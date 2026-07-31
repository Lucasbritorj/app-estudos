import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/simulado.dart';
import 'package:app_estudos/features/dashboard/widgets/card_bancas.dart';
import 'package:app_estudos/features/registro/registro_form.dart';
import 'package:app_estudos/features/simulados/simulados_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Widget tests de banca: o campo no formulário de sessão (RegistroForm) e
/// o card de dashboard (CardBancas — não exercitado por nenhum teste
/// existente, já que o wiring em dashboard_screen.dart é aplicado à parte).
/// Mesmo padrão de setUp/tearDown de dashboard_screen_test.dart: Hive num
/// diretório temporário por teste.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_banca_form_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> seedMateria() async {
    final materia = Materia(
      id: 'm1',
      nome: 'AFO',
      corSlot: 0,
      criadaEm: DateTime(2026, 1, 1),
    );
    await Hive.box<Map>(HiveBoxes.materias).put(materia.id, materia.toJson());
  }

  /// Abre o form pelo caminho real de produção (mostrarFormularioRegistro
  /// via showModalBottomSheet) em vez de montar RegistroForm isolado — assim
  /// o Navigator.pop(context, true) do _salvar() tem uma rota de verdade
  /// para fechar (a única rota do MaterialApp não pode ser "popada").
  Future<void> abrirForm(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => mostrarFormularioRegistro(context),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sessão prática com banca "cespe" grava RegistroHora.banca == CEBRASPE',
    (tester) async {
      // Viewport generosa: o bottom sheet isScrollControlled some com boa
      // parte da altura, e o form tem bastante campo (tipo, matéria, tarefa,
      // minutos/data, questões/acertos, banca, comentário, salvar).
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(seedMateria);
      await abrirForm(tester);

      // Prática: só nessa seção existe o bloco de Questões/Acertos/Banca.
      await tester.tap(find.text('Prática (Questões)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AFO').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minutos *'),
        '60',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Questões resolvidas *'),
        '10',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Acertos *'),
        '5',
      );
      await tester.pumpAndSettle();

      final campoBanca = find.byKey(const Key('registro_form_banca'));
      await tester.ensureVisible(campoBanca);
      await tester.enterText(campoBanca, 'cespe');
      await tester.pump();
      // Fecha o overlay de opções do Autocomplete (abriu ao digitar, casando
      // com "CEBRASPE" do catálogo) tirando o foco do campo — senão ele fica
      // por cima de parte da tela e pode interceptar o tap no botão Salvar.
      await tester.tap(find.text('Registrar sessão'));
      await tester.pumpAndSettle();

      final botaoSalvar = find.widgetWithText(FilledButton, 'Salvar registro');
      await tester.ensureVisible(botaoSalvar);
      await tester.runAsync(() async {
        await tester.tap(botaoSalvar);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final salvos = Hive.box<Map>(HiveBoxes.registros).values
          .map((e) => RegistroHora.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(salvos, hasLength(1));
      expect(salvos.first.banca, 'CEBRASPE');
      expect(salvos.first.questoes, 10);
      expect(salvos.first.acertos, 5);
    },
  );

  testWidgets(
    'sessão teórica não mostra campo de banca (não faz sentido sem questões)',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(seedMateria);
      await abrirForm(tester);

      // Tipo inicial já é Teoria — o campo banca não deve existir na árvore.
      expect(find.byKey(const Key('registro_form_banca')), findsNothing);
    },
  );

  testWidgets(
    'banca em branco grava RegistroHora.banca == null (não string vazia)',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(seedMateria);
      await abrirForm(tester);

      await tester.tap(find.text('Prática (Questões)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AFO').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minutos *'),
        '30',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Questões resolvidas *'),
        '12',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Acertos *'),
        '9',
      );
      await tester.pumpAndSettle();

      final botaoSalvar = find.widgetWithText(FilledButton, 'Salvar registro');
      await tester.ensureVisible(botaoSalvar);
      await tester.runAsync(() async {
        await tester.tap(botaoSalvar);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      final salvos = Hive.box<Map>(HiveBoxes.registros).values
          .map((e) => RegistroHora.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(salvos, hasLength(1));
      expect(salvos.first.banca, isNull);
    },
  );

  testWidgets(
    'formulário de simulado com banca "cespe" grava Simulado.banca == '
    'CEBRASPE (smoke test: simulados_screen.dart não tem teste próprio '
    'no repo)',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(seedMateria);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: SimuladosScreen())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Novo simulado ou prova'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nome *'),
        'Simulado teste',
      );

      final campoBanca = find.byKey(const Key('simulado_form_banca'));
      await tester.ensureVisible(campoBanca);
      await tester.enterText(campoBanca, 'cespe');
      await tester.pump();
      // Fecha o overlay do Autocomplete tirando o foco (mesmo motivo do
      // teste de RegistroForm acima).
      await tester.tap(find.text('Resultado por matéria'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AFO').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Questões *'),
        '10',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Acertos *'),
        '7',
      );
      await tester.pumpAndSettle();

      final botaoSalvar = find.widgetWithText(FilledButton, 'Salvar');
      await tester.ensureVisible(botaoSalvar);
      await tester.runAsync(() async {
        await tester.tap(botaoSalvar);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      final salvos = Hive.box<Map>(HiveBoxes.simulados).values
          .map((e) => Simulado.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      expect(salvos, hasLength(1));
      expect(salvos.first.banca, 'CEBRASPE');
    },
  );

  group('CardBancas', () {
    Future<void> montarCard(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CardBancas())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('esconde (SizedBox.shrink) sem banca registrada', (
      tester,
    ) async {
      await montarCard(tester);
      expect(find.text('Desempenho por banca'), findsNothing);
    });

    testWidgets(
      'mostra ranking, destaque do ponto fraco e rodapé de amostra mínima',
      (tester) async {
        await tester.runAsync(() async {
          final m1 = Materia(
            id: 'm1',
            nome: 'AFO',
            corSlot: 0,
            criadaEm: DateTime(2026, 1, 1),
          );
          final m2 = Materia(
            id: 'm2',
            nome: 'Direito Constitucional',
            corSlot: 1,
            criadaEm: DateTime(2026, 1, 1),
          );
          await Hive.box<Map>(HiveBoxes.materias).put(m1.id, m1.toJson());
          await Hive.box<Map>(HiveBoxes.materias).put(m2.id, m2.toJson());

          // 44/84 = 52% — mesmo par banca×matéria do exemplo da spec, e a
          // única banca acima da amostra mínima (10 questões).
          final r1 = RegistroHora(
            id: 'r1',
            data: DateTime(2026, 7, 1),
            materiaId: 'm2',
            tipo: TipoEstudo.pratica,
            minutos: 120,
            questoes: 84,
            acertos: 44,
            banca: 'cespe',
          );
          await Hive.box<Map>(HiveBoxes.registros).put(r1.id, r1.toJson());

          // FGV com só 9 questões: fica no agregado, some do ranking —
          // prova o rodapé "fora do ranking por amostra".
          final r2 = RegistroHora(
            id: 'r2',
            data: DateTime(2026, 7, 2),
            materiaId: 'm1',
            tipo: TipoEstudo.pratica,
            minutos: 60,
            questoes: 9,
            acertos: 8,
            banca: 'FGV',
          );
          await Hive.box<Map>(HiveBoxes.registros).put(r2.id, r2.toJson());
        });

        await montarCard(tester);

        expect(find.text('Desempenho por banca'), findsOneWidget);
        expect(
          find.textContaining(
            'Você acerta 52% em Direito Constitucional na CEBRASPE — '
            '84 questões',
          ),
          findsOneWidget,
        );
        expect(find.text('CEBRASPE'), findsOneWidget);
        expect(find.text('FGV'), findsNothing); // abaixo da amostra mínima
        expect(find.textContaining('fora do ranking'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
