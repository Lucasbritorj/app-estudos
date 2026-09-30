import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/plano_diario_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hoje = DateTime(2026, 9, 7);
  Materia m(String id, String a, {int? alvo}) => Materia(
    id: id,
    nome: id,
    ambienteId: a,
    corSlot: 0,
    criadaEm: hoje,
    minutosAlvo: alvo,
  );
  Ambiente a(String id, {DateTime? data}) =>
      Ambiente(id: id, nome: id, criadoEm: hoje, dataProva: data);
  test('capacidade única e divisão 80/20 sem multiplicar agendas', () {
    final p = PlanoDiarioService.gerar(
      hoje: hoje,
      dias: {1: 150},
      principal: 'a',
      secundarios: ['b'],
      ambientes: [a('a'), a('b')],
      materias: [m('x', 'a'), m('y', 'b')],
      revisoes: [],
    );
    expect(p.blocos.length, 10);
    expect(p.blocos.where((b) => b.materiaId == 'x').length, 8);
  });
  test(
    'revisões reservadas primeiro; excesso explícito e dia indisponível',
    () {
      final rs = List.generate(
        3,
        (i) => Revisao(
          id: '$i',
          materiaId: 'x',
          titulo: 'R',
          dataAgendada: hoje,
          intervaloDias: 7,
        ),
      );
      final p = PlanoDiarioService.gerar(
        hoje: hoje,
        dias: {1: 30, 2: 60},
        excecoes: {'2026-09-08': 0},
        principal: 'a',
        ambientes: [a('a')],
        materias: [m('x', 'a')],
        revisoes: rs,
      );
      expect(p.blocos.length, 2);
      expect(p.blocos.every((b) => b.revisaoId != null), true);
      expect(p.avisos.join(), contains('1 revisões sem capacidade'));
    },
  );
  test('prova passada não gera blocos', () {
    final p = PlanoDiarioService.gerar(
      hoje: hoje,
      dias: {1: 60},
      principal: 'a',
      ambientes: [a('a', data: hoje.subtract(const Duration(days: 1)))],
      materias: [m('x', 'a')],
      revisoes: [],
    );
    expect(p.blocos, isEmpty);
    expect(p.avisos.join(), contains('prova passada'));
  });
  test('conteúdo comum satisfaz reservas equivalentes sem duplicar tempo', () {
    final p = PlanoDiarioService.gerar(
      hoje: hoje,
      dias: {1: 60},
      principal: 'a',
      secundarios: ['b'],
      ambientes: [a('a'), a('b')],
      materias: [m('x', 'a', alvo: 15), m('y', 'b', alvo: 15)],
      revisoes: [],
      comuns: {'x': 'y'},
    );
    expect(p.blocos.length, 1);
  });
  test('sem data permanece semanal mesmo com secundário distante', () {
    final p = PlanoDiarioService.gerar(
      hoje: hoje,
      dias: {1: 60},
      principal: 'a',
      secundarios: ['b'],
      ambientes: [
        a('a'),
        a('b', data: hoje.add(const Duration(days: 20))),
      ],
      materias: [m('x', 'a'), m('y', 'b')],
      revisoes: [],
    );
    expect(
      p.blocos
          .where((b) => b.materiaId == 'x')
          .every((b) => b.dia.difference(hoje).inDays < 7),
      true,
    );
  });
  test('import inválido é rejeitado antes de persistir', () {
    expect(() => validarPlanoDiario({'dias': 42}), throwsFormatException);
    expect(
      () => validarPlanoDiario({
        'dias': {'8': 30},
      }),
      throwsFormatException,
    );
    expect(
      () => validarPlanoDiario({
        'excecoes': {'2026-02-31': 30},
      }),
      throwsFormatException,
    );
    expect(
      () => validarPlanoDiario({
        'vinculos': {'inexistente': 'registro'},
      }),
      throwsFormatException,
    );
    expect(
      () => validarPlanoDiario({'percentual': 100}),
      throwsFormatException,
    );
    expect(() => validarPlanoDiario({}), returnsNormally);
  });
  test('secundário recebe capacidade ao longo de dias curtos', () {
    final p = PlanoDiarioService.gerar(
      hoje: hoje,
      dias: {1: 15, 2: 15, 3: 15, 4: 15, 5: 15},
      principal: 'a',
      secundarios: ['b'],
      ambientes: [a('a'), a('b')],
      materias: [m('x', 'a'), m('y', 'b')],
      revisoes: [],
    );
    expect(p.blocos.where((b) => b.materiaId == 'y').length, 1);
  });
}
