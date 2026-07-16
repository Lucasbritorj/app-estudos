import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/repositories/ambiente_filtros.dart';
import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Camada de agregados derivados (item 2): correção da derivação e, sobretudo,
/// a memoização — ler o mesmo provider duas vezes devolve a MESMA instância
/// enquanto as listas de origem não mudam (era esse recálculo por build que a
/// auditoria apontou).
void main() {
  final hoje = DateTime(2026, 7, 16); // quinta-feira

  Materia mat(String id, {int peso = 1, int intimidade = 3}) => Materia(
      id: id,
      nome: id.toUpperCase(),
      corSlot: 0,
      peso: peso,
      intimidade: intimidade,
      criadaEm: DateTime(2026, 1, 1));

  RegistroHora reg(String id, String materiaId,
          {int minutos = 60, int? questoes, int? acertos, DateTime? data}) =>
      RegistroHora(
          id: id,
          data: data ?? hoje,
          materiaId: materiaId,
          minutos: minutos,
          questoes: questoes,
          acertos: acertos);

  ProviderContainer container({
    required List<RegistroHora> registros,
    required List<Materia> materias,
  }) =>
      ProviderContainer(overrides: [
        registrosDoAmbienteProvider.overrideWithValue(registros),
        materiasDoAmbienteProvider.overrideWithValue(materias),
        revisoesDoAmbienteProvider.overrideWithValue(const <Revisao>[]),
        hojeProvider.overrideWithValue(hoje),
      ]);

  test('desempenhoPorMateriaProvider soma questões/acertos por matéria', () {
    final c = container(registros: [
      reg('r1', 'm1', questoes: 10, acertos: 8),
      reg('r2', 'm1', questoes: 10, acertos: 6),
      reg('r3', 'm2', questoes: 5, acertos: 5),
    ], materias: [
      mat('m1'),
      mat('m2')
    ]);
    addTearDown(c.dispose);
    final d = c.read(desempenhoPorMateriaProvider);
    expect(d['m1'], (questoes: 20, acertos: 14));
    expect(d['m2'], (questoes: 5, acertos: 5));
  });

  test('memoiza: leituras repetidas devolvem a mesma instância', () {
    final c = container(
        registros: [reg('r1', 'm1', questoes: 10, acertos: 8)],
        materias: [mat('m1')]);
    addTearDown(c.dispose);
    expect(identical(c.read(desempenhoPorMateriaProvider),
        c.read(desempenhoPorMateriaProvider)), isTrue);
    expect(identical(c.read(rankingsProvider), c.read(rankingsProvider)),
        isTrue);
    expect(identical(c.read(donutProvider), c.read(donutProvider)), isTrue);
  });

  test('rankingsProvider: maior taxa primeiro; amostra < 10 questões fica fora',
      () {
    final c = container(registros: [
      reg('r1', 'm1', minutos: 120, questoes: 10, acertos: 9), // 90%
      reg('r2', 'm2', questoes: 10, acertos: 5), // 50%
      reg('r3', 'm3', questoes: 4, acertos: 4), // amostra insuficiente
    ], materias: [
      mat('m1'),
      mat('m2'),
      mat('m3')
    ]);
    addTearDown(c.dispose);
    final rk = c.read(rankingsProvider);
    expect(rk.ranking.map((e) => e.materiaId).toList(), ['m1', 'm2']);
    expect(rk.maisEstudada?.materiaId, 'm1');
  });

  test('insightsProvider nunca vem vazio e aponta o pior desempenho', () {
    final c = container(
        registros: [reg('r1', 'm1', questoes: 10, acertos: 4)], // 40%
        materias: [mat('m1')]);
    addTearDown(c.dispose);
    final ins = c.read(insightsProvider);
    expect(ins, isNotEmpty);
    expect(ins.any((a) => a.materiaId == 'm1'), isTrue);
  });

  test('barrasSemanaProvider agrega a semana e ordena maior primeiro', () {
    final c = container(registros: [
      reg('r1', 'm1', minutos: 30, data: hoje),
      reg('r2', 'm2', minutos: 90, data: hoje),
    ], materias: [
      mat('m1'),
      mat('m2')
    ]);
    addTearDown(c.dispose);
    final barras = c.read(barrasSemanaProvider);
    expect(barras.map((e) => e.materiaId).toList(), ['m2', 'm1']);
    expect(barras.first.minutos, 90);
  });
}
