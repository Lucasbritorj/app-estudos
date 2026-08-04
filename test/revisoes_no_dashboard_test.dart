import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:app_estudos/features/dashboard/widgets/card_revisoes_hoje.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Revisões concluíveis direto do dashboard.
///
/// O critério de pronto é paridade: concluir pelo card tem de produzir o
/// MESMO estado que concluir pela tela de Revisões. A garantia é estrutural —
/// os dois chamam `concluirRevisaoComFeedback` — e estes testes provam que o
/// card está de fato ligado nesse fluxo, não numa cópia.
void main() {
  final hoje = DateTime(2026, 8, 3);

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_rev_dash_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Revisao rev(String id, DateTime agendada, {bool feita = false}) => Revisao(
    id: id,
    materiaId: 'm1',
    titulo: 'Revisar $id',
    dataAgendada: agendada,
    intervaloDias: 7,
    feita: feita,
    dataConclusao: feita ? agendada : null,
  );

  /// Escreve DIRETO nos boxes, sem passar por notifier.
  ///
  /// Dentro de `testWidgets` isto precisa rodar em `tester.runAsync`: a zona
  /// fake-async nunca entrega a conclusão de um `put` real e o `await` trava
  /// até o timeout de 10 min. Foi exatamente o que derrubou este arquivo na
  /// primeira versão — mesma armadilha documentada em
  /// `test/dashboard_screen_test.dart` e `test/sidebar_test.dart`.
  Future<void> semearHive(List<Revisao> revisoes) async {
    await Hive.box<Map>(HiveBoxes.materias).put(
      'm1',
      Materia(
        id: 'm1',
        nome: 'AFO',
        corSlot: 0,
        criadaEm: DateTime(2026, 1, 1),
      ).toJson(),
    );
    for (final r in revisoes) {
      await Hive.box<Map>(HiveBoxes.revisoes).put(r.id, r.toJson());
    }
  }

  /// Container criado DEPOIS da semeadura: os repositórios leem o box no
  /// `build`, então semear antes é o que faz o provider já nascer com dado.
  ProviderContainer criarContainer() {
    final container = ProviderContainer(
      overrides: [hojeProvider.overrideWithValue(hoje)],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('revisoesDeHojeProvider', () {
    test('pega vencidas e de hoje, ignora futuras e feitas', () async {
      await semearHive([
        rev('atrasada', DateTime(2026, 7, 30)),
        rev('hoje', hoje),
        rev('amanha', DateTime(2026, 8, 4)),
        rev('ja-feita', DateTime(2026, 7, 29), feita: true),
      ]);
      final container = criarContainer();

      final ids = container.read(revisoesDeHojeProvider).map((r) => r.id);
      expect(ids, ['atrasada', 'hoje']);
    });

    test('ordena da mais antiga para a mais recente', () async {
      await semearHive([
        rev('b', DateTime(2026, 8, 1)),
        rev('c', hoje),
        rev('a', DateTime(2026, 7, 20)),
      ]);
      final container = criarContainer();

      expect(container.read(revisoesDeHojeProvider).map((r) => r.id), [
        'a',
        'b',
        'c',
      ]);
    });

    test(
      'lista vem completa: o teto de exibição é do card, não do provider',
      () async {
        await semearHive([
          for (var i = 0; i < 9; i++) rev('r$i', DateTime(2026, 7, 20 + i)),
        ]);
        final container = criarContainer();

        expect(container.read(revisoesDeHojeProvider), hasLength(9));
        expect(CardRevisoesHoje.maxVisiveis, lessThan(9));
      },
    );
  });

  group('card', () {
    /// Semeia dentro de `runAsync` (I/O real) e só então monta.
    Future<ProviderContainer> prepararTela(
      WidgetTester tester,
      List<Revisao> revisoes,
    ) async {
      await tester.runAsync(() => semearHive(revisoes));
      final container = criarContainer();

      await tester.binding.setSurfaceSize(const Size(500, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CardRevisoesHoje())),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('some quando não há revisão vencida', (tester) async {
      await prepararTela(tester, [rev('amanha', DateTime(2026, 8, 4))]);
      expect(find.text('Revisões de hoje'), findsNothing);
    });

    testWidgets('mostra o total real e limita as linhas desenhadas', (
      tester,
    ) async {
      await prepararTela(tester, [
        for (var i = 0; i < 7; i++) rev('r$i', DateTime(2026, 7, 25 + i)),
      ]);

      // Contador diz a verdade (7), a lista desenha o teto (4).
      expect(find.text('7 pendentes'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(4));
      expect(find.text('Ver todas (+3)'), findsOneWidget);
    });

    testWidgets('atraso vira texto, não só cor', (tester) async {
      await prepararTela(tester, [
        rev('atrasada', DateTime(2026, 7, 31)),
        rev('hoje', hoje),
      ]);

      expect(find.textContaining('atrasada 3 dias'), findsOneWidget);
      expect(find.textContaining('vence hoje'), findsOneWidget);
    });

    testWidgets('a11y: linha vira um nó só, com a situação falada', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // Só duas revisões: com mais que `maxVisiveis` as mais RECENTES não são
      // desenhadas (a ordem é da mais antiga para a mais nova), e afirmar
      // rótulo de linha invisível seria teste mentindo.
      await prepararTela(tester, [
        rev('atrasada', DateTime(2026, 7, 31)),
        rev('hoje', hoje),
      ]);

      // Antes eram dois `Text` irmãos: o leitor anunciava o título, depois
      // "AFO · atrasada 3 dias" com o "·" lido como pontuação solta.
      expect(
        find.bySemanticsLabel('Revisar atrasada, AFO, atrasada 3 dias'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Revisar hoje, AFO, vence hoje'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('a11y: cada botão diz QUAL revisão; "Ver todas" tem nome', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      // 7 semeadas, 4 desenhadas: r0..r3 são as mais antigas.
      await prepararTela(tester, [
        for (var i = 0; i < 7; i++) rev('r$i', DateTime(2026, 7, 25 + i)),
      ]);

      // Com `tooltip` apenas, o nome primário do nó ficava vazio e uma lista
      // de 4 botões iguais anunciava "botão" quatro vezes.
      for (final id in ['r0', 'r1', 'r2', 'r3']) {
        expect(
          find.bySemanticsLabel('Concluir revisão Revisar $id'),
          findsOneWidget,
          reason: 'botão precisa dizer QUAL revisão',
        );
      }

      // Nome distinto do CardForecastRevisao, que leva para a MESMA aba.
      expect(
        find.bySemanticsLabel('Ver todas as revisões, mais 3 pendentes'),
        findsOneWidget,
      );

      // Garantia negativa: nenhum botão do card fica sem o que anunciar.
      for (final elemento in find
          .descendant(
            of: find.byType(CardRevisoesHoje),
            matching: find.byType(IconButton),
          )
          .evaluate()) {
        expect(
          tester.getSemantics(find.byWidget(elemento.widget)).label,
          isNotEmpty,
        );
      }

      handle.dispose();
    });

    testWidgets('concluir pelo card marca feita e emenda a próxima', (
      tester,
    ) async {
      final container = await prepararTela(tester, [
        rev('r1', DateTime(2026, 7, 31)),
      ]);

      // A cadeia INTEIRA (abrir diálogo -> confirmar -> gravar) entra no mesmo
      // bloco `runAsync`, com `pump()` simples entre os passos — misturar
      // `pumpAndSettle()` (zona fake) no meio de uma cadeia que termina em I/O
      // real trava o teste.
      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.check_circle_outline));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();

        // "Só concluir" = sem questões; o intervalo seguinte cai na janela
        // histórica em vez da taxa da revisão.
        await tester.tap(find.text('Só concluir'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      final revisoes = container.read(revisoesProvider);
      final original = revisoes.firstWhere((r) => r.id == 'r1');
      expect(original.feita, isTrue, reason: 'a original tem de ficar feita');
      expect(original.dataConclusao, isNotNull);

      // A cadeia emendou: existe uma nova pendente que não é a original.
      final pendentes = revisoes.where((r) => !r.feita).toList();
      expect(pendentes, hasLength(1));
      expect(pendentes.single.id, isNot('r1'));

      // E o card não mostra mais nada a fazer hoje: a nova nasce no futuro.
      expect(container.read(revisoesDeHojeProvider), isEmpty);
    });

    testWidgets('cancelar no diálogo não conclui nada', (tester) async {
      final container = await prepararTela(tester, [
        rev('r1', DateTime(2026, 7, 31)),
      ]);

      await tester.runAsync(() async {
        await tester.tap(find.byIcon(Icons.check_circle_outline));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
        await tester.tap(find.text('Cancelar'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(container.read(revisoesProvider).single.feita, isFalse);
      expect(container.read(revisoesDeHojeProvider), hasLength(1));
    });
  });
}
