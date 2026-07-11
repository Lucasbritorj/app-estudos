import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_migracao_');
    Hive.init(dir.path);
    await Hive.openBox<Map>(HiveBoxes.ambientes);
    await Hive.openBox<Map>(HiveBoxes.materias);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('box vazio ganha o ambiente Geral', () async {
    await HiveBoxes.migrarAmbientes();
    final box = Hive.box<Map>(HiveBoxes.ambientes);
    expect(box.length, 1);
    final geral = Ambiente.fromJson(
        Map<String, dynamic>.from(box.get(Ambiente.geralId)!));
    expect(geral.nome, 'Geral');
  });

  test('matéria antiga sem ambienteId é gravada com Geral', () async {
    final materias = Hive.box<Map>(HiveBoxes.materias);
    // Simula gravação pré-Ambientes: sem o campo.
    final antiga = Materia(
      id: 'm1',
      nome: 'AFO',
      corSlot: 0,
      criadaEm: DateTime(2026, 1, 1),
    ).toJson()
      ..remove('ambienteId');
    await materias.put('m1', antiga);

    await HiveBoxes.migrarAmbientes();

    final gravada = materias.get('m1')!;
    expect(gravada['ambienteId'], Ambiente.geralId);
  });

  test('idempotente: rodar duas vezes não duplica nem sobrescreve', () async {
    await HiveBoxes.migrarAmbientes();
    final box = Hive.box<Map>(HiveBoxes.ambientes);
    // Usuário renomeia o Geral; nova migração NÃO pode desfazer.
    final renomeado = Map<String, dynamic>.from(box.get(Ambiente.geralId)!);
    renomeado['nome'] = 'Meus estudos';
    await box.put(Ambiente.geralId, renomeado);

    await HiveBoxes.migrarAmbientes();
    expect(box.length, 1);
    expect(box.get(Ambiente.geralId)!['nome'], 'Meus estudos');
  });

  test('matéria já migrada não é tocada', () async {
    final materias = Hive.box<Map>(HiveBoxes.materias);
    await materias.put(
        'm1',
        Materia(
          id: 'm1',
          nome: 'Python',
          ambienteId: 'curso',
          corSlot: 1,
          criadaEm: DateTime(2026, 1, 1),
        ).toJson());
    await HiveBoxes.migrarAmbientes();
    expect(materias.get('m1')!['ambienteId'], 'curso');
  });
}
