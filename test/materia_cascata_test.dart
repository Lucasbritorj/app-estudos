import 'dart:io';

import 'package:app_estudos/application/materia_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Integridade referencial na exclusão de matéria: dependentes estruturais
/// (tópicos, aulas, revisões pendentes) caem em cascata; o log histórico
/// (registros) e as revisões feitas (XP da gamificação) ficam.
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_cascata_');
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

  test('excluirEmCascata remove dependentes e preserva histórico', () async {
    final materias = container.read(materiasProvider.notifier);
    await materias.salvar(Materia(
        id: 'm1', nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026, 1, 1)));
    await materias.salvar(Materia(
        id: 'm2', nome: 'LP', corSlot: 1, criadaEm: DateTime(2026, 1, 1)));

    await container.read(topicosProvider.notifier).mesclar([
      const Topico(id: 't1', materiaId: 'm1', nome: 'Orçamento'),
      const Topico(id: 't2', materiaId: 'm2', nome: 'Crase'),
    ]);
    await container.read(aulasProvider.notifier).salvar(Aula(
        id: 'a1', materiaId: 'm1', nome: 'Aula 01', paginasTotais: 10));
    await container.read(revisoesProvider.notifier).mesclar([
      Revisao(
          id: 'r-pendente',
          materiaId: 'm1',
          titulo: 'AFO 7d',
          dataAgendada: DateTime(2026, 7, 20),
          intervaloDias: 7),
      Revisao(
          id: 'r-feita',
          materiaId: 'm1',
          titulo: 'AFO 7d',
          dataAgendada: DateTime(2026, 7, 1),
          intervaloDias: 7,
          feita: true,
          dataConclusao: DateTime(2026, 7, 1)),
      Revisao(
          id: 'r-outra-materia',
          materiaId: 'm2',
          titulo: 'LP 7d',
          dataAgendada: DateTime(2026, 7, 20),
          intervaloDias: 7),
    ]);
    await container.read(registrosProvider.notifier).salvar(RegistroHora(
        id: 'reg1',
        data: DateTime(2026, 7, 10),
        materiaId: 'm1',
        minutos: 60));

    await container.read(materiaUseCaseProvider).excluirEmCascata('m1');

    expect(container.read(materiasProvider).map((m) => m.id), ['m2']);
    // Dependentes estruturais da m1 caem; os da m2 ficam intactos.
    expect(container.read(topicosProvider).map((t) => t.id), ['t2']);
    expect(container.read(aulasProvider), isEmpty);
    expect(container.read(revisoesProvider).map((r) => r.id),
        containsAll(['r-feita', 'r-outra-materia']));
    expect(container.read(revisoesProvider).map((r) => r.id),
        isNot(contains('r-pendente')));
    // Log histórico intocado.
    expect(container.read(registrosProvider).map((r) => r.id), ['reg1']);
  });

  test(
    'D-04: excluir matéria limpa o aulaId dos registros, sem tocar nos de outra',
    () async {
      // Contraprova do furo: `AulaUseCase.excluirEmCascata` limpa `aulaId` no
      // caminho direto, mas a matéria removia as aulas por `removerOnde` e
      // deixava a referência pendurada. Como o registro é log histórico e
      // nunca é apagado, o `aulaId` morto sobrevivia para sempre.
      final materias = container.read(materiasProvider.notifier);
      await materias.salvar(
        Materia(
          id: 'm1',
          nome: 'AFO',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        ),
      );
      await materias.salvar(
        Materia(
          id: 'm2',
          nome: 'LP',
          corSlot: 1,
          criadaEm: DateTime(2026, 1, 1),
        ),
      );

      final aulas = container.read(aulasProvider.notifier);
      await aulas.salvar(
        Aula(id: 'a1', materiaId: 'm1', nome: 'Aula 01', paginasTotais: 10),
      );
      await aulas.salvar(
        Aula(id: 'a2', materiaId: 'm1', nome: 'Aula 02', paginasTotais: 20),
      );
      await aulas.salvar(
        Aula(id: 'a9', materiaId: 'm2', nome: 'Crase 01', paginasTotais: 5),
      );

      final registros = container.read(registrosProvider.notifier);
      // Tipo explícito: com `null` numa posição e String nas outras, deixar a
      // inferência decidir o tipo do record é aposta desnecessária.
      const semente = <(String, String, String?)>[
        ('reg-a1', 'm1', 'a1'),
        ('reg-a2', 'm1', 'a2'),
        ('reg-sem-aula', 'm1', null),
        ('reg-outra-materia', 'm2', 'a9'),
      ];
      for (final (id, materiaId, aulaId) in semente) {
        await registros.salvar(
          RegistroHora(
            id: id,
            data: DateTime(2026, 7, 10),
            materiaId: materiaId,
            aulaId: aulaId,
            minutos: 60,
          ),
        );
      }

      await container.read(materiaUseCaseProvider).excluirEmCascata('m1');

      RegistroHora lido(String id) =>
          container.read(registrosProvider).firstWhere((r) => r.id == id);

      // Nenhum registro some — só a referência morta.
      expect(container.read(registrosProvider), hasLength(4));
      expect(lido('reg-a1').aulaId, isNull);
      expect(lido('reg-a2').aulaId, isNull);
      expect(lido('reg-sem-aula').aulaId, isNull);
      // A aula de OUTRA matéria continua existindo: mexer nela seria dano
      // colateral, não cascata.
      expect(lido('reg-outra-materia').aulaId, 'a9');
      expect(container.read(aulasProvider).map((a) => a.id), ['a9']);

      // Invariante geral: nenhum aulaId aponta para aula inexistente.
      final idsVivos = container.read(aulasProvider).map((a) => a.id).toSet();
      for (final r in container.read(registrosProvider)) {
        if (r.aulaId != null) {
          expect(idsVivos, contains(r.aulaId));
        }
      }
    },
  );
}
