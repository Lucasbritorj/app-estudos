import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/aula_service.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

Aula aula({int totais = 100, int lidas = 0, bool concluida = false}) => Aula(
      id: 'a1',
      materiaId: 'm1',
      nome: 'Aula 00 — Licitações',
      paginasTotais: totais,
      paginasLidas: lidas,
      concluida: concluida,
    );

RegistroHora sessao({
  String? aulaId = 'a1',
  TipoEstudo tipo = TipoEstudo.teoria,
  int minutos = 60,
  int? paginas,
  int? questoes,
  int? acertos,
}) =>
    RegistroHora(
      id: '$aulaId-$minutos-$paginas-$questoes',
      data: DateTime(2026, 7, 9),
      materiaId: 'm1',
      aulaId: aulaId,
      tipo: tipo,
      minutos: minutos,
      paginasLidasManual: paginas,
      questoes: questoes,
      acertos: acertos,
    );

void main() {
  group('aplicarSessao', () {
    test('acumula páginas sem concluir', () {
      final r = AulaService.aplicarSessao(
          aula(lidas: 20), 25, DateTime(2026, 7, 9, 22));
      expect(r.aula.paginasLidas, 45);
      expect(r.aula.concluida, false);
      expect(r.concluiuAgora, false);
      expect(r.aula.dataConclusao, isNull);
    });

    test('atingir o total conclui e grava dataConclusao (só a data)', () {
      final r = AulaService.aplicarSessao(
          aula(lidas: 90), 15, DateTime(2026, 7, 9, 22, 30));
      expect(r.aula.paginasLidas, 100); // teto no total, não 105
      expect(r.aula.concluida, true);
      expect(r.concluiuAgora, true);
      expect(r.aula.dataConclusao, DateTime(2026, 7, 9));
    });

    test('sessão em aula já concluída NÃO redispara o gatilho', () {
      final r = AulaService.aplicarSessao(
          aula(lidas: 100, concluida: true), 10, DateTime(2026, 7, 10));
      expect(r.concluiuAgora, false);
      expect(r.aula.concluida, true);
    });

    test('páginas <= 0 não muda nada', () {
      final original = aula(lidas: 50);
      final r = AulaService.aplicarSessao(original, 0, DateTime(2026, 7, 9));
      expect(r.aula.paginasLidas, 50);
      expect(r.concluiuAgora, false);
    });
  });

  group('ritmoDaAula / projeção', () {
    test('só sessões teóricas da aula entram no ritmo', () {
      final registros = [
        sessao(minutos: 60, paginas: 30), // 30 pág/h
        sessao(minutos: 60, questoes: 10, acertos: 8,
            tipo: TipoEstudo.pratica), // prática: fora
        sessao(aulaId: 'outra', minutos: 60, paginas: 100), // outra aula
      ];
      expect(AulaService.ritmoDaAula(registros, 'a1'), 30.0);
    });

    test('projeção: páginas restantes ÷ ritmo', () {
      final registros = [sessao(minutos: 60, paginas: 30)];
      // 100 totais - 40 lidas = 60 restantes a 30 pág/h = 120 min.
      expect(
          AulaService.minutosParaTerminar(aula(lidas: 40), registros), 120);
    });

    test('sem sessão com páginas: ritmo e projeção null', () {
      expect(AulaService.ritmoDaAula(const [], 'a1'), isNull);
      expect(AulaService.minutosParaTerminar(aula(), const []), isNull);
    });
  });

  group('minutosPorTipo', () {
    test('separa teoria de prática', () {
      final registros = [
        sessao(minutos: 90),
        sessao(minutos: 45, tipo: TipoEstudo.pratica, questoes: 10),
        sessao(minutos: 30),
      ];
      expect(StatsService.minutosPorTipo(registros),
          (teoria: 120, pratica: 45));
    });
  });

  group('migração de registros antigos (sem tipo gravado)', () {
    test('só questões, sem páginas: vira prática', () {
      final r = RegistroHora.fromJson({
        'id': 'x',
        'data': '2026-07-09T10:00:00',
        'materiaId': 'm1',
        'minutos': 60,
        'questoes': 10,
        'acertos': 8,
      });
      expect(r.tipo, TipoEstudo.pratica);
    });

    test('com páginas: vira teoria mesmo tendo questões', () {
      final r = RegistroHora.fromJson({
        'id': 'x',
        'data': '2026-07-09T10:00:00',
        'materiaId': 'm1',
        'minutos': 60,
        'questoes': 10,
        'paginaInicial': 1,
        'paginaFinal': 20,
      });
      expect(r.tipo, TipoEstudo.teoria);
    });

    test('tipo gravado roundtrip com aulaId', () {
      final original = sessao(tipo: TipoEstudo.pratica, questoes: 5);
      final r = RegistroHora.fromJson(original.toJson());
      expect(r.tipo, TipoEstudo.pratica);
      expect(r.aulaId, 'a1');
    });

    test('Aula roundtrip JSON', () {
      final a = Aula(
        id: 'a1',
        materiaId: 'm1',
        nome: 'Aula 01',
        paginasTotais: 150,
        paginasLidas: 45,
        concluida: false,
      );
      final volta = Aula.fromJson(a.toJson());
      expect(volta.paginasTotais, 150);
      expect(volta.paginasLidas, 45);
      expect(volta.progresso, 0.3);
      expect(volta.paginasRestantes, 105);
    });
  });
}
