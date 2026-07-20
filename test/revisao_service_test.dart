import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/revisao_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora regComQuestoes(String materia, String? topico, int questoes,
        int acertos) =>
    RegistroHora(
      id: '$materia-$topico-$questoes-$acertos',
      data: DateTime(2026, 7, 9),
      materiaId: materia,
      topicoId: topico,
      minutos: 60,
      questoes: questoes,
      acertos: acertos,
    );

void main() {
  const intervalos = [7, 15, 30, 60];

  test('cadeia avança para o próximo intervalo maior', () {
    expect(RevisaoService.proximoIntervalo(intervalos, 7), 15);
    expect(RevisaoService.proximoIntervalo(intervalos, 15), 30);
    expect(RevisaoService.proximoIntervalo(intervalos, 30), 60);
  });

  test('fim da cadeia retorna null', () {
    expect(RevisaoService.proximoIntervalo(intervalos, 60), isNull);
    expect(RevisaoService.proximoIntervalo(intervalos, 90), isNull);
  });

  test('revisão manual (intervalo 0) entra no início da cadeia', () {
    expect(RevisaoService.proximoIntervalo(intervalos, 0), 7);
  });

  test('lista desordenada é tratada', () {
    expect(RevisaoService.proximoIntervalo(const [30, 7, 15], 7), 15);
  });

  group('taxaAcertoDe', () {
    final registros = [
      regComQuestoes('m1', 't1', 10, 6), // 60% no tópico t1
      regComQuestoes('m1', 't2', 10, 9), // 90% no tópico t2
      regComQuestoes('m1', null, 10, 10), // conta só na matéria
    ];

    test('com tópico usa só registros do tópico', () {
      expect(
          RevisaoService.taxaAcertoDe(registros,
              materiaId: 'm1', topicoId: 't1'),
          0.6);
    });

    test('sem tópico agrega a matéria inteira', () {
      expect(RevisaoService.taxaAcertoDe(registros, materiaId: 'm1'),
          25 / 30);
    });

    test('sem questões registradas: null, nunca valor inventado', () {
      expect(
          RevisaoService.taxaAcertoDe(registros,
              materiaId: 'm1', topicoId: 'sem-questoes'),
          isNull);
    });

    test('janela de recência: sessão antiga sai do cálculo do passo', () {
      // 1 sessão péssima antiga + 10 recentes perfeitas: com a janela de 10
      // sessões a antiga não segura mais o intervalo (taxa acumulada
      // seguraria para sempre).
      final historico = [
        RegistroHora(
          id: 'antiga',
          data: DateTime(2026, 1, 1),
          materiaId: 'm1',
          topicoId: 't1',
          minutos: 60,
          questoes: 10,
          acertos: 0,
        ),
        for (var i = 0; i < 10; i++)
          RegistroHora(
            id: 'recente-$i',
            data: DateTime(2026, 7, 1 + i),
            materiaId: 'm1',
            topicoId: 't1',
            minutos: 60,
            questoes: 10,
            acertos: 10,
          ),
      ];
      expect(
          RevisaoService.taxaAcertoDe(historico,
              materiaId: 'm1', topicoId: 't1'),
          1.0);
      // Janela maior que o histórico volta a incluir a antiga.
      expect(
          RevisaoService.taxaAcertoDe(historico,
              materiaId: 'm1', topicoId: 't1', ultimasSessoes: 11),
          100 / 110);
    });
  });

  group('proximoPassoFsrs', () {
    // Valores recalculados após o freio de estabilidade S^(-0.15) e a
    // reversão à média da dificuldade (0.1): a progressão fica sub-geométrica
    // (7→13 em vez de 7→15) — de propósito, o modelo antigo super-espaçava.
    test('em dia com bom desempenho cresce sub-geométrico (7 vira 13)', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.9)!;
      // cresc = 0.9*1.0*1.2*7^-0.15 = 0.8066 -> S' = 7*1.8066 = 12.65
      expect(passo.dias, 13);
      expect(passo.reforco, false);
      expect(passo.estabilidade, closeTo(12.646, 0.01));
      // 4.7 puxado à média: 4.7 + 0.1*(5-4.7) = 4.73
      expect(passo.dificuldade, closeTo(4.73, 0.001));
    });

    test('errou (<75%): estabilidade despenca, reforço curto', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.6)!;
      expect(passo.dias, 3); // 7 * 0.4 = 2.8
      expect(passo.reforco, true);
      // 6.0 puxado à média: 6.0 + 0.1*(5-6) = 5.9
      expect(passo.dificuldade, closeTo(5.9, 0.001));
    });

    test('difícil (75-84%): cresce na metade do ritmo', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.8)!;
      expect(passo.dias, 10); // 7 * (1 + 0.4033) = 9.82
      expect(passo.reforco, false);
      // 5.5 puxado à média: 5.5 + 0.1*(5-5.5) = 5.45
      expect(passo.dificuldade, closeTo(5.45, 0.001));
    });

    test('sem questões (taxa null): cresce pleno como a cadeia clássica', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: null)!;
      expect(passo.dias, 13);
      expect(passo.reforco, false);
    });

    test('revisada atrasada com sucesso consolida mais (espaçamento)', () {
      // O efeito de espaçamento vive na ESTABILIDADE (o arredondamento em
      // dias pode empatar após o freio); a estabilidade da atrasada é maior.
      final emDia = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.9)!;
      final atrasada = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, diasDeAtraso: 7, taxaAcerto: 0.9)!;
      expect(atrasada.estabilidade, greaterThan(emDia.estabilidade));
    });

    test('retenção-alvo menor alonga o intervalo (menos revisões)', () {
      final alvo90 = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.9, retencaoAlvo: 0.9)!;
      final alvo80 = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.9, retencaoAlvo: 0.8)!;
      expect(alvo80.dias, greaterThan(alvo90.dias));
      // mesma estabilidade; só o intervalo agendado muda com a retenção-alvo.
      expect(alvo80.estabilidade, closeTo(alvo90.estabilidade, 0.001));
    });

    test('estado gravado tem precedência sobre a semente do intervalo', () {
      final passo = RevisaoService.proximoPassoFsrs(
          estabilidade: 30,
          dificuldade: 5,
          intervaloAtual: 7,
          taxaAcerto: 0.9)!;
      expect(passo.dias, greaterThan(30)); // cresceu da estabilidade 30
    });

    test('dificuldade acumulada trava o crescimento', () {
      final duro = RevisaoService.proximoPassoFsrs(
          estabilidade: 7,
          dificuldade: 10,
          intervaloAtual: 7,
          taxaAcerto: 0.9)!;
      expect(duro.dias, lessThan(15)); // fator (11-10)/6 encolhe o ganho
    });

    test('revisão manual (intervalo 0) usa semente curta', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 0, taxaAcerto: null)!;
      expect(passo.dias, 6); // semente 3d * 2.08
      expect(passo.reforco, false);
    });

    test('intervalo além do teto encerra a cadeia (null)', () {
      expect(
          RevisaoService.proximoPassoFsrs(
              estabilidade: 100, intervaloAtual: 100, taxaAcerto: 0.95),
          isNull);
    });

    test('errou nunca encerra a cadeia, mesmo com estabilidade alta', () {
      final passo = RevisaoService.proximoPassoFsrs(
          estabilidade: 100, intervaloAtual: 100, taxaAcerto: 0.5)!;
      expect(passo.reforco, true);
      expect(passo.dias, 40); // 100 * 0.4
    });
  });
}
