import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:flutter_test/flutter_test.dart';

/// Invariantes garantidas no construtor dos modelos (item 10 da auditoria):
/// nenhuma via — form, import de backup, cálculo — grava valores impossíveis.
void main() {
  final data = DateTime(2026, 1, 1);

  group('RegistroHora', () {
    test('acertos nunca passam das questões (senão contaminam o Elo)', () {
      final r = RegistroHora(
          id: 'r', data: data, materiaId: 'm', minutos: 60, questoes: 5, acertos: 10);
      expect(r.acertos, 5);
      expect(r.taxaAcerto, 1.0);
    });

    test('minutos/questões/páginas negativos são zerados', () {
      final r = RegistroHora(
          id: 'r',
          data: data,
          materiaId: 'm',
          minutos: -30,
          questoes: -4,
          acertos: -2,
          paginasLidasManual: -5);
      expect(r.minutos, 0);
      expect(r.questoes, 0);
      expect(r.taxaAcerto, isNull);
      expect(r.paginasLidasManual, 0);
    });

    test('acerto sem questões é descartado', () {
      final r = RegistroHora(
          id: 'r', data: data, materiaId: 'm', minutos: 60, acertos: 8);
      expect(r.acertos, isNull);
    });

    test('fromJson (caminho do import) também clampa', () {
      final r = RegistroHora.fromJson({
        'id': 'r',
        'data': data.toIso8601String(),
        'materiaId': 'm',
        'minutos': 60,
        'questoes': 3,
        'acertos': 99,
      });
      expect(r.acertos, 3);
    });

    test('valores válidos passam intactos', () {
      final r = RegistroHora(
          id: 'r', data: data, materiaId: 'm', minutos: 45, questoes: 10, acertos: 7);
      expect((r.minutos, r.questoes, r.acertos), (45, 10, 7));
    });
  });

  group('Aula', () {
    test('páginas lidas nunca passam do total', () {
      final a = Aula(
          id: 'a', materiaId: 'm', nome: 'Aula 00', paginasTotais: 10, paginasLidas: 25);
      expect(a.paginasLidas, 10);
      expect(a.progresso, 1.0);
      expect(a.paginasRestantes, 0);
    });

    test('total e lidas negativos são zerados', () {
      final a = Aula(
          id: 'a', materiaId: 'm', nome: 'x', paginasTotais: -5, paginasLidas: -3);
      expect((a.paginasTotais, a.paginasLidas), (0, 0));
    });

    test('fromJson clampa lidas > total (backup corrompido)', () {
      final a = Aula.fromJson({
        'id': 'a',
        'materiaId': 'm',
        'nome': 'x',
        'paginasTotais': 8,
        'paginasLidas': 20,
      });
      expect(a.paginasLidas, 8);
    });

    test('copyWith reduzindo o total reclampa as lidas', () {
      final a = Aula(
          id: 'a', materiaId: 'm', nome: 'x', paginasTotais: 100, paginasLidas: 80);
      expect(a.copyWith(paginasTotais: 50).paginasLidas, 50);
    });
  });
}
