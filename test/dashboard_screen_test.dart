import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/features/dashboard/dashboard_screen.dart';
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
    expect(find.text('O que melhorar hoje'), findsOneWidget);
    expect(find.text('Seu dashboard nasce do primeiro registro'), findsNothing);
  });
}
