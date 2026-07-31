import 'dart:io';
import 'dart:typed_data';

import 'package:app_estudos/application/apagar_dados_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:app_estudos/domain/import_service.dart';
import 'package:app_estudos/features/caderno/caderno_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// F1 — foto do enunciado no caderno de erros. Cobre:
/// * CRUD do box de anexos (`AnexosQuestaoRepositorio`) sobre Hive real;
/// * cascata do wipe total (`ApagarDadosUseCase.apagarTudo`);
/// * roundtrip de `QuestaoErrada.temAnexo` (bool, não `anexoId` — ver o
///   comentário no model);
/// * round-trip do backup (bytes -> base64 -> bytes), tolerância a backup
///   antigo sem a chave `anexos` e rejeição de base64/estrutura corrompidos;
/// * cascata de exclusão (apagar a questão pela tela apaga o anexo dela)
///   pelo mesmo caminho de produção (`caderno_screen.dart`).
///
/// Mesmo setUp/tearDown de `backup_rollback_test.dart`/`apagar_dados_test.dart`:
/// Hive real num diretório temporário, um `ProviderContainer` por teste.
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_anexo_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  // Bytes determinísticos e distintos por "semente", pra distinguir anexos
  // diferentes nos testes de armazenamento/backup — não passam de bytes
  // opacos ali (nunca viram widget), então não precisam parecer imagem de
  // verdade.
  Uint8List bytes([int semente = 1]) =>
      Uint8List.fromList(List.generate(16, (i) => (i * semente + 1) % 256));

  // PNG 1x1 real e mínimo (mesmo fixture `kTransparentImage` usado pelos
  // testes de widget do próprio Flutter, ex. circle_avatar_test.dart): o
  // teste de cascata via UI abaixo renderiza `Image.memory` de verdade (a
  // tela "Fila de hoje" continua montada por trás da aba "Todas" dentro do
  // `TabBarView`), e bytes arbitrários fariam o decoder do engine lançar
  // "Invalid image data" no meio do pump.
  Uint8List fotoValida() => Uint8List.fromList(const <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
    0x89, 0x00, 0x00, 0x00, 0x06, 0x62, 0x4B, 0x47, //
    0x44, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0xA0, //
    0xBD, 0xA7, 0x93, 0x00, 0x00, 0x00, 0x09, 0x70, //
    0x48, 0x59, 0x73, 0x00, 0x00, 0x0B, 0x13, 0x00, //
    0x00, 0x0B, 0x13, 0x01, 0x00, 0x9A, 0x9C, 0x18, //
    0x00, 0x00, 0x00, 0x07, 0x74, 0x49, 0x4D, 0x45, //
    0x07, 0xE6, 0x03, 0x10, 0x17, 0x07, 0x1D, 0x2E, //
    0x5E, 0x30, 0x9B, 0x00, 0x00, 0x00, 0x0B, 0x49, //
    0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0x60, 0x00, //
    0x02, 0x00, 0x00, 0x05, 0x00, 0x01, 0xE2, 0x26, //
    0x05, 0x9B, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, //
    0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  group('AnexosQuestaoRepositorio — grava/lê/apaga no box', () {
    test('grava e lê os bytes pela chave (id da questão)', () async {
      final repo = container.read(anexosQuestaoRepositorioProvider);
      await repo.salvar('q1', bytes());
      expect(repo.ler('q1'), bytes());
    });

    test('ler devolve null quando a questão não tem anexo', () {
      final repo = container.read(anexosQuestaoRepositorioProvider);
      expect(repo.ler('nunca-existiu'), isNull);
    });

    test('remover apaga o anexo', () async {
      final repo = container.read(anexosQuestaoRepositorioProvider);
      await repo.salvar('q1', bytes());
      await repo.remover('q1');
      expect(repo.ler('q1'), isNull);
    });

    test('remover é idempotente: apagar quem não tem anexo não lança', () async {
      final repo = container.read(anexosQuestaoRepositorioProvider);
      await repo.remover('nunca-existiu');
      expect(repo.ler('nunca-existiu'), isNull);
    });

    test('substituirTudo troca o conteúdo do box por inteiro (restauração)', () async {
      final repo = container.read(anexosQuestaoRepositorioProvider);
      await repo.salvar('antigo', bytes(1));
      await repo.substituirTudo({'novo': bytes(2)});
      expect(repo.ler('antigo'), isNull);
      expect(repo.ler('novo'), bytes(2));
    });

    test('mesclar grava sem apagar o resto (import aditivo)', () async {
      final repo = container.read(anexosQuestaoRepositorioProvider);
      await repo.salvar('q1', bytes(1));
      await repo.mesclar({'q2': bytes(2)});
      expect(repo.ler('q1'), bytes(1));
      expect(repo.ler('q2'), bytes(2));
    });
  });

  group('ApagarDadosUseCase.apagarTudo — cascata do wipe total', () {
    test('limpa o box de anexos junto com as questões erradas', () async {
      await container
          .read(questoesErradasProvider.notifier)
          .salvar(
            QuestaoErrada(
              id: 'q1',
              materiaId: 'm1',
              enunciado: 'Enunciado com foto',
              criadaEm: DateTime(2026, 7, 1),
              temAnexo: true,
            ),
          );
      await container
          .read(anexosQuestaoRepositorioProvider)
          .salvar('q1', bytes());
      expect(Hive.box<Uint8List>(HiveBoxes.anexos).isEmpty, isFalse);

      await container.read(apagarDadosUseCaseProvider).apagarTudo();

      expect(container.read(questoesErradasProvider), isEmpty);
      expect(container.read(anexosQuestaoRepositorioProvider).ler('q1'), isNull);
      expect(Hive.box<Uint8List>(HiveBoxes.anexos).isEmpty, isTrue);
    });

    test('base de anexos já vazia não lança exceção', () async {
      await container.read(apagarDadosUseCaseProvider).apagarTudo();
      expect(Hive.box<Uint8List>(HiveBoxes.anexos).isEmpty, isTrue);
    });
  });

  group('QuestaoErrada.temAnexo — model', () {
    QuestaoErrada questao({bool temAnexo = false}) => QuestaoErrada(
      id: 'q1',
      materiaId: 'm1',
      enunciado: 'x',
      criadaEm: DateTime(2026, 7, 1),
      temAnexo: temAnexo,
    );

    test('default é false', () {
      expect(questao().temAnexo, isFalse);
    });

    test('roundtrip JSON preserva true', () {
      final restaurada = QuestaoErrada.fromJson(questao(temAnexo: true).toJson());
      expect(restaurada.temAnexo, isTrue);
    });

    test('roundtrip JSON preserva false', () {
      final restaurada = QuestaoErrada.fromJson(questao().toJson());
      expect(restaurada.temAnexo, isFalse);
    });

    test('fromJson tolera backup sem a chave temAnexo (default false)', () {
      final restaurada = QuestaoErrada.fromJson({
        'id': 'q1',
        'materiaId': 'm1',
        'enunciado': 'x',
        'criadaEm': DateTime(2026, 7, 1).toIso8601String(),
      });
      expect(restaurada.temAnexo, isFalse);
    });

    test('copyWith atualiza temAnexo sem mexer no resto', () {
      final atualizada = questao().copyWith(temAnexo: true);
      expect(atualizada.temAnexo, isTrue);
      expect(atualizada.id, 'q1');
    });
  });

  group('Backup (ExportService/ImportService) — fotos em base64', () {
    String jsonSemAnexos() => ExportService.jsonCompleto(
      materias: const [],
      topicos: const [],
      aulas: const [],
      registros: const [],
      revisoes: const [],
      leituras: const [],
      planejamento: const {},
    );

    test('jsonCompleto sem anexos vira backup com mapa de anexos vazio', () {
      final backup = ImportService.parseBackup(jsonSemAnexos());
      expect(backup.anexos, isEmpty);
    });

    test('round-trip preserva os bytes byte a byte via base64', () {
      final original = bytes(7);
      final json = ExportService.jsonCompleto(
        materias: const [],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
        leituras: const [],
        planejamento: const {},
        anexos: {'q1': original},
      );
      final backup = ImportService.parseBackup(json);
      expect(backup.anexos['q1'], original);
    });

    test('round-trip preserva vários anexos distintos', () {
      final json = ExportService.jsonCompleto(
        materias: const [],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
        leituras: const [],
        planejamento: const {},
        anexos: {'q1': bytes(1), 'q2': bytes(2)},
      );
      final backup = ImportService.parseBackup(json);
      expect(backup.anexos['q1'], bytes(1));
      expect(backup.anexos['q2'], bytes(2));
    });

    test('backup antigo sem a chave "anexos" não quebra (mapa vazio)', () {
      final backup = ImportService.parseBackup('{"versao":1,"materias":[]}');
      expect(backup.anexos, isEmpty);
    });

    test('base64 corrompido vira FormatException, não TypeError', () {
      const json =
          '{"versao":1,"materias":[],"anexos":{"q1":"###não-é-base64###"}}';
      expect(
        () => ImportService.parseBackup(json),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'valor de anexo que não é string vira FormatException, não TypeError',
      () {
        const json = '{"versao":1,"materias":[],"anexos":{"q1":123}}';
        expect(
          () => ImportService.parseBackup(json),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('"anexos" que não é um objeto vira FormatException', () {
      const json = '{"versao":1,"materias":[],"anexos":[1,2,3]}';
      expect(
        () => ImportService.parseBackup(json),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'jsonAmbiente só leva os anexos das questões que entraram no backup parcial',
      () {
        final ambiente = Ambiente(
          id: 'amb1',
          nome: 'Concurso X',
          criadoEm: DateTime(2026, 1, 1),
        );
        final materiaDoAmbiente = Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          ambienteId: 'amb1',
          criadaEm: DateTime(2026, 1, 1),
        );
        final materiaDeFora = Materia(
          id: 'm2',
          nome: 'Direito',
          corSlot: 1,
          ambienteId: 'outro-ambiente',
          criadaEm: DateTime(2026, 1, 1),
        );
        final questaoDoAmbiente = QuestaoErrada(
          id: 'q-dentro',
          materiaId: 'm1',
          enunciado: 'x',
          criadaEm: DateTime(2026, 1, 1),
          temAnexo: true,
        );
        final questaoDeFora = QuestaoErrada(
          id: 'q-fora',
          materiaId: 'm2',
          enunciado: 'y',
          criadaEm: DateTime(2026, 1, 1),
          temAnexo: true,
        );

        final json = ExportService.jsonAmbiente(
          ambiente: ambiente,
          materias: [materiaDoAmbiente, materiaDeFora],
          topicos: const [],
          aulas: const [],
          registros: const [],
          revisoes: const [],
          questoesErradas: [questaoDoAmbiente, questaoDeFora],
          anexos: {'q-dentro': bytes(1), 'q-fora': bytes(2)},
        );

        final backup = ImportService.parseBackup(json);
        expect(backup.anexos.keys, ['q-dentro']);
        expect(backup.anexos['q-dentro'], bytes(1));
      },
    );
  });

  group('Cascata de exclusão via UI (CadernoScreen) — B/F1', () {
    Future<void> montarTela(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: CadernoScreen())),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('excluir a questão pela tela apaga o anexo dela', (
      tester,
    ) async {
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
        final questao = QuestaoErrada(
          id: 'q1',
          materiaId: 'm1',
          enunciado: 'Questão com foto anexada',
          criadaEm: agora,
          proximaTentativa: agora,
          temAnexo: true,
        );
        await Hive.box<Map>(
          HiveBoxes.questoesErradas,
        ).put(questao.id, questao.toJson());
        await Hive.box<Uint8List>(
          HiveBoxes.anexos,
        ).put(questao.id, fotoValida());
      });

      await montarTela(tester);
      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();
      expect(find.text('Questão com foto anexada'), findsOneWidget);
      expect(Hive.box<Uint8List>(HiveBoxes.anexos).get('q1'), isNotNull);

      // Mesma cadeia (runAsync único, pump() simples entre os passos) de
      // caderno_screen_test.dart: abrir o menu, confirmar a exclusão e a
      // escrita real no Hive formam uma cadeia assíncrona só.
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

      expect(find.text('Caderno de erros vazio'), findsOneWidget);
      expect(Hive.box<Uint8List>(HiveBoxes.anexos).get('q1'), isNull);
      expect(tester.takeException(), isNull);
    });
  });
}
