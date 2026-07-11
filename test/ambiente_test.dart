import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Ambiente', () {
    test('roundtrip JSON preserva tudo', () {
      final ambiente = Ambiente(
        id: 'a1',
        nome: 'Concurso SEFAZ-RN 2026',
        corSlot: 3,
        arquivado: true,
        criadoEm: DateTime(2026, 7, 10),
      );
      final volta = Ambiente.fromJson(ambiente.toJson());
      expect(volta.id, 'a1');
      expect(volta.nome, 'Concurso SEFAZ-RN 2026');
      expect(volta.corSlot, 3);
      expect(volta.arquivado, true);
      expect(volta.criadoEm, DateTime(2026, 7, 10));
    });
  });

  group('Materia.ambienteId', () {
    test('JSON antigo sem ambienteId cai no Geral', () {
      final materia = Materia.fromJson({
        'id': 'm1',
        'nome': 'AFO',
        'corSlot': 0,
        'criadaEm': DateTime(2026, 1, 1).toIso8601String(),
      });
      expect(materia.ambienteId, Ambiente.geralId);
    });

    test('roundtrip preserva ambienteId', () {
      final materia = Materia(
        id: 'm1',
        nome: 'AFO',
        ambienteId: 'a1',
        corSlot: 0,
        criadaEm: DateTime(2026, 1, 1),
      );
      expect(Materia.fromJson(materia.toJson()).ambienteId, 'a1');
    });

    test('copyWith move de ambiente', () {
      final materia = Materia(
        id: 'm1',
        nome: 'AFO',
        ambienteId: 'a1',
        corSlot: 0,
        criadaEm: DateTime(2026, 1, 1),
      );
      expect(materia.copyWith(ambienteId: 'a2').ambienteId, 'a2');
      expect(materia.copyWith(nome: 'AFO II').ambienteId, 'a1');
    });
  });

  group('Configuracoes.ambienteAtivoId', () {
    test('roundtrip com e sem ambiente ativo', () {
      const comAtivo = Configuracoes(ambienteAtivoId: 'a1');
      expect(
          Configuracoes.fromJson(comAtivo.toJson()).ambienteAtivoId, 'a1');
      const semAtivo = Configuracoes();
      expect(
          Configuracoes.fromJson(semAtivo.toJson()).ambienteAtivoId, null);
    });

    test('copyWith troca e limparAmbienteAtivo zera', () {
      const config = Configuracoes(ambienteAtivoId: 'a1');
      expect(config.copyWith(ambienteAtivoId: 'a2').ambienteAtivoId, 'a2');
      expect(
          config.copyWith(limparAmbienteAtivo: true).ambienteAtivoId, null);
      // copyWith sem tocar no campo preserva.
      expect(config.copyWith(horaNotificacao: 8).ambienteAtivoId, 'a1');
    });
  });
}
