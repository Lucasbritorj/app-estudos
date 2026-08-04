import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/features/dashboard/dashboard_screen.dart';
import 'package:app_estudos/features/dashboard/widgets/tiles_resumo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Smoke test do dashboard: garante que a composição (tela-índice +
/// widgets/ por card) monta nos dois estados — vazio e com dados.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_dashboard_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: DashboardScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sem registros mostra estado vazio com os dois caminhos',
      (tester) async {
    await montar(tester);

    expect(
        find.text('Seu dashboard nasce do primeiro registro'), findsOneWidget);
    expect(find.text('Registrar primeira sessão'), findsOneWidget);
    expect(find.text('Ou estude agora com o cronômetro'), findsOneWidget);
  });

  testWidgets('com registro monta hero e cards sem erro de composição',
      (tester) async {
    // IO real do Hive dentro de testWidgets precisa de runAsync — a zona
    // fake-async do teste nunca entrega a conclusão do put e o await trava.
    await tester.runAsync(() async {
      final materia = Materia(
          id: 'm1', nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026, 1, 1));
      await Hive.box<Map>(HiveBoxes.materias)
          .put(materia.id, materia.toJson());
      final registro = RegistroHora(
          id: 'r1', data: DateTime.now(), materiaId: 'm1', minutos: 60);
      await Hive.box<Map>(HiveBoxes.registros)
          .put(registro.id, registro.toJson());
    });

    await montar(tester);

    expect(find.textContaining('Meta da semana'), findsOneWidget);
    expect(find.text('Hoje'), findsWidgets);
    // O diagnóstico do dia abre a leitura, acima da grade. Com 1h em 1 único
    // dia dos últimos 14, a régua de constância crava o veredito crítico —
    // determinístico, então dá para afirmar o título exato.
    expect(find.text('Fora do ritmo — e a conta chegou'), findsOneWidget);
    // "O que melhorar hoje" virou seção do card unificado "Plano de hoje",
    // no sliver de topo — mas o card é alto (missão + quests + insights) e a
    // seção continua podendo nascer fora da viewport. O scroll segue valendo.
    await tester.scrollUntilVisible(
      find.text('O que melhorar hoje'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('O que melhorar hoje'), findsOneWidget);
    expect(find.text('PLANO DE HOJE'), findsOneWidget);
    expect(find.text('Seu dashboard nasce do primeiro registro'), findsNothing);
  });

  testWidgets('em tela larga a grade masonry (3 colunas) monta sem overflow',
      (tester) async {
    // Superfície larga o bastante para o modo 3 colunas (>= 1360) e alta o
    // bastante para caber o topo (hero + TilesResumo + diagnóstico) mais os
    // primeiros cards da grade sem rolar. Prova que o CustomScrollView +
    // SliverMasonryGrid recebe altura limitada e os cards da grade rendem
    // sem exceção de layout. reset() volta ao padrão no fim.
    tester.view.physicalSize = const Size(1500, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final materia = Materia(
          id: 'm1', nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026, 1, 1));
      await Hive.box<Map>(HiveBoxes.materias)
          .put(materia.id, materia.toJson());
      final registro = RegistroHora(
          id: 'r1', data: DateTime.now(), materiaId: 'm1', minutos: 60);
      await Hive.box<Map>(HiveBoxes.registros)
          .put(registro.id, registro.toJson());
    });

    await montar(tester);

    // pumpAndSettle já teria estourado com exceção de layout; reforço achando
    // cards que vivem DENTRO da grade. "O que melhorar hoje" saiu daqui: virou
    // seção do card unificado, no topo em largura total.
    expect(tester.takeException(), isNull);
    expect(find.text('Evolução — últimos 14 dias'), findsOneWidget);
    expect(find.text('Distribuição total por matéria'), findsOneWidget);
    expect(find.text('Horas da semana por matéria'), findsOneWidget);
  });

  testWidgets(
      'TilesResumo fica no sliver de topo, acima do primeiro card da grade',
      (tester) async {
    // Viewport alta o bastante pra HeroGeral + TilesResumo + o primeiro card
    // da grade caberem sem rolar — prova que os tiles migraram do rodapé
    // (onde dependiam de scroll) pra área nobre, junto do hero.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      final materia = Materia(
          id: 'm1', nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026, 1, 1));
      await Hive.box<Map>(HiveBoxes.materias)
          .put(materia.id, materia.toJson());
      final registro = RegistroHora(
          id: 'r1', data: DateTime.now(), materiaId: 'm1', minutos: 60);
      await Hive.box<Map>(HiveBoxes.registros)
          .put(registro.id, registro.toJson());
    });

    await montar(tester);

    expect(find.byType(TilesResumo), findsOneWidget);
    // Âncora da grade: `CardMelhorarHoje` era o primeiro item e sumiu na fusão
    // do "Plano de hoje". O gráfico de horas da semana serve melhor como
    // referência — é o único card da grade que renderiza sem condição de
    // conteúdo, então não some por causa da massa de teste.
    final cardDaGrade = find.text('Horas da semana por matéria');
    expect(cardDaGrade, findsOneWidget);
    // Se TilesResumo está ACIMA dele (dy menor), então saiu do rodapé da grade
    // e está no sliver de topo, como pedido.
    final yTiles = tester.getTopLeft(find.byType(TilesResumo)).dy;
    final yPrimeiroCardDaGrade = tester.getTopLeft(cardDaGrade).dy;
    expect(yTiles, lessThan(yPrimeiroCardDaGrade));

    // O card unificado fica ACIMA dos tiles: ação antes de estatística.
    expect(
      tester.getTopLeft(find.text('PLANO DE HOJE')).dy,
      lessThan(yTiles),
    );
  });
}
