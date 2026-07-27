import 'dart:io';

import 'package:app_estudos/application/aula_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// D-04: excluir uma aula não tinha cascata — RegistroHora.aulaId e
/// Revisao.aulaId ficavam órfãos, apontando pra uma aula inexistente.
/// Espelha o padrão de materia_cascata_test.dart, mas com decisões
/// diferentes por entidade: registro de horas (log histórico) NUNCA é
/// destruído, só perde o vínculo com a aula; revisão pendente da cadeia
/// desta aula é removida de verdade (sem a aula, não há o que revisar);
/// revisão FEITA fica intocada, como no cascade de matéria (conta XP).
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_aula_cascata_');
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

  test(
      'excluirEmCascata remove a aula, limpa aulaId órfão nos registros e '
      'remove só as revisões pendentes da cadeia', () async {
    await container.read(materiasProvider.notifier).salvar(Materia(
        id: 'm1', nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026, 1, 1)));

    await container.read(aulasProvider.notifier).mesclar([
      Aula(id: 'a1', materiaId: 'm1', nome: 'Aula 01', paginasTotais: 10),
      Aula(id: 'a2', materiaId: 'm1', nome: 'Aula 02', paginasTotais: 10),
    ]);

    await container.read(registrosProvider.notifier).mesclar([
      RegistroHora(
          id: 'reg-a1',
          data: DateTime(2026, 7, 10),
          materiaId: 'm1',
          aulaId: 'a1',
          minutos: 60),
      RegistroHora(
          id: 'reg-a2',
          data: DateTime(2026, 7, 11),
          materiaId: 'm1',
          aulaId: 'a2',
          minutos: 45),
      RegistroHora(
          id: 'reg-sem-aula',
          data: DateTime(2026, 7, 12),
          materiaId: 'm1',
          minutos: 30),
    ]);

    await container.read(revisoesProvider.notifier).mesclar([
      Revisao(
          id: 'rev-pendente-a1',
          materiaId: 'm1',
          aulaId: 'a1',
          titulo: 'Aula 01 — 7d',
          dataAgendada: DateTime(2026, 7, 20),
          intervaloDias: 7),
      Revisao(
          id: 'rev-feita-a1',
          materiaId: 'm1',
          aulaId: 'a1',
          titulo: 'Aula 01 — 7d',
          dataAgendada: DateTime(2026, 7, 1),
          intervaloDias: 7,
          feita: true,
          dataConclusao: DateTime(2026, 7, 1)),
      Revisao(
          id: 'rev-a2',
          materiaId: 'm1',
          aulaId: 'a2',
          titulo: 'Aula 02 — 7d',
          dataAgendada: DateTime(2026, 7, 21),
          intervaloDias: 7),
    ]);

    await container.read(aulaUseCaseProvider).excluirEmCascata('a1');

    // Aula some; a outra aula da mesma matéria fica intacta.
    expect(container.read(aulasProvider).map((a) => a.id), ['a2']);

    // Registros: NENHUM é destruído (log histórico) — só o vínculo órfão
    // some. reg-a2 e reg-sem-aula ficam bit a bit intactos.
    final registros = {
      for (final r in container.read(registrosProvider)) r.id: r,
    };
    expect(registros.keys, containsAll(['reg-a1', 'reg-a2', 'reg-sem-aula']));
    expect(registros['reg-a1']!.aulaId, isNull);
    expect(registros['reg-a1']!.minutos, 60); // dado histórico preservado
    expect(registros['reg-a2']!.aulaId, 'a2');
    expect(registros['reg-sem-aula']!.aulaId, isNull);

    // Revisões: pendente da cadeia de a1 some; feita de a1 fica (XP); de
    // a2 nem é tocada.
    final revisoesRestantes = container.read(revisoesProvider).map((r) => r.id);
    expect(revisoesRestantes, isNot(contains('rev-pendente-a1')));
    expect(revisoesRestantes, containsAll(['rev-feita-a1', 'rev-a2']));
  });

  test('excluir aula sem nenhum dependente não lança exceção', () async {
    await container.read(materiasProvider.notifier).salvar(Materia(
        id: 'm1', nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026, 1, 1)));
    await container.read(aulasProvider.notifier).salvar(
        Aula(id: 'a1', materiaId: 'm1', nome: 'Aula 01', paginasTotais: 10));

    await container.read(aulaUseCaseProvider).excluirEmCascata('a1');

    expect(container.read(aulasProvider), isEmpty);
  });
}
