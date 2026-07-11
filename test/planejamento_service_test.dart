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
