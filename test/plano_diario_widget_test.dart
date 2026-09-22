import 'dart:io';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/domain/plano_diario_service.dart';
import 'package:app_estudos/features/plano_diario/plano_diario_repositorio.dart';
import 'package:app_estudos/features/plano_diario/plano_diario_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('plano-teste');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  testWidgets('tela vazia permite configurar e informa ausência de blocos', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PlanoDiarioScreen())),
    );
    expect(find.text('Plano pessoal'), findsOneWidget);
    expect(find.text('Concurso principal'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Gerar proposta'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Gerar proposta'),
          )
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
  test('aceitação repetida preserva dia com sessão e não duplica', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final r = c.read(planoDiarioProvider.notifier);
    final hoje = DateTime(2026, 9, 7);
    final b = BlocoDiario(id: 'b', materiaId: 'm', dia: hoje, motivo: 'teste');
    await r.aceitar({}, PropostaDiaria([b], []), hoje);
    await Hive.box<Map>(HiveBoxes.registros).put(
      'sessao-real',
      RegistroHora(
        id: 'sessao-real',
        data: hoje,
        materiaId: 'm',
        minutos: 15,
      ).toJson(),
    );
    await r.vincular('b', 'sessao-real');
    await r.vincular('b', 'sessao-real');
    final nova = PropostaDiaria([
      BlocoDiario(id: 'novo', materiaId: 'm', dia: hoje, motivo: 'outra'),
    ], []);
    await r.aceitar({}, nova, hoje);
    await r.aceitar({}, nova, hoje);
    expect(c.read(planoDiarioProvider)['blocos'], hasLength(1));
    expect(c.read(planoDiarioProvider)['vinculos'], {'b': 'sessao-real'});
  });
  testWidgets('gera proposta e aceita sem criar registros de estudo', (
    tester,
  ) async {
    final hoje = DateTime.now();
    await tester.runAsync(() async {
      await Hive.box<Map>(HiveBoxes.ambientes).put(
        'a',
        Ambiente(id: 'a', nome: 'Concurso A', criadoEm: hoje).toJson(),
      );
      await Hive.box<Map>(HiveBoxes.materias).put(
        'm',
        Materia(
          id: 'm',
          nome: 'Direito',
          ambienteId: 'a',
          corSlot: 0,
          criadaEm: hoje,
        ).toJson(),
      );
      await Hive.box<Map>(HiveBoxes.config).put('planoDiario', {
        'principal': 'a',
        'dias': {'${hoje.weekday}': 30},
      });
    });
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: PlanoDiarioScreen())),
    );
    await tester.scrollUntilVisible(
      find.text('Gerar proposta'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Gerar proposta'));
    await tester.pumpAndSettle();
    expect(
      Hive.box<Map>(HiveBoxes.config).get('planoDiario')!['blocos'],
      isNull,
    );
    await tester.ensureVisible(find.text('Aceitar plano futuro'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Aceitar plano futuro'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(
      Hive.box<Map>(HiveBoxes.config).get('planoDiario')!['blocos'],
      hasLength(2),
    );
    expect(Hive.box<Map>(HiveBoxes.registros).values, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test(
    'rejeita vínculo sem sessão real e preserva passado no replanejamento',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final r = c.read(planoDiarioProvider.notifier);
      final ontem = DateTime(2026, 9, 6), hoje = DateTime(2026, 9, 7);
      final antigo = BlocoDiario(
        id: 'antigo',
        materiaId: 'm',
        dia: ontem,
        motivo: 'estudo',
      );
      await r.aceitar({}, PropostaDiaria([antigo], []), ontem);
      await expectLater(r.vincular('antigo', 'inventado'), throwsStateError);
      final novo = BlocoDiario(
        id: 'novo',
        materiaId: 'm',
        dia: hoje,
        motivo: 'estudo',
      );
      await r.aceitar({}, PropostaDiaria([novo], []), hoje);
      expect(c.read(planoDiarioProvider)['blocos'], hasLength(2));
      expect(
        (c.read(planoDiarioProvider)['blocos'] as List).first,
        antigo.toJson(),
      );
    },
  );
}
