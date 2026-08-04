import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/simulado.dart';
import 'package:app_estudos/features/dashboard/widgets/card_simulados.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Acessibilidade do card de simulados.
///
/// O card inteiro era um `InkWell` anônimo: o leitor de tela não tinha ponto
/// de entrada nomeado, só os fragmentos de dentro. Diferente de
/// `CardForecastRevisao`, aqui o rótulo NÃO usa `excludeSemantics` — as linhas
/// têm nome, data, acertos e taxa, e apagá-las da árvore seria regressão pior
/// que o bug (lição B18).
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_simul_a11y_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Simulado simulado(
    String id,
    DateTime data, {
    required int questoes,
    required int acertos,
  }) => Simulado(
    id: id,
    ambienteId: 'geral',
    tipo: TipoSimulado.simulado,
    nome: 'Simulado $id',
    data: data,
    resultados: [
      ResultadoMateria(materiaId: 'm1', questoes: questoes, acertos: acertos),
    ],
  );

  Future<ProviderContainer> montar(
    WidgetTester tester,
    List<Simulado> simulados,
  ) async {
    await tester.runAsync(() async {
      for (final s in simulados) {
        await Hive.box<Map>(HiveBoxes.simulados).put(s.id, s.toJson());
      }
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: CardSimulados())),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('card ganha ponto de entrada nomeado', (tester) async {
    final handle = tester.ensureSemantics();
    await montar(tester, [
      simulado('a', DateTime(2026, 7, 20), questoes: 100, acertos: 60),
    ]);

    // Singular concorda: "1 registrado", não "1 registrados". Sem variação
    // (só um simulado), o rótulo não inventa comparação.
    expect(
      find.bySemanticsLabel('Simulados e provas: 1 registrado. Abrir lista'),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('variação sai por extenso, não como "pp"', (tester) async {
    final handle = tester.ensureSemantics();
    // `SimuladosRepositorio.comparar` ordena por data DESC, então
    // `simulados.first` é o mais recente ('novo') e `[1]` o anterior.
    // 70% contra 60% = +10 pontos percentuais.
    await montar(tester, [
      simulado('velho', DateTime(2026, 7, 10), questoes: 100, acertos: 60),
      simulado('novo', DateTime(2026, 7, 20), questoes: 100, acertos: 70),
    ]);

    expect(
      find.bySemanticsLabel(
        'Simulados e provas: 2 registrados, variação de mais 10 pontos '
        'percentuais no último. Abrir lista',
      ),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('queda fala "menos", sem sinal gráfico', (tester) async {
    final handle = tester.ensureSemantics();
    await montar(tester, [
      simulado('velho', DateTime(2026, 7, 10), questoes: 100, acertos: 80),
      simulado('novo', DateTime(2026, 7, 20), questoes: 100, acertos: 65),
    ]);

    expect(
      find.bySemanticsLabel(RegExp('variação de menos 15 pontos percentuais')),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('o conteúdo das linhas CONTINUA explorável', (tester) async {
    final handle = tester.ensureSemantics();
    await montar(tester, [
      simulado('a', DateTime(2026, 7, 20), questoes: 100, acertos: 60),
      simulado('b', DateTime(2026, 7, 15), questoes: 50, acertos: 40),
    ]);

    // A contraprova da decisão: com `excludeSemantics` no card estes nós
    // sumiriam da árvore. O rótulo do botão convive com eles, não os substitui.
    expect(find.text('Simulado a'), findsOneWidget);
    expect(find.text('Simulado b'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Simulado a')).label,
      contains('Simulado a'),
      reason: 'a linha precisa continuar tendo nó próprio',
    );

    handle.dispose();
  });
}
