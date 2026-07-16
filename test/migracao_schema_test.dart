import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Pipeline versionado (migrar) e reparo de órfãos (repararOrfaos): crash
/// entre "aula concluída" e "Revisão 1 criada" deixa de ser perda
/// permanente — o boot religa a cadeia.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_schema_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> gravarAula(Aula aula) async =>
      Hive.box<Map>(HiveBoxes.aulas).put(aula.id, aula.toJson());

  Aula aulaConcluida(String id) => Aula(
        id: id,
        materiaId: 'm1',
        nome: 'Aula 01',
        paginasTotais: 10,
        paginasLidas: 10,
        concluida: true,
        dataConclusao: DateTime(2026, 7, 10),
      );

  test('repararOrfaos recria Revisão 1 de aula concluída sem cadeia',
      () async {
    await gravarAula(aulaConcluida('a1'));

    await HiveBoxes.repararOrfaos();

    final revisoes = Hive.box<Map>(HiveBoxes.revisoes);
    expect(revisoes.length, 1);
    final r = Revisao.fromJson(
        Map<String, dynamic>.from(revisoes.values.first));
    expect(r.aulaId, 'a1');
    expect(r.intervaloDias, 7);
    expect(r.dataAgendada, DateTime(2026, 7, 17)); // conclusão + 7d
  });

  test('não duplica: aula que já tem revisão na cadeia é ignorada', () async {
    await gravarAula(aulaConcluida('a1'));
    // Cadeia já progrediu: só há revisão FEITA com o aulaId.
    final feita = Revisao(
      id: 'r-feita',
      materiaId: 'm1',
      aulaId: 'a1',
      titulo: 'AFO 7d',
      dataAgendada: DateTime(2026, 7, 17),
      intervaloDias: 7,
      feita: true,
      dataConclusao: DateTime(2026, 7, 17),
    );
    await Hive.box<Map>(HiveBoxes.revisoes).put(feita.id, feita.toJson());

    await HiveBoxes.repararOrfaos();

    expect(Hive.box<Map>(HiveBoxes.revisoes).length, 1); // nada recriado
  });

  test('aula não concluída não gera revisão', () async {
    await gravarAula(Aula(
        id: 'a2', materiaId: 'm1', nome: 'Aula 02', paginasTotais: 10));
    await HiveBoxes.repararOrfaos();
    expect(Hive.box<Map>(HiveBoxes.revisoes).isEmpty, isTrue);
  });

  test('migrar roda uma vez e grava schemaVersion; segundo boot é no-op',
      () async {
    await gravarAula(aulaConcluida('a1'));

    await HiveBoxes.migrar();
    expect(Hive.box<Map>(HiveBoxes.config).get('schemaVersion')?['v'],
        HiveBoxes.schemaVersion);
    expect(Hive.box<Map>(HiveBoxes.revisoes).length, 1);

    // Segundo boot: versão em dia, repararOrfaos não roda de novo.
    await HiveBoxes.migrar();
    expect(Hive.box<Map>(HiveBoxes.revisoes).length, 1);
  });
}
