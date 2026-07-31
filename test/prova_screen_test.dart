import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/execucao_prova.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/simulado.dart';
import 'package:app_estudos/features/simulados/prova_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Widget tests do modo prova (setup -> execução -> correção -> resultado).
/// Mesmo padrão de setUp/tearDown de dashboard_screen_test.dart: Hive num
/// diretório temporário por teste.
///
/// Escritas reais no Hive disparadas por tap (iniciar prova, marcar
/// resposta, corrigir e salvar) usam `tester.runAsync` — mesma armadilha
/// documentada em caderno_screen_test.dart: a zona fake-async do
/// `testWidgets` nunca entrega a conclusão de um `await` de I/O real.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_prova_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProvaScreen())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'prova de 3 questões: marcar respostas, corrigir e salvar simulado + '
    'questões erradas + registro de hora',
    (tester) async {
      // Viewport generosa: a folha de respostas e a tela de correção têm
      // bastante campo por questão.
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await montar(tester);

      // --- Setup: 3 questões, 60 minutos, sem faixas por matéria (cai no
      // bucket "não classificada" — caminho mais simples do formulário, o
      // agrupamento por matéria já tem cobertura no teste de domínio).
      await tester.enterText(
        find.byKey(const Key('prova_setup_nome')),
        'Simulado teste',
      );
      await tester.enterText(
        find.byKey(const Key('prova_setup_num_questoes')),
        '3',
      );
      await tester.enterText(
        find.byKey(const Key('prova_setup_duracao')),
        '60',
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('prova_setup_iniciar')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.text('Simulado teste'), findsOneWidget); // AppBar da execução

      // --- Execução: questão 1 = A (vai acertar), questão 2 = B (vai
      // errar), questão 3 fica em branco (vai errar por omissão).
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('resposta_1_A')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('resposta_2_B')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(find.text('2/3 respondidas'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('prova_finalizar')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // --- Correção: cola o gabarito "AAB" — bate com a questão 1
      // (acerto), erra a 2 (gabarito A, candidato marcou B) e a 3 (gabarito
      // B, candidato deixou em branco).
      expect(find.text('Corrigir prova'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('prova_colar_gabarito')),
        'AAB',
      );
      // "Aplicar" agora também persiste o gabarito no Hive (B12,
      // fire-and-forget) — mesma ressalva do topo do arquivo sobre
      // escritas reais precisarem de runAsync.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('prova_aplicar_gabarito')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('prova_corrigir_salvar')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // --- Resultado: 1 acerto, 2 erros, 1 em branco, 0 sem gabarito
      // (as 3 questões receberam gabarito via "Aplicar") — B10.
      expect(find.text('Resultado'), findsOneWidget);
      expect(
        find.textContaining(
          '1 acerto · 2 erros · 1 questão em branco · 0 questões sem gabarito',
        ),
        findsOneWidget,
      );

      final simulados = Hive.box<Map>(HiveBoxes.simulados).values
          .map((e) => Simulado.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(simulados, hasLength(1));
      expect(simulados.first.nome, 'Simulado teste');
      expect(simulados.first.totalQuestoes, 3);
      expect(simulados.first.totalAcertos, 1);

      final erradas = Hive.box<Map>(HiveBoxes.questoesErradas).values
          .map((e) => QuestaoErrada.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(erradas, hasLength(2));
      expect(erradas.every((q) => q.origem == OrigemQuestao.simulado), isTrue);
      expect(
        erradas.every((q) => q.simuladoId == simulados.first.id),
        isTrue,
      );

      final registros = Hive.box<Map>(HiveBoxes.registros).values
          .map((e) => RegistroHora.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(registros, hasLength(1));
      expect(registros.first.tipo, TipoEstudo.pratica);
      expect(registros.first.questoes, 3);
      expect(registros.first.acertos, 1);

      // A execução ativa foi encerrada — não sobra rascunho no Hive.
      expect(Hive.box<Map>(HiveBoxes.execucaoProva).isEmpty, isTrue);

      // Concluir sai da tela sem exceção pendente.
      await tester.tap(find.byKey(const Key('prova_concluir')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'execução ativa persistida no Hive é retomada direto na execução ao '
    'reabrir a tela (sobrevive a fechar o app)',
    (tester) async {
      // Simula "app fechado no meio da prova": grava a execução direto no
      // Hive (sem passar pela tela) e monta — deve abrir direto na
      // execução em andamento, não no setup.
      await tester.runAsync(() async {
        final execucao = ExecucaoProva(
          id: 'exec1',
          nome: 'Prova retomada',
          iniciadaEm: DateTime.now(),
          duracaoMinutos: 60,
          itens: [ItemProva(numero: 1), ItemProva(numero: 2)],
        );
        await Hive.box<Map>(
          HiveBoxes.execucaoProva,
        ).put('atual', execucao.toJson());
      });

      await montar(tester);

      expect(find.text('Prova retomada'), findsOneWidget);
      expect(find.byKey(const Key('prova_setup_nome')), findsNothing);
      expect(find.text('0/2 respondidas'), findsOneWidget);

      // _ProvaExecucao mantém um Timer.periodic pro relógio regressivo —
      // sem desmontar a árvore antes do fim do teste, o framework acusa
      // timer pendente (mesmo cuidado de qualquer tela com countdown ativo
      // em widget test).
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'execução ativa já finalizada (finalizadaEm setado) é retomada na '
    'tela de correção, não na execução',
    (tester) async {
      await tester.runAsync(() async {
        final agora = DateTime.now();
        final execucao = ExecucaoProva(
          id: 'exec2',
          nome: 'Prova aguardando correção',
          iniciadaEm: agora.subtract(const Duration(minutes: 30)),
          duracaoMinutos: 60,
          itens: [ItemProva(numero: 1, respostaMarcada: 'A')],
          finalizadaEm: agora,
        );
        await Hive.box<Map>(
          HiveBoxes.execucaoProva,
        ).put('atual', execucao.toJson());
      });

      await montar(tester);

      expect(find.text('Corrigir prova'), findsOneWidget);
      expect(find.byKey(const Key('prova_colar_gabarito')), findsOneWidget);
    },
  );

  testWidgets(
    'B12: gabarito digitado na correção é persistido no Hive '
    '(fire-and-forget) e sobrevive a fechar e reabrir a tela',
    (tester) async {
      await tester.runAsync(() async {
        final agora = DateTime.now();
        final execucao = ExecucaoProva(
          id: 'exec3',
          nome: 'Prova para corrigir depois',
          iniciadaEm: agora.subtract(const Duration(minutes: 30)),
          duracaoMinutos: 60,
          itens: [
            ItemProva(numero: 1, respostaMarcada: 'A'),
            ItemProva(numero: 2, respostaMarcada: 'B'),
          ],
          finalizadaEm: agora,
        );
        await Hive.box<Map>(
          HiveBoxes.execucaoProva,
        ).put('atual', execucao.toJson());
      });

      await montar(tester);
      expect(find.text('Corrigir prova'), findsOneWidget);

      // Digita nos dois campos SEM apertar "Corrigir e salvar" — cada
      // keystroke já deve gravar no Hive (mesmo padrão fire-and-forget de
      // _marcar em _ProvaExecucaoState).
      await tester.runAsync(() async {
        await tester.enterText(find.byKey(const Key('prova_gabarito_1')), 'A');
        await tester.pump();
        await tester.enterText(find.byKey(const Key('prova_gabarito_2')), 'C');
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      final raw = Hive.box<Map>(HiveBoxes.execucaoProva).get('atual');
      final persistida = ExecucaoProva.fromJson(
        Map<String, dynamic>.from(raw!),
      );
      expect(persistida.itens[0].gabarito, 'A');
      expect(persistida.itens[1].gabarito, 'C');

      // "Fecha o app": desmonta a árvore inteira (o ProviderScope some
      // junto) e depois "reabre": monta uma ProvaScreen nova, com um
      // ExecucaoProvaController novo lendo do zero direto do Hive.
      await tester.pumpWidget(const SizedBox());
      await montar(tester);

      expect(find.text('Corrigir prova'), findsOneWidget);
      final campo1 = tester.widget<TextField>(
        find.byKey(const Key('prova_gabarito_1')),
      );
      expect(campo1.controller!.text, 'A');
      final campo2 = tester.widget<TextField>(
        find.byKey(const Key('prova_gabarito_2')),
      );
      expect(campo2.controller!.text, 'C');
    },
  );

  testWidgets(
    'B10: pluralização no resultado cobre singular/plural nos limites '
    '0, 1 e 2 (acertos=0, erros=1, em branco=2, sem gabarito=1)',
    (tester) async {
      await tester.runAsync(() async {
        final agora = DateTime.now();
        // item 1: sem resposta, COM gabarito -> em branco + erro (apurada).
        // item 2: sem resposta, SEM gabarito -> só em branco (fora da
        // apuração, vira "sem gabarito").
        final execucao = ExecucaoProva(
          id: 'exec_plural',
          nome: 'Prova limites',
          iniciadaEm: agora.subtract(const Duration(minutes: 10)),
          duracaoMinutos: 60,
          itens: [ItemProva(numero: 1, gabarito: 'A'), ItemProva(numero: 2)],
          finalizadaEm: agora,
        );
        await Hive.box<Map>(
          HiveBoxes.execucaoProva,
        ).put('atual', execucao.toJson());
      });

      await montar(tester);
      expect(find.text('Corrigir prova'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('prova_corrigir_salvar')));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Resultado'), findsOneWidget);
      expect(
        find.textContaining(
          '0 acertos · 1 erro · 2 questões em branco · 1 questão sem gabarito',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'B11: correção com muitas questões usa lista lazy — campo fora da '
    'viewport não é construído, e o texto digitado sobrevive a rolar pra '
    'longe e voltar (controller não é recriado a cada build)',
    (tester) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        final agora = DateTime.now();
        final execucao = ExecucaoProva(
          id: 'exec_lazy',
          nome: 'Prova grande',
          iniciadaEm: agora.subtract(const Duration(minutes: 10)),
          duracaoMinutos: 60,
          itens: [for (var i = 1; i <= 60; i++) ItemProva(numero: i)],
          finalizadaEm: agora,
        );
        await Hive.box<Map>(
          HiveBoxes.execucaoProva,
        ).put('atual', execucao.toJson());
      });

      await montar(tester);
      expect(find.text('Corrigir prova'), findsOneWidget);

      // ListView.builder de verdade: a questão 60 não existe na árvore
      // antes de rolar até ela — um ListView eager teria as 60 de uma vez.
      expect(find.byKey(const Key('prova_gabarito_60')), findsNothing);

      await tester.runAsync(() async {
        await tester.enterText(find.byKey(const Key('prova_gabarito_1')), 'A');
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // O Scrollable do ListView.builder é o PRIMEIRO descendente da lista
      // com essa chave — o TextField "colar gabarito" (fora da lista) e os
      // TextField de cada questão (dentro dela) também têm Scrollable
      // interno próprio, então find.byType(Scrollable) sozinho é ambíguo.
      final listaScrollable = find
          .descendant(
            of: find.byKey(const Key('prova_correcao_lista')),
            matching: find.byType(Scrollable),
          )
          .first;

      await tester.scrollUntilVisible(
        find.byKey(const Key('prova_gabarito_60')),
        500,
        scrollable: listaScrollable,
      );
      expect(find.byKey(const Key('prova_gabarito_60')), findsOneWidget);
      // Rolou tão longe que a questão 1 saiu da árvore.
      expect(find.byKey(const Key('prova_gabarito_1')), findsNothing);

      await tester.scrollUntilVisible(
        find.byKey(const Key('prova_gabarito_1')),
        -500,
        scrollable: listaScrollable,
      );
      // Volta pro topo: se o controller fosse recriado a cada build do
      // ListView.builder, o texto digitado antes de rolar teria sumido.
      final campo1 = tester.widget<TextField>(
        find.byKey(const Key('prova_gabarito_1')),
      );
      expect(campo1.controller!.text, 'A');

      // Sai da tela: dispose() percorre só os controllers realmente
      // criados até aqui — sem exceção de controller usado após descartado.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
