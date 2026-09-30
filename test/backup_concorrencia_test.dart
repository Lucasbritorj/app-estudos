import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_estudos/application/apagar_dados_use_case.dart';
import 'package:app_estudos/application/backup_use_case.dart';
import 'package:app_estudos/application/revisao_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/repositories/conclusoes_revisao_repositorio.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:app_estudos/domain/import_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer c;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup_concorrencia_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrar();
    c = ProviderContainer();
    await c
        .read(materiasProvider.notifier)
        .salvar(
          Materia(
            id: 'm',
            nome: 'Materia',
            corSlot: 0,
            peso: 1,
            criadaEm: DateTime(2026),
          ),
        );
  });
  tearDown(() async {
    c.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });
  Revisao revisao(String id) => Revisao(
    id: id,
    materiaId: 'm',
    titulo: id,
    dataAgendada: DateTime.now(),
    intervaloDias: 7,
  );

  test(
    'exportar, apagar e mesclar preserva recibos de revisoes excluidas',
    () async {
      for (var i = 0; i < 3; i++) {
        await c
            .read(revisaoUseCaseProvider)
            .concluir(revisao('r$i'), questoes: 10, acertos: 8);
        await c.read(revisoesProvider.notifier).remover('r$i');
      }
      final backup = ImportService.parseBackup(
        c.read(backupUseCaseProvider).snapshotAtual(),
      );
      expect(backup.conclusoesRevisao, hasLength(3));
      final sessaoIds = c.read(registrosProvider).map((r) => r.id).toSet();
      await c.read(apagarDadosUseCaseProvider).apagarTudo();
      expect(ConclusoesRevisaoRepositorio.box.values, isEmpty);
      await c.read(backupUseCaseProvider).mesclar(backup);
      await c.read(backupUseCaseProvider).mesclar(backup);
      expect(ConclusoesRevisaoRepositorio.box.values, hasLength(3));
      await c
          .read(revisaoUseCaseProvider)
          .concluir(revisao('r0'), questoes: 10, acertos: 0);
      expect(c.read(registrosProvider).map((r) => r.id).toSet(), sessaoIds);
      expect(c.read(revisoesProvider).where((r) => r.id == 'r0'), isEmpty);
      await c
          .read(revisaoUseCaseProvider)
          .concluir(revisao('r4'), questoes: 10, acertos: 8);
      expect(c.read(registrosProvider), hasLength(4));
      expect(
        c.read(registrosProvider).where((r) => r.minutos == 0),
        hasLength(1),
      );
    },
  );

  for (final operacao in ['apagar', 'restaurar']) {
    test(
      '$operacao espera conclusao pendente e nao ressuscita dados',
      () async {
        final vazio = ImportService.parseBackup('{"versao":1,"materias":[]}');
        final pausada = Completer<void>();
        final liberar = Completer<void>();
        c.dispose();
        c = ProviderContainer(
          overrides: [
            revisaoUseCaseProvider.overrideWith(
              (ref) => RevisaoUseCase(
                ref,
                aposEtapaPersistida: (etapa) async {
                  if (etapa == 'sessao') {
                    pausada.complete();
                    await liberar.future;
                  }
                },
              ),
            ),
          ],
        );
        final conclusao = c
            .read(revisaoUseCaseProvider)
            .concluir(revisao('pendente'), questoes: 10, acertos: 8);
        await pausada.future;
        var terminou = false;
        final alteracao =
            (operacao == 'apagar'
                    ? c.read(apagarDadosUseCaseProvider).apagarTudo()
                    : c
                          .read(backupUseCaseProvider)
                          .restaurarSubstituindo(vazio))
                .then((_) {
                  terminou = true;
                });
        try {
          // Entrega eventos/escritas Hive; a operação destrutiva ainda deve
          // aguardar o lock, mesmo depois de oportunidades para prosseguir.
          await Future<void>.delayed(const Duration(milliseconds: 30));
          expect(terminou, false);
          expect(Hive.box<Map>(HiveBoxes.registros).length, 1);
          expect(ConclusoesRevisaoRepositorio.box.length, 1);
        } finally {
          liberar.complete();
          await conclusao;
          await alteracao;
        }
        expect(c.read(registrosProvider), isEmpty);
        expect(c.read(revisoesProvider), isEmpty);
        expect(ConclusoesRevisaoRepositorio.box.values, isEmpty);
        c.dispose();
        await Hive.close();
        await HiveBoxes.openAll();
        await HiveBoxes.migrar();
        c = ProviderContainer();
        expect(c.read(registrosProvider), isEmpty);
        expect(c.read(revisoesProvider), isEmpty);
        expect(ConclusoesRevisaoRepositorio.box.values, isEmpty);
      },
    );
  }

  test(
    'extensoes plano e concursos sobrevivem exportar restaurar e desfazer',
    () async {
      final box = Hive.box<Map>(HiveBoxes.config);
      final plano = <String, dynamic>{
        'dias': {'1': 120},
        'excecoes': {},
        'comuns': {},
        'principal': 'geral',
        'secundarios': [],
        'percentual': 80,
        'blocos': [],
        'vinculos': {},
        'avisos': [],
      };
      final concursos = <String, dynamic>{
        'acompanhados': ['fgv:teste'],
        'consultas': {},
        'publicacoes': {},
      };
      await box.put('planoDiario', plano);
      await box.put('concursos', concursos);
      final backup = ImportService.parseBackup(
        c.read(backupUseCaseProvider).snapshotAtual(),
      );
      await c.read(apagarDadosUseCaseProvider).apagarTudo();
      expect(box.get('planoDiario'), isNull);
      expect(box.get('concursos'), isNull);
      await c.read(backupUseCaseProvider).restaurarSubstituindo(backup);
      expect(box.get('planoDiario'), plano);
      expect(box.get('concursos'), concursos);
      expect(
        await c.read(backupUseCaseProvider).desfazerUltimaRestauracao(),
        true,
      );
      expect(box.get('planoDiario'), isNull);
      expect(box.get('concursos'), isNull);
    },
  );
  test(
    'mesclar snapshot anterior nao reabre nem ressuscita conclusao local',
    () async {
      final r = revisao('antiga');
      await c.read(revisoesProvider.notifier).salvar(r);
      await c.read(revisoesProvider.notifier).salvar(revisao('sem-recibo'));
      final anterior = ImportService.parseBackup(
        c.read(backupUseCaseProvider).snapshotAtual(),
      );
      final concluida = await c
          .read(revisaoUseCaseProvider)
          .concluir(r, questoes: 10, acertos: 8);
      // Revisão sem recibo continua elegível para importação normal.
      await c.read(revisoesProvider.notifier).remover('sem-recibo');
      await c.read(backupUseCaseProvider).mesclar(anterior);
      expect(
        c.read(revisoesProvider).singleWhere((e) => e.id == 'sem-recibo').feita,
        false,
      );
      expect(
        c.read(revisoesProvider).singleWhere((e) => e.id == r.id).feita,
        true,
      );
      final repetida = await c.read(revisaoUseCaseProvider).concluir(r);
      expect(repetida.proxima!.id, concluida.proxima!.id);
      expect(c.read(registrosProvider), hasLength(1));
      await c.read(revisoesProvider.notifier).remover(r.id);
      await c.read(backupUseCaseProvider).mesclar(anterior);
      await c.read(backupUseCaseProvider).mesclar(anterior);
      expect(c.read(revisoesProvider).where((e) => e.id == r.id), isEmpty);
      expect(c.read(registrosProvider), hasLength(1));
      c.dispose();
      await Hive.close();
      await HiveBoxes.openAll();
      await HiveBoxes.migrar();
      c = ProviderContainer();
      expect(c.read(revisoesProvider).where((e) => e.id == r.id), isEmpty);
      expect(c.read(registrosProvider), hasLength(1));
    },
  );
  for (final aplicada in [true, false]) {
    test(
      'recibo importado aplicada=$aplicada impede revisão pendente do snapshot',
      () async {
        final r = revisao('importada');
        await c.read(revisoesProvider.notifier).salvar(r);
        final result = await c
            .read(revisaoUseCaseProvider)
            .concluir(r, questoes: 10, acertos: 8);
        final json =
            jsonDecode(c.read(backupUseCaseProvider).snapshotAtual())
                as Map<String, dynamic>;
        json['revisoes'] = [r.toJson()];
        (json['conclusoesRevisao'] as List).single['aplicada'] = aplicada;
        final backup = ImportService.parseBackup(jsonEncode(json));
        await c.read(apagarDadosUseCaseProvider).apagarTudo();
        await c.read(backupUseCaseProvider).mesclar(backup);
        await c.read(backupUseCaseProvider).mesclar(backup);
        expect(
          c.read(revisoesProvider).where((e) => e.id == r.id && !e.feita),
          isEmpty,
        );
        expect(ConclusoesRevisaoRepositorio.box.get(r.id)!['aplicada'], true);
        expect(c.read(registrosProvider), hasLength(1));
        if (!aplicada) {
          expect(
            c.read(revisoesProvider).singleWhere((e) => e.id == r.id).feita,
            true,
          );
          expect(
            c.read(revisoesProvider).where((e) => e.id == result.proxima!.id),
            hasLength(1),
          );
        }
      },
    );
  }
}
