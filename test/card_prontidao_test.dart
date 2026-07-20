import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/features/dashboard/widgets/card_prontidao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Card de prontidão: some sem data de prova; com ambiente ativo datado,
/// mostra hoje→projeção e a chamada de calibração do cold start.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_prontidao_');
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
      child: MaterialApp(
          home: Scaffold(body: CardProntidao())),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('sem ambiente ativo com data de prova: card some',
      (tester) async {
    await montar(tester);
    expect(find.text('Prontidão para a prova'), findsNothing);
  });

  testWidgets('com prova marcada mostra projeção e pede calibração',
      (tester) async {
    await tester.runAsync(() async {
      final ambiente = Ambiente(
        id: 'amb1',
        nome: 'SEFAZ',
        criadoEm: DateTime(2026, 1, 1),
        dataProva: DateTime.now().add(const Duration(days: 90)),
      );
      await Hive.box<Map>(HiveBoxes.ambientes)
          .put(ambiente.id, ambiente.toJson());
      final materia = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          ambienteId: 'amb1',
          criadaEm: DateTime(2026, 1, 1));
      await Hive.box<Map>(HiveBoxes.materias)
          .put(materia.id, materia.toJson());
      await Hive.box<Map>(HiveBoxes.config).put('config',
          const Configuracoes(ambienteAtivoId: 'amb1').toJson());
    });

    await montar(tester);

    expect(find.text('Prontidão para a prova'), findsOneWidget);
    expect(find.text('Hoje'), findsOneWidget);
    expect(find.text('Na prova (ajustada)'), findsOneWidget);
    // Faixa de confiança nova: % do peso com evidência.
    expect(find.textContaining('do peso com evidência'), findsOneWidget);
    expect(find.textContaining('faltam'), findsOneWidget);
    // Sem questões registradas: matéria entra na chamada de calibração.
    expect(find.textContaining('registre 10+'), findsOneWidget);
    // Sem cronograma: aviso de ritmo zero.
    expect(find.textContaining('Sem cronograma semanal'), findsOneWidget);
  });
}
