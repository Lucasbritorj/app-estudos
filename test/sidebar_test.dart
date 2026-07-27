import 'dart:io';

import 'package:app_estudos/app.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/repositories/configuracoes_repositorio.dart';
import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Sidebar colapsável (F5): estado persiste em Configuracoes.sidebarColapsada
/// e o toggle alterna 240<->72px sem overflow de layout.
void main() {
  group('Configuracoes.sidebarColapsada', () {
    test('padrão falso', () {
      expect(const Configuracoes().sidebarColapsada, isFalse);
    });

    test('backup antigo (sem o campo) assume falso', () {
      expect(Configuracoes.fromJson(const {}).sidebarColapsada, isFalse);
    });

    test('roundtrip preserva true', () {
      final json = const Configuracoes(sidebarColapsada: true).toJson();
      expect(Configuracoes.fromJson(json).sidebarColapsada, isTrue);
    });
  });

  group('toggle da sidebar (widget)', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hive_sidebar_');
      Hive.init(dir.path);
      await HiveBoxes.openAll();
      await HiveBoxes.migrarAmbientes();
      // Onboarding já concluído: pula direto pro shell com a sidebar.
      await Hive.box<Map>(HiveBoxes.config).put(
        'config',
        const Configuracoes(onboardingConcluido: true).toJson(),
      );
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    testWidgets('colapsa ao tocar o botão: largura 240->72 e persiste',
        (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // hojeProvider.overrideWithValue: sem isto o AppEstudos real (via
      // Dashboard) constrói o hojeProvider de verdade, que agenda um Timer
      // (M-06) até a meia-noite seguinte. UncontrolledProviderScope não
      // dispõe o container sozinho (ao contrário de ProviderScope) — o
      // widget tree é desmontado pelo framework de teste ANTES do
      // `addTearDown(container.dispose)` rodar, então o Timer real ainda
      // vivo dispara "A Timer is still pending" no fim do teste.
      final container = ProviderContainer(
        overrides: [hojeProvider.overrideWithValue(DateTime(2026, 7, 16))],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AppEstudos(),
        ),
      );
      await tester.pumpAndSettle();

      // Expandido: logo com texto, largura 240, tooltip "Colapsar menu".
      expect(find.byKey(const Key('app-sidebar')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('app-sidebar'))).width,
        240,
      );
      expect(find.text('Meu Caminho\nAprovado'), findsOneWidget);
      expect(find.byTooltip('Colapsar menu'), findsOneWidget);
      expect(container.read(configuracoesProvider).sidebarColapsada, isFalse);

      // Escrita real no Hive: fake-async do testWidgets nunca entrega esse
      // await sozinha, precisa de runAsync (mesmo padrão do resto da suíte).
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Colapsar menu'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      // Colapsado: só ícones, largura 72, tooltip inverte, texto some.
      expect(tester.getSize(find.byKey(const Key('app-sidebar'))).width, 72);
      expect(find.text('Meu Caminho\nAprovado'), findsNothing);
      expect(find.byTooltip('Expandir menu'), findsOneWidget);
      // Rótulo migrou pro Tooltip do item — continua acessível, só não
      // ocupa mais espaço horizontal.
      expect(find.byTooltip('Dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Persistiu no Configuracoes.
      expect(container.read(configuracoesProvider).sidebarColapsada, isTrue);

      // Alterna de volta: expande de novo.
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Expandir menu'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(const Key('app-sidebar'))).width, 240);
      expect(container.read(configuracoesProvider).sidebarColapsada, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
