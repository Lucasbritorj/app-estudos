import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/features/edital/edital_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Smoke test da tela do edital verticalizado: monta nos dois estados —
/// base vazia (sem tópico cadastrado) e com dados — sem exceção de
/// composição. Padrão de setUp/tearDown copiado de dashboard_screen_test.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_edital_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> montar(WidgetTester tester) async {
    // Viewport alto o bastante pra caber donut + lista de matérias + seção
    // de buracos sem depender de rolagem — é um smoke test de composição,
    // não de scroll (mesmo raciocínio de dashboard_screen_test.dart).
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: EditalScreen())),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('sem tópico cadastrado mostra estado vazio, nunca 0%', (
    tester,
  ) async {
    await montar(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Importe o edital para ver a cobertura'), findsOneWidget);
    expect(find.text('Importar edital'), findsOneWidget);
    // Trava a regra "NUNCA mostrar 0%" quando não há tópico cadastrado —
    // sem isto a tela acusaria um atraso que não existe.
    expect(find.textContaining('0%'), findsNothing);
  });

  testWidgets(
    'com edital importado monta cobertura, matéria e buracos sem erro',
    (tester) async {
      await tester.runAsync(() async {
        final materia = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          peso: 2,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(
          HiveBoxes.materias,
        ).put(materia.id, materia.toJson());

        // Peso 1 dominado + peso 4 intocado: cobertura geral = 1/5 = 20%.
        final dominado = const Topico(
          id: 't1',
          materiaId: 'm1',
          nome: 'Tópico dominado',
          peso: 1,
          concluido: true,
        );
        final intocado = const Topico(
          id: 't2',
          materiaId: 'm1',
          nome: 'Tópico intocado',
          peso: 4,
        );
        await Hive.box<Map>(
          HiveBoxes.topicos,
        ).put(dominado.id, dominado.toJson());
        await Hive.box<Map>(
          HiveBoxes.topicos,
        ).put(intocado.id, intocado.toJson());

        final registro = RegistroHora(
          id: 'r1',
          data: DateTime(2026, 1, 5),
          materiaId: 'm1',
          topicoId: 't1',
          minutos: 60,
        );
        await Hive.box<Map>(
          HiveBoxes.registros,
        ).put(registro.id, registro.toJson());
      });

      await montar(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Cobertura do edital'), findsOneWidget);
      expect(find.text('AFO'), findsOneWidget);
      expect(find.text('Próximos buracos'), findsOneWidget);
      // peso da matéria (2) × peso do tópico dominado (1) = 2; peso da
      // matéria (2) × peso do tópico intocado (4) = 8 -> dominado 2/10.
      expect(find.textContaining('20%'), findsWidgets);
      // O buraco (tópico intocado) explica a prioridade por extenso.
      expect(find.textContaining('peso 2 × tópico 4 = 8'), findsOneWidget);

      // Expande a matéria e confere a linha do tópico intocado.
      await tester.tap(find.text('AFO'));
      await tester.pumpAndSettle();
      expect(find.text('Tópico intocado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('matéria sem tópico não aparece na lista por matéria', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final comEdital = Materia(
        id: 'm1',
        nome: 'AFO',
        corSlot: 0,
        criadaEm: DateTime(2026, 1, 1),
      );
      final semEdital = Materia(
        id: 'm2',
        nome: 'Português',
        corSlot: 1,
        criadaEm: DateTime(2026, 1, 1),
      );
      await Hive.box<Map>(
        HiveBoxes.materias,
      ).put(comEdital.id, comEdital.toJson());
      await Hive.box<Map>(
        HiveBoxes.materias,
      ).put(semEdital.id, semEdital.toJson());
      final t = const Topico(id: 't1', materiaId: 'm1', nome: 'Único tópico');
      await Hive.box<Map>(HiveBoxes.topicos).put(t.id, t.toJson());
    });

    await montar(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('AFO'), findsOneWidget);
    expect(find.text('Português'), findsNothing);
  });
}
