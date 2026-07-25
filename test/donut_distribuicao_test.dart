import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/repositories/ambiente_filtros.dart';
import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:app_estudos/features/dashboard/widgets/graficos.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Materia _materia(String id, String nome, int corSlot) => Materia(
      id: id,
      nome: nome,
      corSlot: corSlot,
      criadaEm: DateTime(2026, 1, 1),
    );

/// F3: acima de [maxFatiasDonut] fatias a rosca (PieChart) vira ilegível —
/// DonutDistribuicao troca para barras horizontais. Providers sobrescritos
/// direto (sem Hive): donutProvider/materiasDoAmbienteProvider são Provider
/// simples, sem dependência de box aberto.
void main() {
  Future<void> montar(
    WidgetTester tester, {
    required List<Materia> materias,
    required MinutosPorMateria linhas,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materiasDoAmbienteProvider.overrideWithValue(materias),
          donutProvider.overrideWithValue(linhas),
        ],
        child: const MaterialApp(home: Scaffold(body: DonutDistribuicao())),
      ),
    );
    await tester.pump();
  }

  testWidgets('até maxFatiasDonut matérias renderiza a rosca (PieChart)', (
    tester,
  ) async {
    final materias = [
      for (var i = 0; i < maxFatiasDonut; i++) _materia('m$i', 'Matéria $i', i),
    ];
    final MinutosPorMateria linhas = [
      for (var i = 0; i < maxFatiasDonut; i++)
        (materiaId: 'm$i', minutos: 100 - i * 10),
    ];

    await montar(tester, materias: materias, linhas: linhas);

    expect(find.byType(PieChart), findsOneWidget);
  });

  testWidgets(
    'acima de maxFatiasDonut matérias NÃO renderiza a rosca — usa barras',
    (tester) async {
      final n = maxFatiasDonut + 1;
      final materias = [
        for (var i = 0; i < n; i++) _materia('m$i', 'Matéria $i', i),
      ];
      final MinutosPorMateria linhas = [
        for (var i = 0; i < n; i++) (materiaId: 'm$i', minutos: 100 - i * 5),
      ];

      await montar(tester, materias: materias, linhas: linhas);

      expect(find.byType(PieChart), findsNothing);
      // Uma barra (LinearProgressIndicator) por matéria, no lugar da rosca.
      expect(find.byType(LinearProgressIndicator), findsNWidgets(n));
      expect(find.text('Matéria 0'), findsOneWidget);
    },
  );

  testWidgets('sem dados (total 0) não renderiza rosca nem barras', (
    tester,
  ) async {
    await montar(tester, materias: const [], linhas: const []);

    expect(find.byType(PieChart), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Sem dados'), findsOneWidget);
  });
}
