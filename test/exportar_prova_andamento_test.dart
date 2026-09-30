import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/execucao_prova.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:app_estudos/features/exportar/exportar_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// B16: prova em andamento fica fora do backup de propósito, mas exportar
/// o backup completo precisa avisar em vez de perdê-la em silêncio.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_exportar_prova_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> abrir(WidgetTester tester, {required bool comProva}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    if (comProva) {
      await tester.runAsync(
        () => Hive.box<Map>(HiveBoxes.execucaoProva).put(
          'atual',
          ExecucaoProva(
            id: 'p1',
            nome: 'Simulado TJ',
            iniciadaEm: DateTime.now(),
            duracaoMinutos: 60,
          ).toJson(),
        ),
      );
    }
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ExportarScreen())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('com prova em andamento, backup completo pede confirmação', (
    tester,
  ) async {
    await abrir(tester, comProva: true);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExportarScreen)),
    );
    expect(container.read(execucaoProvaProvider), isNotNull);

    await tester.tap(find.text('JSON — backup completo'));
    await tester.pumpAndSettle();

    expect(find.text('Prova em andamento'), findsOneWidget);
    expect(find.text('Exportar sem a prova'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Prova em andamento'), findsNothing);
  });

  testWidgets('sem prova em andamento, não há diálogo de prova', (
    tester,
  ) async {
    await abrir(tester, comProva: false);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ExportarScreen)),
    );
    expect(container.read(execucaoProvaProvider), isNull);
    expect(find.text('Prova em andamento'), findsNothing);
  });
}
