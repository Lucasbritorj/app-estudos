import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/simulado.dart';
import 'package:app_estudos/domain/gamificacao_service.dart';
import 'package:app_estudos/domain/revisao_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressões da auditoria 2026-07-24. Um grupo por achado corrigido: cada
/// teste falha se a brecha reabrir.
void main() {
  group('M-03 — conclusão antecipada não consolida como intervalo pleno', () {
    test('revisar 60d no dia seguinte cresce muito menos que revisar em dia', () {
      final emDia = RevisaoService.proximoPassoFsrs(
        estabilidade: 60,
        dificuldade: 5,
        intervaloAtual: 60,
        diasDeAtraso: 0,
        taxaAcerto: 0.9,
      )!;
      final antecipada = RevisaoService.proximoPassoFsrs(
        estabilidade: 60,
        dificuldade: 5,
        intervaloAtual: 60,
        diasDeAtraso: -59, // concluída 59 dias antes do vencimento
        taxaAcerto: 0.9,
      )!;
      expect(antecipada.estabilidade, lessThan(emDia.estabilidade));
      // Antecipar quase tudo deve consolidar quase nada: < 5% de ganho.
      expect(antecipada.estabilidade, lessThan(60 * 1.05));
      expect(emDia.estabilidade, greaterThan(60 * 1.3));
    });

    test('atraso continua com o bônus de esquecimento (nada regrediu)', () {
      final emDia = RevisaoService.proximoPassoFsrs(
        estabilidade: 10,
        dificuldade: 5,
        intervaloAtual: 10,
        diasDeAtraso: 0,
        taxaAcerto: 0.9,
      )!;
      final atrasada = RevisaoService.proximoPassoFsrs(
        estabilidade: 10,
        dificuldade: 5,
        intervaloAtual: 10,
        diasDeAtraso: 20,
        taxaAcerto: 0.9,
      )!;
      expect(atrasada.estabilidade, greaterThan(emDia.estabilidade));
    });

    test('lapso (<75%) ignora antecipação: reforço curto continua curto', () {
      final passo = RevisaoService.proximoPassoFsrs(
        estabilidade: 30,
        dificuldade: 5,
        intervaloAtual: 30,
        diasDeAtraso: -29,
        taxaAcerto: 0.4,
      )!;
      expect(passo.reforco, isTrue);
      expect(passo.estabilidade, closeTo(12.0, 0.001)); // 30 * 0.4
    });
  });

  group('M-11 — reancoragem por estudo só empurra', () {
    Revisao rev(DateTime agendada) => Revisao(
      id: 'r1',
      materiaId: 'm1',
      topicoId: 't1',
      titulo: 'Tópico (7d)',
      dataAgendada: agendada,
      intervaloDias: 7,
    );

    test('sessão retroativa não puxa a revisão para o passado', () {
      final revisoes = [rev(DateTime(2026, 7, 20))];
      // Registro de uma sessão de 2 semanas atrás: 1/7 + 7d = 8/7, ANTES da
      // data atual (20/7). Antes isso nascia "atrasada" sem culpa do usuário.
      final alteradas = RevisaoService.reagendarPorEstudo(
        revisoes,
        't1',
        DateTime(2026, 7, 1),
      );
      expect(alteradas, isEmpty);
    });

    test('sessão de hoje continua empurrando para frente', () {
      final revisoes = [rev(DateTime(2026, 7, 20))];
      final alteradas = RevisaoService.reagendarPorEstudo(
        revisoes,
        't1',
        DateTime(2026, 7, 24),
      );
      expect(alteradas, hasLength(1));
      expect(alteradas.first.dataAgendada, DateTime(2026, 7, 31));
    });
  });

  group('M-02 — bônus de revisão tem teto diário', () {
    Revisao feitaEm(String id, DateTime? conclusao) => Revisao(
      id: id,
      materiaId: 'm1',
      titulo: 'r',
      dataAgendada: DateTime(2026, 7, 24),
      intervaloDias: 0,
      feita: true,
      dataConclusao: conclusao,
    );

    test('20 revisões concluídas no mesmo dia valem no máximo 3', () {
      final revisoes = [
        for (var i = 0; i < 20; i++) feitaEm('r$i', DateTime(2026, 7, 24, 10)),
      ];
      expect(
        GamificacaoService.bonusRevisoes(revisoes),
        GamificacaoService.maxRevisoesComBonusPorDia *
            GamificacaoService.xpPorRevisaoFeita,
      );
    });

    test('ritmo real (3/dia em dias distintos) não é penalizado', () {
      final revisoes = [
        for (var d = 1; d <= 4; d++)
          for (var i = 0; i < 3; i++) feitaEm('r$d-$i', DateTime(2026, 7, d)),
      ];
      expect(
        GamificacaoService.bonusRevisoes(revisoes),
        12 * GamificacaoService.xpPorRevisaoFeita,
      );
    });

    test('revisão antiga sem dataConclusao não perde XP já conquistado', () {
      final revisoes = [for (var i = 0; i < 10; i++) feitaEm('r$i', null)];
      expect(
        GamificacaoService.bonusRevisoes(revisoes),
        10 * GamificacaoService.xpPorRevisaoFeita,
      );
    });

    test('revisão pendente não gera bônus', () {
      final pendente = Revisao(
        id: 'p',
        materiaId: 'm1',
        titulo: 'r',
        dataAgendada: DateTime(2026, 7, 24),
        intervaloDias: 0,
      );
      expect(GamificacaoService.bonusRevisoes([pendente]), 0);
    });
  });

  group('M-05 — invariantes de ResultadoMateria', () {
    test('acertos acima de questões são clampados (taxa nunca passa de 100%)', () {
      final r = ResultadoMateria(materiaId: 'm1', questoes: 10, acertos: 30);
      expect(r.acertos, 10);
      expect(r.taxa, 1.0);
      expect(r.erros, 0);
    });

    test('valores negativos viram zero', () {
      final r = ResultadoMateria(materiaId: 'm1', questoes: -5, acertos: -2);
      expect(r.questoes, 0);
      expect(r.acertos, 0);
      expect(r.taxa, isNull);
    });

    test('backup hostil não corrompe o modelo pelo fromJson', () {
      final r = ResultadoMateria.fromJson({
        'materiaId': 'm1',
        'questoes': 10,
        'acertos': 999,
      });
      expect(r.acertos, 10);
    });
  });

  group('M-09 — teto de minutos por sessão', () {
    test('registro absurdo é clampado em 16h', () {
      final r = RegistroHora(
        id: 'r1',
        data: DateTime(2026, 7, 24),
        materiaId: 'm1',
        minutos: 999999,
      );
      expect(r.minutos, RegistroHora.maxMinutosPorSessao);
    });

    test('sessão longa porém plausível passa intacta', () {
      final r = RegistroHora(
        id: 'r1',
        data: DateTime(2026, 7, 24),
        materiaId: 'm1',
        minutos: 600,
      );
      expect(r.minutos, 600);
    });
  });
}
