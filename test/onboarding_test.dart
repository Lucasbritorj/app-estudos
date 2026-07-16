import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/repositories/configuracoes_repositorio.dart';
import 'package:app_estudos/features/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Onboarding multi-passo (item 8): flag persistida, navegação entre passos
/// e o caminho de conclusão que grava no box.
void main() {
  group('Configuracoes.onboardingConcluido', () {
    test('padrão falso na primeira execução', () {
      expect(const Configuracoes().onboardingConcluido, isFalse);
    });

    test('backup antigo (sem o campo) assume falso', () {
      expect(Configuracoes.fromJson(const {}).onboardingConcluido, isFalse);
    });

    test('roundtrip preserva true', () {
      final json = const Configuracoes(onboardingConcluido: true).toJson();
      expect(Configuracoes.fromJson(json).onboardingConcluido, isTrue);
    });
  });

  group('persistência da conclusão', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hive_onboarding_');
      Hive.init(dir.path);
      await HiveBoxes.openAll();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test('salvar concluído persiste no box e sobrevive a novo container',
        () async {
      final c1 = ProviderContainer();
      addTearDown(c1.dispose);
      await c1
          .read(configuracoesProvider.notifier)
          .salvar(const Configuracoes(onboardingConcluido: true));
      expect(c1.read(configuracoesProvider).onboardingConcluido, isTrue);

      // Novo container reconstrói o Notifier a partir do box.
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      expect(c2.read(configuracoesProvider).onboardingConcluido, isTrue);
    });
  });

  testWidgets('avança passo a passo até o botão Começar', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: OnboardingScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bem-vindo ao Meu Caminho Aprovado'), findsOneWidget);
    expect(find.text('Próximo'), findsOneWidget);
    expect(find.text('Pular'), findsOneWidget);

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    expect(find.text('Registre cada sessão'), findsOneWidget);

    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Próximo'));
    await tester.pumpAndSettle();

    // Último passo troca o rótulo do botão.
    expect(find.text('Nunca esqueça o que estudou'), findsOneWidget);
    expect(find.text('Começar'), findsOneWidget);
    expect(find.text('Próximo'), findsNothing);
  });
}
