import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/features/caderno/caderno_screen.dart';
import 'package:app_estudos/features/caderno/questoes_orfas_screen.dart';
import 'package:app_estudos/features/dashboard/widgets/card_caderno_erros.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Widget tests do Caderno de Erros. Mesmo padrão de setUp/tearDown de
/// dashboard_screen_test.dart: Hive num diretório temporário por teste.
///
/// Escritas reais no Hive disparadas por interação (tap) precisam de
/// `tester.runAsync` — a zona fake-async do `testWidgets` nunca entrega a
/// conclusão de um `await` de I/O real (mesmo padrão de
/// test/sidebar_test.dart, que documenta a mesma armadilha). Quando a cadeia
/// de interação tem VÁRIOS taps até a escrita (abrir menu -> abrir diálogo de
/// confirmação -> confirmar), TODA a cadeia entra no mesmo bloco runAsync,
/// com `pump()` simples entre os passos — misturar `pumpAndSettle()` (zona
/// fake) no meio de uma cadeia que termina em I/O real trava o teste.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_caderno_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> montarTela(WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: CadernoScreen())),
    );
    await tester.pumpAndSettle();
  }

  Future<void> seedMateriaEQuestao(WidgetTester tester) async {
    await tester.runAsync(() async {
      final materia = Materia(
        id: 'm1',
        nome: 'AFO',
        corSlot: 0,
        criadaEm: DateTime(2026, 1, 1),
      );
      await Hive.box<Map>(HiveBoxes.materias).put(materia.id, materia.toJson());

      // proximaTentativa/criadaEm usam DateTime.now() (não hojeProvider) de
      // propósito: a QuestaoErrada trunca pro dia via factory, então cai no
      // MESMO "hoje" que hojeProvider computa a partir do relógio real — a
      // tela nunca faz override de hojeProvider (mesma escolha de
      // dashboard_screen_test.dart), então a fila só bate se os dois lerem
      // a mesma data real.
      final agora = DateTime.now();
      final questao = QuestaoErrada(
        id: 'q1',
        materiaId: 'm1',
        enunciado: 'Questão de teste sobre AFO',
        respostaMarcada: 'Letra B',
        respostaCorreta: 'Letra C',
        criadaEm: agora,
        proximaTentativa: agora,
      );
      await Hive.box<Map>(
        HiveBoxes.questoesErradas,
      ).put(questao.id, questao.toJson());
    });
  }

  group('CadernoScreen', () {
    testWidgets('caderno vazio mostra estado vazio e esconde as abas', (
      tester,
    ) async {
      await montarTela(tester);

      expect(find.text('Caderno de erros vazio'), findsOneWidget);
      expect(find.text('Adicionar questão'), findsOneWidget);
      expect(find.text('Fila de hoje'), findsNothing);
      expect(find.text('Estatísticas'), findsNothing);
    });

    testWidgets(
      'questão vencida aparece na fila; refazer acertando tira ela de lá',
      (tester) async {
        await seedMateriaEQuestao(tester);
        await montarTela(tester);

        // Abre direto na aba "Fila de hoje" (índice 0 do TabController).
        expect(find.text('Questão de teste sobre AFO'), findsOneWidget);

        // Resposta correta some até o usuário pedir pra ver.
        expect(find.textContaining('Letra C'), findsNothing);
        await tester.tap(find.text('Ver resposta'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Letra C'), findsOneWidget);
        expect(find.textContaining('Letra B'), findsOneWidget);

        // "Acertei" grava a tentativa (I/O real no Hive) e reagenda a
        // questão pra frente — ela sai da fila de hoje.
        await tester.runAsync(() async {
          await tester.tap(find.text('Acertei'));
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();

        expect(find.text('Questão de teste sobre AFO'), findsNothing);
        expect(find.text('Fila zerada por hoje'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('aba Todas mostra a questão e permite excluir com confirmação', (
      tester,
    ) async {
      await seedMateriaEQuestao(tester);
      await montarTela(tester);

      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();
      expect(find.text('Questão de teste sobre AFO'), findsOneWidget);

      // PopupMenu > Excluir > confirma — tudo num único runAsync, só com
      // pump()/pump(duração) entre os passos (nunca pumpAndSettle no meio):
      // abrir o menu, abrir o diálogo de confirmação e a escrita real no
      // Hive formam UMA cadeia assíncrona só, e cruzar de volta pra zona
      // fake-async no meio dela é o que travava o teste.
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Mais opções'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Excluir').last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Excluir').last);
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      // Caderno ficou vazio de novo (única questão excluída).
      expect(find.text('Caderno de erros vazio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adicionar questão manual pelo diálogo entra no caderno', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final materia = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(HiveBoxes.materias).put(materia.id, materia.toJson());
      });
      await montarTela(tester);

      // Caderno começa vazio (só a matéria foi semeada) — usa o CTA do
      // estado vazio, que abre o mesmo diálogo do FAB.
      await tester.tap(find.text('Adicionar questão'));
      await tester.pumpAndSettle();
      expect(find.text('Nova questão errada'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Enunciado *'),
        'Nova questão adicionada manualmente',
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Salvar'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.text('Nova questão adicionada manualmente'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Questões órfãs (B5)', () {
    Future<void> seedOrfaComDuasMaterias(WidgetTester tester) async {
      await tester.runAsync(() async {
        final m1 = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );
        final m2 = Materia(
          id: 'm2',
          nome: 'Direito Administrativo',
          corSlot: 1,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(HiveBoxes.materias).put(m1.id, m1.toJson());
        await Hive.box<Map>(HiveBoxes.materias).put(m2.id, m2.toJson());

        // materiaId aponta pra uma matéria que nunca existiu no box — mesmo
        // estado que sobra depois de uma exclusão em cascata (preservação
        // deliberada: ver MateriaUseCase/TopicoUseCase).
        final agora = DateTime.now();
        final orfa = QuestaoErrada(
          id: 'qorfa',
          materiaId: 'materia-excluida',
          enunciado: 'Questão cuja matéria foi excluída',
          criadaEm: agora,
          proximaTentativa: agora,
        );
        await Hive.box<Map>(
          HiveBoxes.questoesErradas,
        ).put(orfa.id, orfa.toJson());
      });
    }

    testWidgets('aba Todas mostra o aviso discreto e navega pra tela de órfãs', (
      tester,
    ) async {
      await seedOrfaComDuasMaterias(tester);
      await montarTela(tester);

      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();

      expect(find.textContaining('órfã'), findsOneWidget);

      await tester.tap(find.textContaining('órfã'));
      await tester.pumpAndSettle();

      expect(find.byType(QuestoesOrfasScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reatribuir grava a nova matéria e a questão some da lista de órfãs', (
      tester,
    ) async {
      await seedOrfaComDuasMaterias(tester);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: QuestoesOrfasScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Questão cuja matéria foi excluída'), findsOneWidget);
      expect(find.text('Matéria excluída'), findsOneWidget);

      await tester.tap(find.text('Reatribuir'));
      await tester.pumpAndSettle();
      expect(find.text('Reatribuir questão'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Direito Administrativo').last);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Salvar'));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      // Diálogo fechou, a questão já não aparece mais como órfã — a tela
      // volta pro estado vazio porque era a única.
      expect(find.text('Reatribuir questão'), findsNothing);
      expect(find.text('Questão cuja matéria foi excluída'), findsNothing);
      expect(find.text('Nenhuma questão órfã'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final salvo = QuestaoErrada.fromJson(
        Map<String, dynamic>.from(
          Hive.box<Map>(HiveBoxes.questoesErradas).get('qorfa')!,
        ),
      );
      expect(salvo.materiaId, 'm2');
    });
  });

  group('CardCadernoErros', () {
    Future<void> montarCard(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CardCadernoErros())),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('esconde (SizedBox.shrink) quando o caderno está vazio', (
      tester,
    ) async {
      await montarCard(tester);
      expect(find.text('Caderno de Erros'), findsNothing);
    });

    testWidgets('mostra contagem de hoje e navega pro caderno ao tocar', (
      tester,
    ) async {
      await seedMateriaEQuestao(tester);
      await montarCard(tester);

      expect(find.text('Caderno de Erros'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('vence hoje'), findsOneWidget);

      await tester.tap(find.byType(CardCadernoErros));
      await tester.pumpAndSettle();

      expect(find.byType(CadernoScreen), findsOneWidget);
    });
  });

  group('Indicador de foto na aba Todas (B17)', () {
    Future<void> seedQuestoesComESemFoto(WidgetTester tester) async {
      await tester.runAsync(() async {
        final materia = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(
          HiveBoxes.materias,
        ).put(materia.id, materia.toJson());

        final agora = DateTime.now();
        final comFoto = QuestaoErrada(
          id: 'q1',
          materiaId: 'm1',
          enunciado: 'Questão com foto anexada',
          criadaEm: agora,
          proximaTentativa: agora,
          temAnexo: true,
        );
        final semFoto = QuestaoErrada(
          id: 'q2',
          materiaId: 'm1',
          enunciado: 'Questão sem foto',
          criadaEm: agora,
          proximaTentativa: agora,
        );
        await Hive.box<Map>(
          HiveBoxes.questoesErradas,
        ).put(comFoto.id, comFoto.toJson());
        await Hive.box<Map>(
          HiveBoxes.questoesErradas,
        ).put(semFoto.id, semFoto.toJson());
      });
    }

    testWidgets(
      'questão com temAnexo mostra o ícone na aba Todas; sem anexo não mostra',
      (tester) async {
        final handle = tester.ensureSemantics();

        await seedQuestoesComESemFoto(tester);
        await montarTela(tester);

        await tester.tap(find.text('Todas'));
        await tester.pumpAndSettle();

        expect(find.text('Questão com foto anexada'), findsOneWidget);
        expect(find.text('Questão sem foto'), findsOneWidget);

        // Só a FLAG temAnexo decide o ícone (nunca os bytes do anexo): com
        // 2 questões na lista e só 1 com temAnexo, o ícone tem que aparecer
        // exatamente uma vez.
        expect(find.byIcon(Icons.image_outlined), findsOneWidget);
        expect(find.bySemanticsLabel('Foto anexada'), findsOneWidget);

        handle.dispose();
      },
    );
  });
}
