import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/domain/planejamento_service.dart';
import 'package:flutter_test/flutter_test.dart';

Materia materia(String id, int peso, {bool arquivada = false}) => Materia(
      id: id,
      nome: id,
      corSlot: 0,
      peso: peso,
      arquivada: arquivada,
      criadaEm: DateTime(2026),
    );

void main() {
  test('distribui proporcional ao peso', () {
    final resultado = PlanejamentoService.distribuirPorPeso(
        600, [materia('afo', 2), materia('sql', 1)]);
    expect(resultado['afo'], 400);
    expect(resultado['sql'], 200);
  });

  test('maior resto: soma distribuída bate exata com o total', () {
    final resultado = PlanejamentoService.distribuirPorPeso(
        100, [materia('a', 1), materia('b', 1), materia('c', 1)]);
    expect(resultado.values.fold(0, (x, y) => x + y), 100);
    expect(resultado.values.every((v) => v == 33 || v == 34), true);
  });

  test('matéria arquivada fica fora da distribuição', () {
    final resultado = PlanejamentoService.distribuirPorPeso(
        300, [materia('a', 1), materia('b', 1, arquivada: true)]);
    expect(resultado, {'a': 300});
  });

  test('sem minutos ou sem matérias retorna vazio', () {
    expect(PlanejamentoService.distribuirPorPeso(0, [materia('a', 1)]), {});
    expect(PlanejamentoService.distribuirPorPeso(100, []), {});
  });

  group('dominioInicial', () {
    test('medição confiável tem precedência sobre a intimidade', () {
      expect(
          PlanejamentoService.dominioInicial(
              5, (dominio: 0.3, questoes: 20, confiavel: true)),
          0.3);
    });

    test('medição com pouca amostra cai no prior de intimidade', () {
      expect(
          PlanejamentoService.dominioInicial(
              5, (dominio: 0.3, questoes: 4, confiavel: false)),
          closeTo(0.8, 0.001));
    });

    test('prior linear: intimidade 1=0.2, 3=0.5, 5=0.8', () {
      expect(PlanejamentoService.dominioInicial(1, null), closeTo(0.2, 0.001));
      expect(PlanejamentoService.dominioInicial(3, null), closeTo(0.5, 0.001));
      expect(PlanejamentoService.dominioInicial(5, null), closeTo(0.8, 0.001));
    });
  });

  group('distribuirPorUtilidade', () {
    test('soma distribuída bate exata, inclusive com resto de bloco', () {
      final resultado = PlanejamentoService.distribuirPorUtilidade(
          50, [materia('a', 1), materia('b', 1)], {'a': 0.5, 'b': 0.5});
      expect(resultado.values.fold(0, (x, y) => x + y), 50);
    });

    test('déficit de domínio grande leva tudo enquanto a utilidade domina',
        () {
      final resultado = PlanejamentoService.distribuirPorUtilidade(
          120,
          [materia('fraca', 1), materia('dominada', 1)],
          {'fraca': 0.2, 'dominada': 0.8});
      expect(resultado['fraca'], 120);
      expect(resultado['dominada'], 0);
    });

    test('domínios iguais: retorno decrescente intercala meio a meio', () {
      final resultado = PlanejamentoService.distribuirPorUtilidade(
          120, [materia('a', 1), materia('b', 1)], {'a': 0.5, 'b': 0.5});
      expect(resultado['a'], 60);
      expect(resultado['b'], 60);
    });

    test('peso do edital multiplica a utilidade', () {
      final resultado = PlanejamentoService.distribuirPorUtilidade(
          60,
          [materia('pesada', 5), materia('leve', 1)],
          {'pesada': 0.5, 'leve': 0.5});
      expect(resultado['pesada'], 60);
      expect(resultado['leve'], 0);
    });

    test('matéria sem domínio informado assume neutro 0.5', () {
      final resultado = PlanejamentoService.distribuirPorUtilidade(
          30, [materia('a', 1), materia('b', 1)], {'a': 0.9});
      expect(resultado['b'], 30); // 0.5 efetivo perde só para déficit maior
    });

    test('piso de manutenção: matéria totalmente dominada ganha fatia mínima '
        'em vez de zero (spaced repetition)', () {
      // 'zzz' (dom 1.0, déficit 0) perde os desempates para 'aaa' pelo nome.
      // Sem piso 'zzz' fica com 0 (aaa, ainda com déficit, soca tudo). Com o
      // piso, quando aaa passa de 0.92 (déficit < piso), zzz entra na fila.
      final materias = [materia('aaa', 1), materia('zzz', 1)];
      final semPiso = PlanejamentoService.distribuirPorUtilidade(
          75, materias, {'aaa': 0.86, 'zzz': 1.0});
      final comPiso = PlanejamentoService.distribuirPorUtilidade(
          75, materias, {'aaa': 0.86, 'zzz': 1.0}, pisoManutencao: 0.08);
      expect(semPiso['zzz'], 0);
      expect(comPiso['zzz'], greaterThan(0));
      // A soma continua exata com o total nos dois casos.
      expect(comPiso.values.fold(0, (x, y) => x + y), 75);
    });

    test('piso pequeno NÃO afeta matéria a 0.8 (déficit 0.2 > piso)', () {
      // Garante que o piso 0.08 não muda a alocação clássica (dominada 0.8).
      final resultado = PlanejamentoService.distribuirPorUtilidade(
          120, [materia('fraca', 1), materia('dominada', 1)],
          {'fraca': 0.2, 'dominada': 0.8},
          pisoManutencao: 0.08);
      expect(resultado['fraca'], 120);
      expect(resultado['dominada'], 0);
    });

    test('arquivada fora; sem minutos ou sem matérias retorna vazio', () {
      expect(
          PlanejamentoService.distribuirPorUtilidade(
              60,
              [materia('a', 1), materia('x', 9, arquivada: true)],
              {'a': 0.5, 'x': 0.0}),
          {'a': 60});
      expect(
          PlanejamentoService.distribuirPorUtilidade(0, [materia('a', 1)], {}),
          {});
      expect(PlanejamentoService.distribuirPorUtilidade(100, [], {}), {});
    });
  });

  test('totalPlanejado soma os dias', () {
    expect(PlanejamentoService.totalPlanejado({1: 120, 3: 60}), 180);
    expect(PlanejamentoService.totalPlanejado({}), 0);
  });

  group('planejadoEntre', () {
    // Cronograma: 60min às segundas (1), 30min aos sábados (6).
    const plano = {1: 60, 6: 30};

    test('uma semana cheia = total do cronograma', () {
      // 06/07/2026 (segunda) a 12/07/2026 (domingo).
      expect(
          PlanejamentoService.planejadoEntre(
              plano, DateTime(2026, 7, 6), DateTime(2026, 7, 12)),
          90);
    });

    test('mês de julho/2026: 4 segundas e 4 sábados', () {
      expect(
          PlanejamentoService.planejadoEntre(
              plano, DateTime(2026, 7, 1), DateTime(2026, 7, 31)),
          4 * 60 + 4 * 30);
    });

    test('período parcial conta só os dias dentro do intervalo', () {
      // Quinta 09/07 a sábado 11/07: só o sábado entra.
      expect(
          PlanejamentoService.planejadoEntre(
              plano, DateTime(2026, 7, 9), DateTime(2026, 7, 11)),
          30);
    });

    test('intervalo invertido ou plano vazio = 0', () {
      expect(
          PlanejamentoService.planejadoEntre(
              plano, DateTime(2026, 7, 10), DateTime(2026, 7, 9)),
          0);
      expect(
          PlanejamentoService.planejadoEntre(
              {}, DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
          0);
    });

    test('ano inteiro de 2026 bate com contagem manual de segundas', () {
      // 2026 tem 52 segundas e 52 sábados.
      expect(
          PlanejamentoService.planejadoEntre(
              {1: 60}, DateTime(2026, 1, 1), DateTime(2026, 12, 31)),
          52 * 60);
    });
  });
}
