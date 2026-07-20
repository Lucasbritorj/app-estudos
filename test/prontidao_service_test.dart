import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/dominio_service.dart';
import 'package:app_estudos/domain/prontidao_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Medição agrupada como os providers fazem (uma passada nos registros).
Map<String, MedicaoDominio?> medir(
        List<Materia> materias, List<RegistroHora> registros) =>
    DominioService.dominioPorMateria(registros, materias.map((m) => m.id));

Materia materia(String id, int peso,
        {int intimidade = 3, bool arquivada = false}) =>
    Materia(
      id: id,
      nome: id,
      corSlot: 0,
      peso: peso,
      intimidade: intimidade,
      arquivada: arquivada,
      criadaEm: DateTime(2026),
    );

RegistroHora sessao(String materiaId, int questoes, int acertos) =>
    RegistroHora(
      id: '$materiaId-$questoes-$acertos',
      data: DateTime(2026, 7, 1),
      materiaId: materiaId,
      minutos: 60,
      questoes: questoes,
      acertos: acertos,
    );

void main() {
  group('prontidao', () {
    test('média ponderada pelo peso do edital', () {
      final valor = ProntidaoService.prontidao(
          [materia('a', 1), materia('b', 3)], {'a': 1.0, 'b': 0.5})!;
      expect(valor, closeTo(0.625, 0.001)); // (1×1 + 3×0.5) / 4
    });

    test('sem matérias ativas: null, nunca valor inventado', () {
      expect(ProntidaoService.prontidao([], {}), isNull);
      expect(
          ProntidaoService.prontidao(
              [materia('x', 5, arquivada: true)], {'x': 0.9}),
          isNull);
    });
  });

  group('prontidaoAjustada (penaliza dispersão)', () {
    test('perfil uniforme: ajustada = média (desvio zero)', () {
      final materias = [materia('a', 1), materia('b', 1)];
      final dom = {'a': 0.7, 'b': 0.7};
      expect(ProntidaoService.prontidaoAjustada(materias, dom),
          closeTo(0.7, 0.001));
    });

    test('mesmo valor médio, perfil bimodal (pesada fraca) fica ABAIXO do '
        'uniforme — o ponto único escondia o risco', () {
      // média 0.7 nos dois; o bimodal tem a matéria peso-3 mais fraca.
      final uniforme = ProntidaoService.prontidaoAjustada(
          [materia('a', 1), materia('b', 1)], {'a': 0.7, 'b': 0.7})!;
      final bimodal = ProntidaoService.prontidaoAjustada(
          [materia('a', 3), materia('b', 1)], {'a': 0.6, 'b': 1.0})!;
      expect(bimodal, lessThan(uniforme));
      // nunca acima da média nem fora de [0,1]
      expect(bimodal, lessThan(0.7));
      expect(bimodal, greaterThan(0.0));
    });

    test('sem matérias ativas: null', () {
      expect(ProntidaoService.prontidaoAjustada([], {}), isNull);
    });
  });

  group('coberturaConfiavel (% do peso com Elo confiável)', () {
    test('fração ponderada pelo peso do edital', () {
      final materias = [materia('medida', 3), materia('palpite', 1)];
      final registros = [sessao('medida', 12, 9), sessao('palpite', 4, 4)];
      // medida (peso 3) confiável, palpite (peso 1) não -> 3/4.
      expect(
          ProntidaoService.coberturaConfiavel(
              materias, medir(materias, registros)),
          closeTo(0.75, 0.001));
    });

    test('sem matérias: 0, nunca divide por zero', () {
      expect(ProntidaoService.coberturaConfiavel([], {}), 0.0);
    });
  });

  group('projetarDominios', () {
    test('sem cronograma ou sem dias: projeção = hoje', () {
      final hoje = {'a': 0.5};
      expect(
          ProntidaoService.projetarDominios(
              materias: [materia('a', 1)],
              dominiosHoje: hoje,
              minutosSemanais: 0,
              diasAteProva: 30),
          {'a': 0.5});
      expect(
          ProntidaoService.projetarDominios(
              materias: [materia('a', 1)],
              dominiosHoje: hoje,
              minutosSemanais: 300,
              diasAteProva: 0),
          {'a': 0.5});
    });

    test('1 semana de 300min rende +0.4 de domínio (0.02 por bloco de 15)',
        () {
      final projetado = ProntidaoService.projetarDominios(
          materias: [materia('a', 1)],
          dominiosHoje: {'a': 0.5},
          minutosSemanais: 300,
          diasAteProva: 7);
      expect(projetado['a'], closeTo(0.9, 0.001));
    });

    test('domínio satura em 1.0', () {
      final projetado = ProntidaoService.projetarDominios(
          materias: [materia('a', 1)],
          dominiosHoje: {'a': 0.5},
          minutosSemanais: 300,
          diasAteProva: 14);
      expect(projetado['a'], 1.0);
    });

    test('semana fracionária recebe minutos proporcionais', () {
      final projetado = ProntidaoService.projetarDominios(
          materias: [materia('a', 1)],
          dominiosHoje: {'a': 0.5},
          minutosSemanais: 700,
          diasAteProva: 1); // 1/7 da semana = 100min = +0.1333
      expect(projetado['a'], closeTo(0.6333, 0.001));
    });

    test('alocação segue a utilidade: fraca ganha, dominada não', () {
      final projetado = ProntidaoService.projetarDominios(
          materias: [materia('fraca', 1), materia('dominada', 1)],
          dominiosHoje: {'fraca': 0.2, 'dominada': 0.8},
          minutosSemanais: 300,
          diasAteProva: 7);
      expect(projetado['fraca'], closeTo(0.6, 0.001));
      expect(projetado['dominada'], closeTo(0.8, 0.001));
    });
  });

  test('materiasEmRisco: abaixo de 75% projetado, piores primeiro', () {
    final risco = ProntidaoService.materiasEmRisco(
        [materia('ok', 1), materia('ruim', 1), materia('pessima', 1)],
        {'ok': 0.8, 'ruim': 0.6, 'pessima': 0.4});
    expect(risco.map((r) => r.materia.id), ['pessima', 'ruim']);
  });

  test('semMedicao: sem 10+ questões = cold start, pede calibração', () {
    final materias = [materia('medida', 1), materia('palpite', 1)];
    final registros = [sessao('medida', 12, 9), sessao('palpite', 4, 4)];
    expect(
        ProntidaoService.semMedicao(materias, medir(materias, registros))
            .map((m) => m.id),
        ['palpite']);
  });

  test('dominiosAtuais: Elo confiável tem precedência sobre intimidade', () {
    final materias = [
      materia('medida', 1, intimidade: 1), // prior seria 0.2
      materia('palpite', 1, intimidade: 5), // prior 0.8
    ];
    final registros = [sessao('medida', 20, 20)];
    final dominios =
        ProntidaoService.dominiosAtuais(materias, medir(materias, registros));
    expect(dominios['medida']!, greaterThan(0.5)); // evidência venceu o prior
    expect(dominios['palpite'], closeTo(0.8, 0.001));
  });

  group('Ambiente.dataProva', () {
    test('roundtrip json preserva; ausente vira null', () {
      final com = Ambiente(
          id: 'a1',
          nome: 'SEFAZ',
          criadoEm: DateTime(2026, 1, 1),
          dataProva: DateTime(2026, 11, 22));
      expect(Ambiente.fromJson(com.toJson()).dataProva,
          DateTime(2026, 11, 22));
      final sem = Ambiente.fromJson(
          {'id': 'a2', 'nome': 'X', 'criadoEm': '2026-01-01T00:00:00.000'});
      expect(sem.dataProva, isNull);
    });

    test('copyWith preserva por padrão e limpa só com limparDataProva', () {
      final ambiente = Ambiente(
          id: 'a1',
          nome: 'SEFAZ',
          criadoEm: DateTime(2026, 1, 1),
          dataProva: DateTime(2026, 11, 22));
      expect(ambiente.copyWith(nome: 'Novo').dataProva,
          DateTime(2026, 11, 22));
      expect(ambiente.copyWith(limparDataProva: true).dataProva, isNull);
    });
  });
}
