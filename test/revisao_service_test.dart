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
}
