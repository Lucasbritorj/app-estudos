import 'dart:convert';

import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:app_estudos/domain/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

Materia m(String id, String ambienteId) => Materia(
      id: id,
      nome: id,
      ambienteId: ambienteId,
      corSlot: 0,
      criadaEm: DateTime(2026, 1, 1),
    );

void main() {
  final ambiente = Ambiente(
      id: 'sefaz', nome: 'SEFAZ-RN 2026', criadoEm: DateTime(2026, 1, 1));

  group('jsonAmbiente', () {
    test('exporta só o que pertence ao ambiente', () {
      final materias = [m('m1', 'sefaz'), m('m2', 'outro')];
      final topicos = [
        Topico(id: 't1', materiaId: 'm1', nome: 'T1'),
        Topico(id: 't2', materiaId: 'm2', nome: 'T2'),
      ];
      final aulas = [
        Aula(
            id: 'a1',
            materiaId: 'm1',
            nome: 'Aula 1',
            paginasTotais: 10),
        Aula(
            id: 'a2',
            materiaId: 'm2',
            nome: 'Aula 2',
            paginasTotais: 10),
      ];
      final registros = [
        RegistroHora(
            id: 'r1',
            data: DateTime(2026, 7, 1),
            materiaId: 'm1',
            minutos: 60),
        RegistroHora(
            id: 'r2',
            data: DateTime(2026, 7, 1),
            materiaId: 'm2',
            minutos: 30),
      ];
      final revisoes = [
        Revisao(
            id: 'v1',
            materiaId: 'm1',
            titulo: 'Rev 1',
            dataAgendada: DateTime(2026, 7, 8),
            intervaloDias: 7),
        Revisao(
            id: 'v2',
            materiaId: 'm2',
            titulo: 'Rev 2',
            dataAgendada: DateTime(2026, 7, 8),
            intervaloDias: 7),
      ];

      final json = ExportService.jsonAmbiente(
        ambiente: ambiente,
        materias: materias,
        topicos: topicos,
        aulas: aulas,
        registros: registros,
        revisoes: revisoes,
      );
      final mapa = jsonDecode(json) as Map<String, dynamic>;
      expect((mapa['ambientes'] as List).single['id'], 'sefaz');
      expect((mapa['materias'] as List).single['id'], 'm1');
      expect((mapa['topicos'] as List).single['id'], 't1');
      expect((mapa['aulas'] as List).single['id'], 'a1');
      expect((mapa['registros'] as List).single['id'], 'r1');
      expect((mapa['revisoes'] as List).single['id'], 'v1');
      expect(mapa['leituras'], isEmpty);
      expect(mapa['planejamento'], isEmpty);
    });

    test('roundtrip: parseBackup lê o export de ambiente', () {
      final json = ExportService.jsonAmbiente(
        ambiente: ambiente,
        materias: [m('m1', 'sefaz')],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
      );
      final backup = ImportService.parseBackup(json);
      expect(backup.ambientes.single.nome, 'SEFAZ-RN 2026');
      expect(backup.materias.single.ambienteId, 'sefaz');
    });
  });

  group('backup pré-Ambientes', () {
    test('ambientesOuGeral inventa o Geral quando lista vazia', () {
      final json = ExportService.jsonCompleto(
        materias: const [],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
        leituras: const [],
        planejamento: const {},
      );
      // Simula backup antigo removendo o campo novo.
      final mapa = jsonDecode(json) as Map<String, dynamic>;
      mapa.remove('ambientes');
      final backup = ImportService.parseBackup(jsonEncode(mapa));
      expect(backup.ambientes, isEmpty);
      final efetivos = backup.ambientesOuGeral(DateTime(2026, 7, 10));
      expect(efetivos.single.id, Ambiente.geralId);
      expect(efetivos.single.nome, 'Geral');
    });
  });
}
