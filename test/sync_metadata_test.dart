import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/data/repositories/planejamento_repositorio.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Metadados de sincronização futura (1a do plano de melhorias): carimbo
/// de última modificação (atualizadaEm/atualizadoEm) e soft delete por
/// tombstone (excluidaEm/excluidoEm) em Matérias, Registros e
/// Planejamento — sem mudar a premissa local-first.
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_sync_meta_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrar();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Materia materia(String id) =>
      Materia(id: id, nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026, 1, 1));

  RegistroHora registro(String id) => RegistroHora(
    id: id,
    data: DateTime(2026, 2, 10),
    materiaId: 'm1',
    minutos: 60,
  );

  group('modelo — tolerância e round-trip', () {
    test('Materia sem atualizadaEm no JSON herda criadaEm', () {
      final json = materia('m1').toJson()
        ..remove('atualizadaEm')
        ..remove('excluidaEm');
      final lida = Materia.fromJson(json);
      expect(lida.atualizadaEm, DateTime(2026, 1, 1));
      expect(lida.excluidaEm, isNull);
    });

    test('Materia round-trip preserva atualizadaEm e excluidaEm', () {
      final marcada = materia(
        'm1',
      ).comAtualizacao(DateTime(2026, 3, 1)).comExclusao(DateTime(2026, 3, 2));
      final lida = Materia.fromJson(marcada.toJson());
      expect(lida.atualizadaEm, DateTime(2026, 3, 2));
      expect(lida.excluidaEm, DateTime(2026, 3, 2));
    });

    test('RegistroHora sem atualizadoEm no JSON herda data', () {
      final json = registro('r1').toJson()
        ..remove('atualizadoEm')
        ..remove('excluidoEm');
      final lido = RegistroHora.fromJson(json);
      expect(lido.atualizadoEm, DateTime(2026, 2, 10));
      expect(lido.excluidoEm, isNull);
    });
  });

  group('repositório — carimbo e tombstone', () {
    test('salvar carimba atualizadaEm com o agora', () async {
      final antes = DateTime.now();
      await container.read(materiasProvider.notifier).salvar(materia('m1'));
      final salva = container.read(materiasProvider).single;
      expect(salva.atualizadaEm.isBefore(antes), isFalse);
      expect(salva.criadaEm, DateTime(2026, 1, 1));
    });

    test(
      'remover tombstona: some do state, fica no box com excluidaEm',
      () async {
        final repo = container.read(materiasProvider.notifier);
        await repo.salvar(materia('m1'));
        await repo.remover('m1');

        expect(container.read(materiasProvider), isEmpty);
        final noBox = Hive.box<Map>(HiveBoxes.materias).get('m1');
        expect(noBox, isNotNull);
        expect(noBox!['excluidaEm'], isNotNull);
      },
    );

    test('build() filtra tombstones ao recarregar do box', () async {
      final repo = container.read(materiasProvider.notifier);
      await repo.salvar(materia('m1'));
      await repo.remover('m1');

      final outro = ProviderContainer();
      addTearDown(outro.dispose);
      expect(outro.read(materiasProvider), isEmpty);
    });

    test('salvar o mesmo id ressuscita a matéria tombstonada', () async {
      final repo = container.read(materiasProvider.notifier);
      await repo.salvar(materia('m1'));
      await repo.remover('m1');
      await repo.salvar(materia('m1'));

      expect(container.read(materiasProvider).single.excluidaEm, isNull);
      final noBox = Hive.box<Map>(HiveBoxes.materias).get('m1');
      expect(noBox!['excluidaEm'], isNull);
    });

    test('removerOnde tombstona registros em lote', () async {
      final repo = container.read(registrosProvider.notifier);
      await repo.salvar(registro('r1'));
      await repo.salvar(registro('r2'));
      await repo.removerOnde((r) => r.materiaId == 'm1');

      expect(container.read(registrosProvider), isEmpty);
      final box = Hive.box<Map>(HiveBoxes.registros);
      expect(box.get('r1')!['excluidoEm'], isNotNull);
      expect(box.get('r2')!['excluidoEm'], isNotNull);
    });

    test('entidade sem suporte (Topico) segue com hard delete', () async {
      final repo = container.read(topicosProvider.notifier);
      await repo.salvar(Topico(id: 't1', materiaId: 'm1', nome: 'Atos'));
      await repo.remover('t1');

      expect(Hive.box<Map>(HiveBoxes.topicos).get('t1'), isNull);
    });
  });

  group('planejamento — formato com carimbo', () {
    test('grava formato novo {dias, atualizadoEm} e lê de volta', () async {
      final repo = container.read(planejamentoProvider.notifier);
      await repo.definirDia(1, 120);

      final raw = Hive.box<Map>(HiveBoxes.planejamento).get('semana');
      expect(raw!['dias'], {'1': 120});
      expect(raw['atualizadoEm'], isNotNull);
      expect(container.read(planejamentoProvider), {1: 120});
    });

    test('lê formato legado (mapa de dias direto)', () async {
      await Hive.box<Map>(
        HiveBoxes.planejamento,
      ).put('semana', {'2': 90, '4': 45});

      final outro = ProviderContainer();
      addTearDown(outro.dispose);
      expect(outro.read(planejamentoProvider), {2: 90, 4: 45});
    });
  });
}
