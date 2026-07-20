import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/gamificacao_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora reg(DateTime data, int minutos) => RegistroHora(
      id: '${data.toIso8601String()}-$minutos',
      data: data,
      materiaId: 'm1',
      minutos: minutos,
    );

void main() {
  final hoje = DateTime(2026, 7, 9);

  group('progressoNivel', () {
    test('0 XP = nível 1, faltam 600 para o 2', () {
      final p = GamificacaoService.progressoNivel(0);
      expect(p.nivel, 1);
      expect(p.xpNoNivel, 0);
      expect(p.xpParaProximo, 600);
    });

    test('599 XP ainda é nível 1', () {
      expect(GamificacaoService.nivelPara(599), 1);
    });

    test('600 XP sobe para nível 2; próximo degrau custa 1200', () {
      final p = GamificacaoService.progressoNivel(600);
      expect(p.nivel, 2);
      expect(p.xpNoNivel, 0);
      expect(p.xpParaProximo, 1200);
    });

    test('1800 XP = nível 3 (600 + 1200)', () {
      expect(GamificacaoService.nivelPara(1800), 3);
    });
  });

  group('xpDetalhado', () {
    test('base + 50 por revisão feita + 10 por dia de streak', () {
      final registros = [reg(hoje, 100), reg(DateTime(2026, 7, 8, 8), 50)];
      final revisoes = [
        Revisao(
          id: 'r1',
          materiaId: 'm1',
          titulo: 'x',
          dataAgendada: DateTime(2026, 7, 1),
          intervaloDias: 7,
          feita: true,
        ),
        Revisao(
          id: 'r2',
          materiaId: 'm1',
          titulo: 'y',
          dataAgendada: DateTime(2026, 7, 20),
          intervaloDias: 15,
        ),
      ];
      final xp = GamificacaoService.xpDetalhado(registros, revisoes, hoje);
      expect(xp.base, 150);
      expect(xp.bonusRevisoes, 50); // só a feita
      expect(xp.bonusStreak, 20); // streak de 2 dias
      expect(xp.total, 220);
    });

    test('sem dados, tudo zero', () {
      final xp = GamificacaoService.xpDetalhado([], [], hoje);
      expect(xp.total, 0);
    });

    test('peso da matéria multiplica o XP base (teto ×1.5)', () {
      final registros = [reg(hoje, 100)];
      expect(GamificacaoService.xpPonderado(registros, {'m1': 1}), 100);
      expect(GamificacaoService.xpPonderado(registros, {'m1': 3}), 120);
      expect(GamificacaoService.xpPonderado(registros, {'m1': 10}), 150);
      // Matéria fora do mapa degrada para 1 XP/min.
      expect(GamificacaoService.xpPonderado(registros, {'outra': 5}), 100);
    });

    test('bônus de streak usa o PICO histórico (monótono, não o atual)', () {
      // Run de 4 dias (4-7/7), buraco 8/7, voltou hoje (9/7, run de 1). O
      // bônus reflete o recorde (4 dias = 40 XP), não o streak atual (1).
      final registros = [
        reg(hoje, 60), // 9/7; 8/7 = buraco
        for (var d = 4; d <= 7; d++) reg(DateTime(2026, 7, d), 30),
      ];
      final xp = GamificacaoService.xpDetalhado(registros, [], hoje);
      expect(xp.bonusStreak, 40);
    });

    test('XP total é monótono: perder o streak não derruba o XP', () {
      // Base: 5 dias seguidos. Depois: mesmos 5 dias + um estudo isolado
      // muito depois (streak atual = 1, mas o pico segue 5).
      final base = [for (var d = 1; d <= 5; d++) reg(DateTime(2026, 7, d), 30)];
      final comQuebra = [...base, reg(DateTime(2026, 8, 1), 30)];
      final xpBase = GamificacaoService.xpDetalhado(base, [], hoje);
      final xpDepois =
          GamificacaoService.xpDetalhado(comQuebra, [], DateTime(2026, 8, 1));
      // O pico (5) segue valendo; base cresce; total nunca cai.
      expect(xpDepois.bonusStreak, xpBase.bonusStreak); // pico intacto
      expect(xpDepois.total, greaterThanOrEqualTo(xpBase.total));
    });
  });

  group('badges', () {
    Map<String, bool> conquistadas(
            List<RegistroHora> registros, List<Revisao> revisoes) =>
        {
          for (final b in GamificacaoService.badges(registros, revisoes, hoje))
            b.id: b.conquistada,
        };

    test('sem dados, nada conquistado', () {
      final b = conquistadas([], []);
      expect(b.values.any((v) => v), false);
    });

    test('primeira sessão e 50 horas', () {
      final b = conquistadas([reg(hoje, 50 * 60)], []);
      expect(b['primeira-sessao'], true);
      expect(b['horas-50'], true);
      expect(b['horas-100'], false);
    });

    test('streak de 7 dias', () {
      final registros = [
        for (var i = 0; i < 7; i++)
          reg(DateTime(2026, 7, 9 - i, 8), 30),
      ];
      final b = conquistadas(registros, []);
      expect(b['streak-7'], true);
      expect(b['streak-30'], false);
    });

    test('badge de streak NÃO é revogada ao quebrar o streak (pico)', () {
      // 7 dias seguidos em janeiro; hoje (julho) o streak atual é 0, mas a
      // badge "Semana cheia" persiste porque deriva do recorde.
      final registros = [
        for (var d = 1; d <= 7; d++) reg(DateTime(2026, 1, d, 8), 30),
      ];
      expect(conquistadas(registros, [])['streak-7'], true);
    });

    test('revisões: primeira feita e em dia', () {
      final feita = Revisao(
        id: 'r1',
        materiaId: 'm1',
        titulo: 'x',
        dataAgendada: DateTime(2026, 7, 1),
        intervaloDias: 7,
        feita: true,
      );
      final futura = Revisao(
        id: 'r2',
        materiaId: 'm1',
        titulo: 'y',
        dataAgendada: DateTime(2026, 7, 20),
        intervaloDias: 15,
      );
      final atrasada = Revisao(
        id: 'r3',
        materiaId: 'm1',
        titulo: 'z',
        dataAgendada: DateTime(2026, 7, 1),
        intervaloDias: 7,
      );

      final emDia = conquistadas([], [feita, futura]);
      expect(emDia['primeira-revisao'], true);
      expect(emDia['revisoes-em-dia'], true);

      final comAtraso = conquistadas([], [feita, atrasada]);
      expect(comAtraso['revisoes-em-dia'], false);
    });
  });
}
