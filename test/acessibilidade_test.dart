import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/features/dashboard/dashboard_screen.dart';
import 'package:app_estudos/features/dashboard/widgets/card_bancas.dart';
import 'package:app_estudos/features/dashboard/widgets/card_caderno_erros.dart';
import 'package:app_estudos/features/dashboard/widgets/card_edital.dart';
import 'package:app_estudos/features/dashboard/widgets/card_true_retention.dart';
import 'package:app_estudos/features/dashboard/widgets/chama_streak.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Prova de acessibilidade semântica (Q2 — WCAG 2.2): tiles de KPI, gráficos,
/// botões de ação e linhas de card com estado precisam virar UM nó de leitor
/// de tela com texto por extenso, não fragmentos soltos nem abreviação visual
/// (um leitor lê "1h" como "um h"). Setup de Hive copiado de
/// dashboard_screen_test.dart: diretório temporário isolado por teste.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_a11y_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  // Uma matéria, um registro: 95min (1h35) de estudo HOJE com 120 questões e
  // 102 acertos (85% — cruza a régua Nexus de "dominado"). Serve para os 4
  // pontos exigidos: tile "Hoje" (HeroGeral), o donut (só 1 matéria = 100%),
  // e a linha do card de desempenho.
  Future<void> montarComDados(WidgetTester tester) async {
    await tester.runAsync(() async {
      final materia = Materia(
        id: 'm1',
        nome: 'Português',
        corSlot: 0,
        criadaEm: DateTime(2026, 1, 1),
      );
      await Hive.box<Map>(HiveBoxes.materias).put(materia.id, materia.toJson());
      final registro = RegistroHora(
        id: 'r1',
        data: DateTime.now(),
        materiaId: 'm1',
        minutos: 95,
        questoes: 120,
        acertos: 102,
      );
      await Hive.box<Map>(HiveBoxes.registros)
          .put(registro.id, registro.toJson());
    });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: DashboardScreen())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'tile "Hoje" do HeroGeral fala o tempo por extenso, num nó só',
    (tester) async {
      // dispose() precisa ser chamado dentro do próprio corpo do teste — a
      // verificação de handles pendentes do flutter_test roda ANTES dos
      // callbacks de addTearDown, então addTearDown(handle.dispose) aqui
      // seria tarde demais e derrubaria o teste com um erro à parte.
      final handle = tester.ensureSemantics();

      await montarComDados(tester);

      // Antes: "Hoje" e "1h 35min" eram 2 nós soltos, e "1h" seria falado
      // como "um h" — agora é 1 nó com o tempo por extenso.
      expect(find.bySemanticsLabel('Hoje: 1 hora e 35 minutos'), findsOneWidget);

      handle.dispose();
    },
  );

  testWidgets(
    'gráfico de distribuição por matéria resume o dado em texto',
    (tester) async {
      final handle = tester.ensureSemantics();

      await montarComDados(tester);
      // Card do gráfico vive na grade masonry (lazy) — precisa rolar até ele
      // antes de existir no Element tree (mesma técnica de
      // dashboard_screen_test.dart).
      await tester.scrollUntilVisible(
        find.text('Distribuição total por matéria'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      // fl_chart/CustomPaint não falam nada sozinhos; o resumo por extenso
      // (nome + percentual de cada matéria) é o único jeito de um leitor de
      // tela saber o que o gráfico mostra.
      expect(
        find.bySemanticsLabel(
          'Distribuição total por matéria, 1h 35min: Português 100%',
        ),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testWidgets(
    'botão "Registrar sessão" é lido como botão acionável, num nó só',
    (tester) async {
      final handle = tester.ensureSemantics();

      await montarComDados(tester);

      final chip = tester.getSemantics(
        find.widgetWithText(ActionChip, 'Registrar sessão'),
      );
      expect(
        chip,
        isSemantics(label: 'Registrar sessão', isButton: true, hasTapAction: true),
      );

      handle.dispose();
    },
  );

  testWidgets(
    'linha do card de desempenho fala nome, fração, percentual e status juntos',
    (tester) async {
      final handle = tester.ensureSemantics();

      await montarComDados(tester);
      await tester.scrollUntilVisible(
        find.text('Desempenho em questões'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      // Antes: bolinha de cor (muda), nome, ícone de status (mudo) e
      // "102/120 · 85% dominado" formavam nós fragmentados, e "/" seria lido
      // como "barra". Um nó só, por extenso, na ordem do exemplo da tarefa.
      expect(
        find.bySemanticsLabel('Português, 102 de 120, 85%, dominado'),
        findsOneWidget,
      );

      handle.dispose();
    },
  );

  testWidgets(
    'FAB de registro manual tem nome próprio, não só tooltip',
    (tester) async {
      final handle = tester.ensureSemantics();

      await montarComDados(tester);

      // Tooltip expõe a mensagem como propriedade "tooltip" (dica
      // secundária), não como "label" (nome primário) — sem o label
      // explícito um ícone puro (Icons.add) fica mudo para o leitor de tela.
      final fab = tester.getSemantics(find.byType(FloatingActionButton));
      expect(
        fab,
        isSemantics(label: 'Registro manual', isButton: true, hasTapAction: true),
      );

      handle.dispose();
    },
  );

  testWidgets('chama do streak em risco tem rótulo próprio', (tester) async {
    final handle = tester.ensureSemantics();

    // Mount isolado (sem Hive/dashboard): Icon puro não fala nada sozinho.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ChamaAnimada(emRisco: true))),
    );

    expect(
      find.bySemanticsLabel(
        'Chama do streak: hoje em risco, estude para não perder a sequência',
      ),
      findsOneWidget,
    );

    handle.dispose();
  });

  // B18 — vazamento semântico nos cards do dashboard: Semantics(label:) sem
  // excludeSemantics deixava os Text descendentes vazarem e se fundirem ao
  // rótulo customizado (leitor lia o rótulo e depois repetia os fragmentos).
  // Cada teste abaixo monta o card isolado (mesmo padrão de
  // card_prontidao_test.dart) e prova, via tester.getSemantics + isSemantics,
  // que o nó final tem SÓ o rótulo composto — nada repetido ao lado.

  testWidgets(
    'CardDiagnostico: ícone+título falam juntos, sem repetir o título',
    (tester) async {
      final handle = tester.ensureSemantics();

      await montarComDados(tester);

      final node = tester.getSemantics(
        find.text('Fora do ritmo — e a conta chegou'),
      );
      expect(
        node,
        isSemantics(
          label: 'Diagnóstico de hoje: Fora do ritmo — e a conta chegou',
        ),
      );

      handle.dispose();
    },
  );

  testWidgets(
    'CardBancas: linha do ranking fala banca, amostra e taxa juntas',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() async {
        final materia = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(
          HiveBoxes.materias,
        ).put(materia.id, materia.toJson());
        final registro = RegistroHora(
          id: 'r1',
          data: DateTime.now(),
          materiaId: 'm1',
          minutos: 60,
          banca: 'CEBRASPE',
          questoes: 20,
          acertos: 17,
        );
        await Hive.box<Map>(
          HiveBoxes.registros,
        ).put(registro.id, registro.toJson());
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CardBancas())),
        ),
      );
      await tester.pumpAndSettle();

      // Antes: nome da banca, "17/20 questões" ("/" lido como "barra") e
      // "85%" (só a cor carregava o status) eram 3 nós soltos.
      final node = tester.getSemantics(find.text('CEBRASPE'));
      expect(node, isSemantics(label: 'CEBRASPE, 17 de 20 questões, 85%'));

      handle.dispose();
    },
  );

  testWidgets('CardCadernoErros: cada tile fala rótulo e valor juntos', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await tester.runAsync(() async {
      final materia = Materia(
        id: 'm1',
        nome: 'AFO',
        corSlot: 0,
        criadaEm: DateTime(2026, 1, 1),
      );
      await Hive.box<Map>(
        HiveBoxes.materias,
      ).put(materia.id, materia.toJson());
      final questao = QuestaoErrada(
        id: 'q1',
        materiaId: 'm1',
        enunciado: 'Questão dominada',
        criadaEm: DateTime(2026, 1, 1),
        arquivada: true,
      );
      await Hive.box<Map>(
        HiveBoxes.questoesErradas,
      ).put(questao.id, questao.toJson());
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: CardCadernoErros())),
      ),
    );
    await tester.pumpAndSettle();

    // Antes: "0"/"vencem hoje" e "100%"/"recuperação" eram Text irmãos
    // soltos (mesmo problema de _Percentual em card_prontidao.dart) — a
    // tinta de fundo/borda do tile não fala nada sozinha pro leitor.
    final nodeFila = tester.getSemantics(find.text('0'));
    expect(nodeFila, isSemantics(label: 'vencem hoje: 0'));
    final nodeTaxa = tester.getSemantics(find.text('100%'));
    expect(nodeTaxa, isSemantics(label: 'recuperação: 100%'));

    handle.dispose();
  });

  testWidgets(
    'CardTrueRetention: cabeçalho e linha por matéria falam num nó só',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() async {
        final materia = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(
          HiveBoxes.materias,
        ).put(materia.id, materia.toJson());
        final registro = RegistroHora(
          id: 'r1',
          data: DateTime.now(),
          materiaId: 'm1',
          minutos: 20,
          tarefa: 'Revisão: Aula 1',
          questoes: 20,
          acertos: 17,
        );
        await Hive.box<Map>(
          HiveBoxes.registros,
        ).put(registro.id, registro.toJson());
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CardTrueRetention())),
        ),
      );
      await tester.pumpAndSettle();

      final nodeHeader = tester.getSemantics(
        find.text('Retenção nas revisões'),
      );
      expect(
        nodeHeader,
        isSemantics(label: 'Retenção nas revisões: 85% geral'),
      );
      final nodeLinha = tester.getSemantics(find.text('AFO'));
      expect(nodeLinha, isSemantics(label: 'AFO, 85%, 20 questões'));

      handle.dispose();
    },
  );

  testWidgets(
    'CardEdital: percentual e base de tópicos falam num nó só',
    (tester) async {
      final handle = tester.ensureSemantics();

      await tester.runAsync(() async {
        final materia = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(
          HiveBoxes.materias,
        ).put(materia.id, materia.toJson());
        const topico = Topico(id: 't1', materiaId: 'm1', nome: 'Lei 8.112');
        await Hive.box<Map>(
          HiveBoxes.topicos,
        ).put(topico.id, topico.toJson());
      });

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CardEdital())),
        ),
      );
      await tester.pumpAndSettle();

      // Denominador (o "de 1 tópico do edital") é obrigatório ao lado do
      // percentual (ver comentário de CardEdital) — precisa continuar no
      // MESMO nó, não sumir nem virar fragmento solto.
      final node = tester.getSemantics(find.text('0%'));
      expect(node, isSemantics(label: '0% de 1 tópico do edital'));

      handle.dispose();
    },
  );
}
