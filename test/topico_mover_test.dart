import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/application/topico_use_case.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:app_estudos/features/materias/topicos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// B6 — mover tópico na hierarquia sem excluir. Três blocos:
/// 1) `TopicoUseCase.podeMoverPara` pura (sem Hive) nos 4 cenários pedidos;
/// 2) mesma validação + gravação real via Hive (o padrão que
///    topicos_screen.dart usa: checar `podeMoverPara` e então
///    `topicosProvider.notifier.salvar(topico.copyWith(...))` direto —
///    mesmo setUp/tearDown de test/materia_cascata_test.dart);
/// 3) fluxo completo pela UI (setUp/tearDown igual a
///    test/dashboard_screen_test.dart; gravação real via runAsync igual a
///    test/banca_form_test.dart).
Topico _t(String id, {String? pai, String materiaId = 'm1', String? nome}) =>
    Topico(id: id, materiaId: materiaId, parentId: pai, nome: nome ?? id);

/// Espelha o `_mover` privado de topicos_screen.dart: revalida
/// `podeMoverPara` e só então grava via `salvar(copyWith(...))`. Devolve se
/// gravou, para o teste distinguir aceito de rejeitado.
Future<bool> _tentarMover(
  ProviderContainer container,
  String topicoId,
  String? novoPaiId,
) async {
  final topicos = container.read(topicosProvider);
  if (!TopicoUseCase.podeMoverPara(topicos, topicoId, novoPaiId)) return false;
  final alvo = topicos.firstWhere((t) => t.id == topicoId);
  await container
      .read(topicosProvider.notifier)
      .salvar(
        alvo.copyWith(parentId: novoPaiId, limparParent: novoPaiId == null),
      );
  return true;
}

void main() {
  group('TopicoUseCase.podeMoverPara (função pura)', () {
    test('mover para si mesmo é inválido', () {
      final topicos = [_t('a')];
      expect(TopicoUseCase.podeMoverPara(topicos, 'a', 'a'), isFalse);
    });

    test('mover para filho direto é inválido (ciclo imediato)', () {
      final topicos = [_t('pai'), _t('filho', pai: 'pai')];
      expect(TopicoUseCase.podeMoverPara(topicos, 'pai', 'filho'), isFalse);
    });

    test('mover para neto é inválido (ciclo transitivo)', () {
      final topicos = [
        _t('avo'),
        _t('pai', pai: 'avo'),
        _t('neto', pai: 'pai'),
      ];
      expect(TopicoUseCase.podeMoverPara(topicos, 'avo', 'neto'), isFalse);
    });

    test('mover para tópico de outra matéria é inválido', () {
      final topicos = [_t('a', materiaId: 'm1'), _t('b', materiaId: 'm2')];
      expect(TopicoUseCase.podeMoverPara(topicos, 'a', 'b'), isFalse);
    });

    test('tornar tópico raiz é sempre válido', () {
      final topicos = [_t('a', pai: 'b'), _t('b')];
      expect(TopicoUseCase.podeMoverPara(topicos, 'a', null), isTrue);
    });

    test('mover para tópico não-relacionado da mesma matéria é válido', () {
      final topicos = [_t('a'), _t('b'), _t('c', pai: 'a')];
      expect(TopicoUseCase.podeMoverPara(topicos, 'c', 'b'), isTrue);
    });

    test('ciclo pré-existente na massa não trava a validação (sem loop)', () {
      // Import de backup grava parentId sem validar: a massa pode chegar
      // com ciclo pronto (a<->b). A subida da ascendência tem que terminar
      // mesmo assim.
      final topicos = [_t('a', pai: 'b'), _t('b', pai: 'a'), _t('c')];
      expect(TopicoUseCase.podeMoverPara(topicos, 'c', 'a'), isTrue);
    });

    test('id inexistente nunca é destino válido', () {
      final topicos = [_t('a')];
      expect(TopicoUseCase.podeMoverPara(topicos, 'a', 'fantasma'), isFalse);
      expect(TopicoUseCase.podeMoverPara(topicos, 'fantasma', 'a'), isFalse);
    });
  });

  group('mover com gravação real (Hive)', () {
    late Directory dir;
    late ProviderContainer container;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hive_mover_');
      Hive.init(dir.path);
      await HiveBoxes.openAll();
      await HiveBoxes.migrarAmbientes();
      container = ProviderContainer();
    });

    tearDown(() async {
      container.dispose();
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    Future<void> seed(List<Topico> topicos) async {
      await container
          .read(materiasProvider.notifier)
          .salvar(
            Materia(
              id: 'm1',
              nome: 'AFO',
              corSlot: 0,
              criadaEm: DateTime(2026, 1, 1),
            ),
          );
      await container.read(topicosProvider.notifier).mesclar(topicos);
    }

    test('move tópico para novo pai válido e grava parentId', () async {
      await seed([_t('a'), _t('b')]);

      final ok = await _tentarMover(container, 'a', 'b');

      expect(ok, isTrue);
      expect(
        container.read(topicosProvider).firstWhere((t) => t.id == 'a').parentId,
        'b',
      );
    });

    test('move para raiz limpa o parentId (limparParent)', () async {
      await seed([_t('pai'), _t('filho', pai: 'pai')]);

      final ok = await _tentarMover(container, 'filho', null);

      expect(ok, isTrue);
      expect(
        container
            .read(topicosProvider)
            .firstWhere((t) => t.id == 'filho')
            .parentId,
        isNull,
      );
    });

    test('rejeita mover para descendente e não grava nada', () async {
      await seed([_t('pai'), _t('filho', pai: 'pai')]);

      final ok = await _tentarMover(container, 'pai', 'filho');

      expect(ok, isFalse);
      expect(
        container.read(topicosProvider).firstWhere((t) => t.id == 'pai').parentId,
        isNull,
        reason: 'rejeitado pela validação — nada foi gravado',
      );
    });
  });

  group('TopicosScreen — mover via UI', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hive_mover_ui_');
      Hive.init(dir.path);
      await HiveBoxes.openAll();
      await HiveBoxes.migrarAmbientes();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    testWidgets(
      'mover subtópico para raiz: continua na lista, sem duplicata e sem '
      'perder os filhos',
      (tester) async {
        final materia = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );

        // Hierarquia: Orçamento (raiz) -> Receita (sub) -> ISS (neto).
        await tester.runAsync(() async {
          await Hive.box<Map>(
            HiveBoxes.materias,
          ).put(materia.id, materia.toJson());
          await Hive.box<Map>(HiveBoxes.topicos).putAll({
            'pai': _t('pai', nome: 'Orçamento').toJson(),
            'sub': _t('sub', pai: 'pai', nome: 'Receita').toJson(),
            'neto': _t('neto', pai: 'sub', nome: 'ISS').toJson(),
          });
        });

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(home: TopicosScreen(materia: materia)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Orçamento'), findsOneWidget);
        expect(find.text('Receita'), findsOneWidget);
        expect(find.text('ISS'), findsOneWidget);

        // Abre o menu do subtópico "Receita" e escolhe "Mover".
        await tester.tap(
          find.descendant(
            of: find.widgetWithText(CheckboxListTile, 'Receita'),
            matching: find.byType(PopupMenuButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mover'));
        await tester.pumpAndSettle();

        // Seletor aberto: escolhe "Tornar tópico raiz". A opção grava direto
        // no onPressed (não como continuação do Future do showDialog) —
        // mesmo padrão de runAsync de test/banca_form_test.dart: a zona
        // fake-async do widget test não entrega IO real do Hive.
        expect(find.text('Tornar tópico raiz'), findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(find.text('Tornar tópico raiz'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // Continua na lista, sem duplicar...
        expect(find.text('Orçamento'), findsOneWidget);
        expect(find.text('Receita'), findsOneWidget);
        // ...e o filho ("ISS") não ficou pra trás — moveu como subárvore,
        // não virou órfão solto.
        expect(find.text('ISS'), findsOneWidget);

        final salvo = Hive.box<Map>(HiveBoxes.topicos).get('sub');
        expect(salvo?['parentId'], isNull);
      },
    );
  });
}
