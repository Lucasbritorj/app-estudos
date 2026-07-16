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

  group('proximoPasso (adaptativa)', () {
    test('acerto < 75%: reforço em 3 dias SEM avançar a cadeia', () {
      final passo = RevisaoService.proximoPasso(intervalos, 7, 0.6)!;
      expect(passo.dias, 3);
      expect(passo.intervalo, 7); // continua de onde estava
      expect(passo.reforco, true);
    });

    test('75-84%: repete o intervalo atual', () {
      final passo = RevisaoService.proximoPasso(intervalos, 15, 0.80)!;
      expect(passo.dias, 15);
      expect(passo.intervalo, 15);
      expect(passo.reforco, false);
    });

    test('>= 85%: segue a cadeia normal', () {
      final passo = RevisaoService.proximoPasso(intervalos, 7, 0.9)!;
      expect(passo.dias, 15);
      expect(passo.intervalo, 15);
      expect(passo.reforco, false);
    });

    test('sem questões (taxa null): cadeia normal', () {
      final passo = RevisaoService.proximoPasso(intervalos, 7, null)!;
      expect(passo.dias, 15);
      expect(passo.reforco, false);
    });

    test('75-84% em revisão manual (intervalo 0): entra na cadeia', () {
      final passo = RevisaoService.proximoPasso(intervalos, 0, 0.8)!;
      expect(passo.dias, 7);
      expect(passo.intervalo, 7);
    });

    test('fim da cadeia com bom desempenho: null (nada a agendar)', () {
      expect(RevisaoService.proximoPasso(intervalos, 60, 0.95), isNull);
    });

    test('fim da cadeia com desempenho ruim AINDA gera reforço', () {
      final passo = RevisaoService.proximoPasso(intervalos, 60, 0.5)!;
      expect(passo.dias, 3);
      expect(passo.reforco, true);
    });
  });

  group('proximoPassoFsrs', () {
    test('em dia com bom desempenho ~dobra o intervalo (7 vira 15)', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.9)!;
      // R(7, S=7) = 0.9; crescimento = 0.9 * 1.0 * 1.2 -> S' = 14.56
      expect(passo.dias, 15);
      expect(passo.reforco, false);
      expect(passo.estabilidade, closeTo(14.56, 0.01));
      expect(passo.dificuldade, closeTo(4.7, 0.001));
    });

    test('errou (<75%): estabilidade despenca, reforço curto', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.6)!;
      expect(passo.dias, 3); // 7 * 0.4 = 2.8
      expect(passo.reforco, true);
      expect(passo.dificuldade, closeTo(6.0, 0.001));
    });

    test('difícil (75-84%): cresce na metade do ritmo', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.8)!;
      expect(passo.dias, 11); // 7 * 1.54 = 10.78
      expect(passo.reforco, false);
      expect(passo.dificuldade, closeTo(5.5, 0.001));
    });

    test('sem questões (taxa null): cresce pleno como a cadeia clássica', () {
      final passo = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: null)!;
      expect(passo.dias, 15);
      expect(passo.reforco, false);
    });

    test('revisada atrasada com sucesso consolida mais (espaçamento)', () {
      final emDia = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, taxaAcerto: 0.9)!;
      final atrasada = RevisaoService.proximoPassoFsrs(
          intervaloAtual: 7, diasDeAtraso: 7, taxaAcerto: 0.9)!;
      expect(atrasada.dias, greaterThan(emDia.dias));
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
