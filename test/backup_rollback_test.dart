import 'dart:convert';
import 'dart:io';

import 'package:app_estudos/application/backup_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/resumo.dart';
import 'package:app_estudos/data/repositories/configuracoes_repositorio.dart';
import 'package:app_estudos/data/repositories/planejamento_repositorio.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:app_estudos/domain/import_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_rollback_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> semearEstadoOriginal() async {
    await container
        .read(materiasProvider.notifier)
        .salvar(
          Materia(
            id: 'm-original',
            nome: 'Português',
            corSlot: 0,
            peso: 3,
            criadaEm: DateTime(2026, 1, 1),
          ),
        );
    await container
        .read(registrosProvider.notifier)
        .salvar(
          RegistroHora(
            id: 'r-original',
            data: DateTime(2026, 7, 1),
            materiaId: 'm-original',
            minutos: 90,
          ),
        );
    await container
        .read(questoesErradasProvider.notifier)
        .salvar(
          QuestaoErrada(
            id: 'q-original',
            materiaId: 'm-original',
            enunciado: 'Questão do estado original',
            criadaEm: DateTime(2026, 7, 1),
          ),
        );
    await container.read(planejamentoProvider.notifier).substituir({1: 120});
    await container
        .read(configuracoesProvider.notifier)
        .salvar(
          const Configuracoes(
            metaSemanalMinutos: 1500,
            intervalosRevisao: [3, 9],
            minutosPadraoRevisao: 25,
          ),
        );
  }

  String backupDeOutraPessoa() => ExportService.jsonCompleto(
    materias: [
      Materia(
        id: 'm-importada',
        nome: 'Direito Penal',
        corSlot: 1,
        peso: 5,
        criadaEm: DateTime(2026, 2, 2),
      ),
    ],
    topicos: const [],
    aulas: const [],
    registros: const [],
    revisoes: const [],
    leituras: const [],
    planejamento: const {2: 60},
    configuracoes: const Configuracoes(metaSemanalMinutos: 600),
  );

  group('B2 — Configuracoes no backup', () {
    test('jsonCompleto grava as preferências e parseBackup as devolve', () {
      final json = ExportService.jsonCompleto(
        materias: const [],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
        leituras: const [],
        planejamento: const {},
        configuracoes: const Configuracoes(
          intervalosRevisao: [5, 11],
          horaNotificacao: 21,
          metaSemanalMinutos: 2400,
          horaLembreteEstudo: 7,
          minutosPadraoRevisao: 15,
        ),
      );
      final lido = ImportService.parseBackup(json).configuracoes;
      expect(lido, isNotNull);
      expect(lido!.intervalosRevisao, [5, 11]);
      expect(lido.horaNotificacao, 21);
      expect(lido.metaSemanalMinutos, 2400);
      expect(lido.horaLembreteEstudo, 7);
      expect(lido.minutosPadraoRevisao, 15);
    });

    test('backup antigo sem a chave devolve null (não zera nada)', () {
      final backup = ImportService.parseBackup('{"versao":1,"materias":[]}');
      expect(backup.configuracoes, isNull);
    });

    test('configurações corrompidas viram FormatException, não TypeError', () {
      expect(
        () => ImportService.parseBackup(
          '{"versao":1,"materias":[],"configuracoes":{"intervalosRevisao":"7"}}',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'ambiente ativo do backup nunca é restaurado (pode não existir)',
      () async {
        await semearEstadoOriginal();
        final json = ExportService.jsonCompleto(
          materias: const [],
          topicos: const [],
          aulas: const [],
          registros: const [],
          revisoes: const [],
          leituras: const [],
          planejamento: const {},
          configuracoes: const Configuracoes(ambienteAtivoId: 'amb-que-sumiu'),
        );
        await container
            .read(backupUseCaseProvider)
            .restaurarSubstituindo(ImportService.parseBackup(json));
        expect(container.read(configuracoesProvider).ambienteAtivoId, isNull);
      },
    );
  });

  group('B4 — rollback da importação destrutiva', () {
    test(
      'snapshotAtual serializa tudo, inclusive caderno e preferências',
      () async {
        await semearEstadoOriginal();
        final snapshot = ImportService.parseBackup(
          container.read(backupUseCaseProvider).snapshotAtual(),
        );
        expect(snapshot.materias.single.id, 'm-original');
        expect(snapshot.registros.single.minutos, 90);
        expect(snapshot.questoesErradas.single.id, 'q-original');
        expect(snapshot.planejamento, {1: 120});
        expect(snapshot.configuracoes!.metaSemanalMinutos, 1500);
        expect(snapshot.configuracoes!.minutosPadraoRevisao, 25);
      },
    );

    test('restaurar troca os dados e habilita o desfazer', () async {
      await semearEstadoOriginal();
      final useCase = container.read(backupUseCaseProvider);
      expect(useCase.podeDesfazer, isFalse);

      await useCase.restaurarSubstituindo(
        ImportService.parseBackup(backupDeOutraPessoa()),
      );

      expect(container.read(materiasProvider).single.id, 'm-importada');
      expect(container.read(registrosProvider), isEmpty);
      expect(container.read(questoesErradasProvider), isEmpty);
      expect(container.read(planejamentoProvider), {2: 60});
      expect(container.read(configuracoesProvider).metaSemanalMinutos, 600);
      expect(useCase.podeDesfazer, isTrue);
    });

    test('desfazer devolve o estado anterior por inteiro', () async {
      await semearEstadoOriginal();
      final useCase = container.read(backupUseCaseProvider);
      await useCase.restaurarSubstituindo(
        ImportService.parseBackup(backupDeOutraPessoa()),
      );

      expect(await useCase.desfazerUltimaRestauracao(), isTrue);

      expect(container.read(materiasProvider).single.id, 'm-original');
      expect(container.read(registrosProvider).single.minutos, 90);
      expect(container.read(questoesErradasProvider).single.id, 'q-original');
      expect(container.read(planejamentoProvider), {1: 120});
      expect(container.read(configuracoesProvider).metaSemanalMinutos, 1500);
      expect(container.read(configuracoesProvider).minutosPadraoRevisao, 25);
      // Snapshot é consumido: não dá para desfazer duas vezes.
      expect(useCase.podeDesfazer, isFalse);
      expect(await useCase.desfazerUltimaRestauracao(), isFalse);
    });

    test(
      'backup parcial (de ambiente) é recusado no use case, não só na UI',
      () async {
        await semearEstadoOriginal();
        final parcial = ImportService.parseBackup(
          ExportService.jsonAmbiente(
            ambiente: Ambiente(
              id: 'amb-x',
              nome: 'Concurso X',
              criadoEm: DateTime(2026, 1, 1),
            ),
            materias: const [],
            topicos: const [],
            aulas: const [],
            registros: const [],
            revisoes: const [],
          ),
        );
        expect(
          () => container
              .read(backupUseCaseProvider)
              .restaurarSubstituindo(parcial),
          throwsA(isA<StateError>()),
        );
        // Nada foi tocado.
        expect(container.read(materiasProvider).single.id, 'm-original');
      },
    );

    test('restauração vazia não apaga as preferências locais', () async {
      await semearEstadoOriginal();
      await expectLater(
        container
            .read(backupUseCaseProvider)
            .restaurarSubstituindo(
              ImportService.parseBackup('{"versao":1,"materias":[]}'),
            ),
        throwsA(isA<StateError>()),
      );
      // Backup sem 'configuracoes' preserva as preferências de quem restaura.
      expect(container.read(configuracoesProvider).metaSemanalMinutos, 1500);
      expect(container.read(materiasProvider).single.id, 'm-original');
    });
  });

  group('D-01 — restaurar backup antigo não apaga o que ele não menciona', () {
    /// Backup COMPLETO e válido, porém sem a chave [semAChave] — é o formato
    /// que o app gerava antes de a coleção existir.
    String backupSem(String semAChave) {
      final json = ExportService.jsonCompleto(
        materias: const [],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
        leituras: const [],
        planejamento: const {},
      );
      final mapa = jsonDecode(json) as Map<String, dynamic>;
      mapa.remove(semAChave);
      return jsonEncode(mapa);
    }

    Future<void> semearResumo() => container
        .read(resumosProvider.notifier)
        .salvar(
          Resumo(
            sigla: 'DC',
            nome: 'Direito Constitucional',
            texto: 'anotação cara de reproduzir',
          ),
        );

    test(
      'backup pré-D-01 (sem "resumos") PRESERVA os resumos existentes',
      () async {
        // O cenário real: o diálogo de wipe manda exportar backup antes de
        // apagar. Quem tem o arquivo mais antigo é quem mais precisa restaurar —
        // e era exatamente quem perdia as páginas de resumo, em silêncio.
        await semearResumo();
        expect(container.read(resumosProvider), hasLength(1));

        await container
            .read(backupUseCaseProvider)
            .restaurarSubstituindo(
              ImportService.parseBackup(backupSem('resumos')),
            );

        final resumos = container.read(resumosProvider);
        expect(resumos, hasLength(1), reason: 'o arquivo não falou de resumos');
        expect(resumos.single.texto, contains('cara de reproduzir'));
      },
    );

    test('backup com "resumos": [] ZERA — o arquivo falou vazio', () async {
      await semearResumo();

      final json = ExportService.jsonCompleto(
        materias: const [],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
        leituras: const [],
        planejamento: const {},
        resumos: const [], // menção explícita
      );
      await container
          .read(backupUseCaseProvider)
          .restaurarSubstituindo(ImportService.parseBackup(json));

      expect(container.read(resumosProvider), isEmpty);
    });

    test('mesma regra para questoesErradas e anexos', () async {
      await container
          .read(questoesErradasProvider.notifier)
          .salvar(
            QuestaoErrada(
              id: 'q1',
              materiaId: 'm-original',
              enunciado: 'questão que custou caro',
              criadaEm: DateTime(2026, 7, 1),
              proximaTentativa: DateTime(2026, 7, 8),
            ),
          );

      await container
          .read(backupUseCaseProvider)
          .restaurarSubstituindo(
            ImportService.parseBackup(backupSem('questoesErradas')),
          );

      expect(container.read(questoesErradasProvider), hasLength(1));
    });

    test('snapshot de rollback continua substituindo tudo', () async {
      // `snapshotAtual()` escreve TODAS as chaves, então o "Desfazer" não é
      // afetado pela guarda — se fosse, o rollback deixaria lixo do estado que
      // ele deveria desfazer.
      await semearResumo();
      final snapshot = container.read(backupUseCaseProvider).snapshotAtual();
      final backup = ImportService.parseBackup(snapshot);
      for (final chave in [
        'aulas',
        'simulados',
        'resumos',
        'questoesErradas',
        'anexos',
      ]) {
        expect(backup.mencionou(chave), isTrue, reason: chave);
      }
    });
  });
}
