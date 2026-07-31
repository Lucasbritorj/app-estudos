import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/data/repositories/ambiente_filtros.dart';
import 'package:app_estudos/domain/caderno_erros_service.dart';
import 'package:app_estudos/features/caderno/caderno_providers.dart';
import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cobre o domínio puro (CadernoErrosService + QuestaoErrada) e os
/// providers de agregação do caderno (caderno_providers.dart). Sem Hive:
/// tanto o serviço quanto os providers operam sobre listas em memória —
/// os providers testados aqui via override direto de
/// `questoesErradasDoAmbienteProvider`/`materiasDoAmbienteProvider`, mesmo
/// padrão de dashboard_providers_test.dart.
void main() {
  final hoje = DateTime(2026, 7, 30);

  QuestaoErrada questao({
    String id = 'q1',
    String materiaId = 'm1',
    String? topicoId,
    String enunciado = 'Enunciado de teste',
    String? respostaMarcada,
    String? respostaCorreta,
    String comentario = '',
    DateTime? criadaEm,
    DateTime? proximaTentativa,
    List<bool> tentativas = const [],
    double? estabilidade,
    double? dificuldade,
    bool arquivada = false,
    String? banca,
    int? ano,
    String? orgao,
  }) => QuestaoErrada(
    id: id,
    materiaId: materiaId,
    topicoId: topicoId,
    enunciado: enunciado,
    respostaMarcada: respostaMarcada,
    respostaCorreta: respostaCorreta,
    comentario: comentario,
    criadaEm: criadaEm ?? hoje,
    proximaTentativa: proximaTentativa,
    tentativas: tentativas,
    estabilidade: estabilidade,
    dificuldade: dificuldade,
    arquivada: arquivada,
    banca: banca,
    ano: ano,
    orgao: orgao,
  );

  group('CadernoErrosService.fila', () {
    test('ordena por peso do edital — matéria que vale mais primeiro', () {
      final barata = questao(id: 'barata', materiaId: 'baixo', proximaTentativa: hoje);
      final cara = questao(id: 'cara', materiaId: 'alto', proximaTentativa: hoje);
      final fila = CadernoErrosService.fila(
        [barata, cara],
        hoje,
        pesoPorMateria: {'baixo': 1, 'alto': 5},
      );
      expect(fila.map((q) => q.id), ['cara', 'barata']);
    });

    test('desempata por atraso (quem espera há mais tempo primeiro)', () {
      final recente = questao(
        id: 'recente',
        proximaTentativa: DateTime(2026, 7, 29),
      );
      final antiga = questao(
        id: 'antiga',
        proximaTentativa: DateTime(2026, 7, 20),
      );
      final fila = CadernoErrosService.fila([recente, antiga], hoje);
      expect(fila.map((q) => q.id), ['antiga', 'recente']);
    });

    test('só entra quem já venceu — futura fica de fora', () {
      final vencida = questao(id: 'vencida', proximaTentativa: hoje);
      final futura = questao(
        id: 'futura',
        proximaTentativa: DateTime(hoje.year, hoje.month, hoje.day + 3),
      );
      final fila = CadernoErrosService.fila([vencida, futura], hoje);
      expect(fila.map((q) => q.id), ['vencida']);
    });

    test('arquivada nunca entra na fila mesmo vencida', () {
      final arquivada = questao(id: 'a', proximaTentativa: hoje, arquivada: true);
      expect(CadernoErrosService.fila([arquivada], hoje), isEmpty);
    });

    test('caderno vazio devolve fila vazia sem exceção', () {
      expect(CadernoErrosService.fila(const [], hoje), isEmpty);
    });
  });

  group('CadernoErrosService.registrarTentativa', () {
    test('acerto reagenda a questão pra frente (sai da fila de hoje)', () {
      final q = questao(proximaTentativa: hoje);
      final depois = CadernoErrosService.registrarTentativa(q, true, hoje);
      expect(depois.proximaTentativa.isAfter(hoje), isTrue);
      expect(depois.tentativas, [true]);
    });

    test('erro reagenda curto e derruba estabilidade', () {
      final q = questao(proximaTentativa: hoje, estabilidade: 10, dificuldade: 5);
      final depois = CadernoErrosService.registrarTentativa(q, false, hoje);
      expect(depois.estabilidade, isNotNull);
      expect(depois.estabilidade!, lessThan(10));
      expect(depois.proximaTentativa.isAfter(hoje), isTrue);
      expect(depois.arquivada, isFalse);
      expect(depois.tentativas, [false]);
    });

    test('2 acertos seguidos arquivam (dominada)', () {
      final q = questao(proximaTentativa: hoje);
      final depois1 = CadernoErrosService.registrarTentativa(q, true, hoje);
      expect(depois1.arquivada, isFalse);

      final depois2 = CadernoErrosService.registrarTentativa(depois1, true, hoje);
      expect(depois2.arquivada, isTrue);
      expect(depois2.acertosSeguidos, 2);
      expect(depois2.tentativas, [true, true]);
    });

    test('erro depois de acerto zera a sequência (não arquiva)', () {
      final q = questao(proximaTentativa: hoje);
      final depois1 = CadernoErrosService.registrarTentativa(q, true, hoje);
      final depois2 = CadernoErrosService.registrarTentativa(depois1, false, hoje);
      expect(depois2.arquivada, isFalse);
      expect(depois2.acertosSeguidos, 0);
    });
  });

  group('CadernoErrosService — bordas de caderno vazio (sem divisão por zero)', () {
    test('taxaRecuperacao vazio é null, não NaN', () {
      expect(CadernoErrosService.taxaRecuperacao(const []), isNull);
    });

    test('taxaRecuperacao com 1 questão ativa (0 dominadas) dá 0%, não null', () {
      final ativa = questao(id: 'ativa');
      expect(CadernoErrosService.taxaRecuperacao([ativa]), 0.0);
    });

    test('ranking vazio devolve lista vazia', () {
      expect(CadernoErrosService.ranking(const [], const []), isEmpty);
    });

    test('forecast vazio devolve 14 dias zerados, sem exceção', () {
      final forecast = CadernoErrosService.forecast(const [], hoje, dias: 14);
      expect(forecast.length, 14);
      expect(forecast.every((d) => d.quantidade == 0), isTrue);
    });

    test('porMateria/porTopico/porBanca vazios não quebram', () {
      expect(CadernoErrosService.porMateria(const []), isEmpty);
      expect(CadernoErrosService.porTopico(const []), isEmpty);
      expect(CadernoErrosService.porBanca(const []), isEmpty);
    });
  });

  group('QuestaoErrada — roundtrip JSON', () {
    test('toJson/fromJson preserva todos os campos', () {
      final original = questao(
        id: 'q9',
        materiaId: 'm9',
        topicoId: 't9',
        enunciado: '  Qual o prazo para recurso administrativo? ',
        respostaMarcada: 'B',
        respostaCorreta: 'D',
        comentario: 'Troquei o prazo de 10 por 15 dias.',
        criadaEm: DateTime(2026, 5, 1),
        proximaTentativa: DateTime(2026, 5, 10),
        tentativas: [true, false, true],
        estabilidade: 12.5,
        dificuldade: 4.2,
        arquivada: false,
        banca: 'cespe',
        ano: 2024,
        orgao: 'TCU',
      );
      final restaurada = QuestaoErrada.fromJson(original.toJson());

      expect(restaurada.id, original.id);
      expect(restaurada.materiaId, original.materiaId);
      expect(restaurada.topicoId, original.topicoId);
      expect(restaurada.enunciado, original.enunciado);
      expect(restaurada.respostaMarcada, original.respostaMarcada);
      expect(restaurada.respostaCorreta, original.respostaCorreta);
      expect(restaurada.comentario, original.comentario);
      expect(restaurada.criadaEm, original.criadaEm);
      expect(restaurada.proximaTentativa, original.proximaTentativa);
      expect(restaurada.tentativas, original.tentativas);
      expect(restaurada.estabilidade, original.estabilidade);
      expect(restaurada.dificuldade, original.dificuldade);
      expect(restaurada.arquivada, original.arquivada);
      expect(restaurada.ano, original.ano);
      expect(restaurada.orgao, original.orgao);
      expect(restaurada.origem, original.origem);
      // Banca normalizada na CONSTRUÇÃO original (Bancas.normalizar) — o
      // roundtrip preserva a forma já canônica, não o "cespe" digitado.
      expect(original.banca, 'CEBRASPE');
      expect(restaurada.banca, original.banca);
    });

    test('roundtrip com campos opcionais todos nulos', () {
      final original = questao(id: 'q10');
      final restaurada = QuestaoErrada.fromJson(original.toJson());
      expect(restaurada.topicoId, isNull);
      expect(restaurada.respostaMarcada, isNull);
      expect(restaurada.respostaCorreta, isNull);
      expect(restaurada.banca, isNull);
      expect(restaurada.ano, isNull);
      expect(restaurada.orgao, isNull);
      expect(restaurada.estabilidade, isNull);
      expect(restaurada.dificuldade, isNull);
    });

    test('roundtrip preserva origem simulado e simuladoId', () {
      final original = QuestaoErrada(
        id: 'q11',
        materiaId: 'm1',
        enunciado: 'x',
        criadaEm: hoje,
        origem: OrigemQuestao.simulado,
        simuladoId: 's1',
      );
      final restaurada = QuestaoErrada.fromJson(original.toJson());
      expect(restaurada.origem, OrigemQuestao.simulado);
      expect(restaurada.simuladoId, 's1');
    });
  });

  group('Providers do caderno (caderno_providers.dart)', () {
    Materia mat(String id, {int peso = 1}) =>
        Materia(id: id, nome: id.toUpperCase(), corSlot: 0, peso: peso, criadaEm: hoje);

    ProviderContainer container({
      required List<QuestaoErrada> questoes,
      List<Materia> materias = const [],
    }) => ProviderContainer(
      overrides: [
        questoesErradasDoAmbienteProvider.overrideWithValue(questoes),
        materiasDoAmbienteProvider.overrideWithValue(materias),
        hojeProvider.overrideWithValue(hoje),
      ],
    );

    test('filaDoDiaProvider ordena pelo peso do edital', () {
      final c = container(
        questoes: [
          questao(id: 'barata', materiaId: 'm1', proximaTentativa: hoje),
          questao(id: 'cara', materiaId: 'm2', proximaTentativa: hoje),
        ],
        materias: [mat('m1', peso: 1), mat('m2', peso: 9)],
      );
      addTearDown(c.dispose);
      expect(c.read(filaDoDiaProvider).map((q) => q.id), ['cara', 'barata']);
    });

    test('filaDoDiaProvider vazio em caderno vazio, sem exceção', () {
      final c = container(questoes: const []);
      addTearDown(c.dispose);
      expect(c.read(filaDoDiaProvider), isEmpty);
    });

    test('resumoCadernoProvider em caderno vazio não divide por zero', () {
      final c = container(questoes: const []);
      addTearDown(c.dispose);
      final resumo = c.read(resumoCadernoProvider);
      expect(resumo.totalAtivas, 0);
      expect(resumo.totalDominadas, 0);
      expect(resumo.venceHoje, 0);
      expect(resumo.taxaRecuperacao, isNull);
    });

    test('resumoCadernoProvider soma ativas/dominadas/vencidas corretamente', () {
      final c = container(
        questoes: [
          questao(id: 'a1', proximaTentativa: hoje), // ativa, vence hoje
          questao(
            id: 'a2',
            proximaTentativa: DateTime(hoje.year, hoje.month, hoje.day + 5),
          ), // ativa, não vence hoje
          questao(id: 'd1', arquivada: true, tentativas: const [true, true]),
        ],
      );
      addTearDown(c.dispose);
      final resumo = c.read(resumoCadernoProvider);
      expect(resumo.totalAtivas, 2);
      expect(resumo.totalDominadas, 1);
      expect(resumo.venceHoje, 1);
    });

    test('rankingCadernoProvider só lista matéria com erro ativo', () {
      final c = container(
        questoes: [
          questao(id: 'q1', materiaId: 'm1'),
          questao(id: 'q2', materiaId: 'm2', arquivada: true, tentativas: const [true, true]),
        ],
        materias: [mat('m1'), mat('m2')],
      );
      addTearDown(c.dispose);
      final ranking = c.read(rankingCadernoProvider);
      expect(ranking.length, 1);
      expect(ranking.first.materia.id, 'm1');
      expect(ranking.first.resumo.ativas, 1);
    });

    test('forecastCadernoProvider devolve 14 dias mesmo vazio', () {
      final c = container(questoes: const []);
      addTearDown(c.dispose);
      final forecast = c.read(forecastCadernoProvider);
      expect(forecast.length, 14);
      expect(forecast.every((d) => d.quantidade == 0), isTrue);
    });
  });

  group('QuestaoErrada.copyWith — limparAno (B9)', () {
    test('limparAno apaga o ano mesmo com valor preenchido antes', () {
      final comAno = questao(id: 'qa', ano: 2020);
      final semAno = comAno.copyWith(limparAno: true);
      expect(semAno.ano, isNull);
    });

    test('sem limparAno, não informar ano preserva o valor antigo', () {
      final comAno = questao(id: 'qa', ano: 2020);
      final copia = comAno.copyWith(enunciado: 'outro enunciado');
      expect(copia.ano, 2020);
    });

    test('ano novo sobrescreve o antigo normalmente (sem limparAno)', () {
      final comAno = questao(id: 'qa', ano: 2020);
      final copia = comAno.copyWith(ano: 2021);
      expect(copia.ano, 2021);
    });

    test('roundtrip JSON preserva o ano limpo (null), não ressuscita o antigo', () {
      final comAno = questao(id: 'qa', ano: 2020);
      final semAno = comAno.copyWith(limparAno: true);
      final restaurada = QuestaoErrada.fromJson(semAno.toJson());
      expect(restaurada.ano, isNull);
    });

    test('roundtrip JSON comum ainda preserva o ano quando não limpo', () {
      final comAno = questao(id: 'qa', ano: 2020);
      final restaurada = QuestaoErrada.fromJson(comAno.toJson());
      expect(restaurada.ano, 2020);
    });
  });

  group('ordenarPorBanca / ordenarPorTopico (B8) — batem com o serviço', () {
    test('ordenarPorBanca replica os números de CadernoErrosService.porBanca', () {
      final questoes = [
        questao(id: 'q1', banca: 'CEBRASPE'),
        questao(
          id: 'q2',
          banca: 'CEBRASPE',
          arquivada: true,
          tentativas: const [true, true],
        ),
        questao(id: 'q3', banca: 'FGV'),
        questao(id: 'q4'), // sem banca — não deve entrar (nem em balde "outros")
      ];
      final direto = CadernoErrosService.porBanca(questoes);
      final ordenado = ordenarPorBanca(questoes);

      expect(ordenado.length, direto.length);
      for (final linha in ordenado) {
        expect(linha.resumo, direto[linha.banca]);
      }
    });

    test('ordenarPorBanca ordena por ativas desc', () {
      final questoes = [
        questao(id: 'q1', banca: 'FGV'),
        questao(id: 'q2', banca: 'CEBRASPE'),
        questao(id: 'q3', banca: 'CEBRASPE'),
      ];
      final ordenado = ordenarPorBanca(questoes);
      expect(ordenado.map((l) => l.banca), ['CEBRASPE', 'FGV']);
    });

    test('ordenarPorBanca vazio devolve lista vazia', () {
      expect(ordenarPorBanca(const []), isEmpty);
    });

    test('ordenarPorTopico só lista tópico que ainda existe e bate com o serviço', () {
      final t1 = Topico(id: 't1', materiaId: 'm1', nome: 'Tópico 1');
      final t2 = Topico(id: 't2', materiaId: 'm1', nome: 'Tópico 2');
      final questoes = [
        questao(id: 'q1', topicoId: 't1'),
        questao(id: 'q2', topicoId: 't1'),
        questao(id: 'q3', topicoId: 't2'),
        questao(id: 'q4', topicoId: 'orfao'), // tópico excluído — some da lista
        questao(id: 'q5'), // sem tópico — não entra
      ];
      final direto = CadernoErrosService.porTopico(questoes);
      final ordenado = ordenarPorTopico(questoes, [t1, t2]);

      expect(ordenado.length, 2);
      for (final linha in ordenado) {
        expect(linha.resumo, direto[linha.topico.id]);
      }
      expect(ordenado.any((l) => l.topico.id == 'orfao'), isFalse);
    });

    test('ordenarPorTopico vazio devolve lista vazia', () {
      expect(ordenarPorTopico(const [], const []), isEmpty);
    });
  });

  group('calcularQuestoesOrfas (B5) — detecção de órfã', () {
    Materia mat(String id) => Materia(id: id, nome: id, corSlot: 0, criadaEm: hoje);
    Topico top(String id, String materiaId) =>
        Topico(id: id, materiaId: materiaId, nome: id);

    test('materiaId inexistente marca órfã por matéria', () {
      final q = questao(id: 'q1', materiaId: 'fantasma');
      final orfas = calcularQuestoesOrfas([q], [mat('m1')], const []);
      expect(orfas.length, 1);
      expect(orfas.first.questao.id, 'q1');
      expect(orfas.first.motivo, MotivoOrfandade.materiaInexistente);
    });

    test('topicoId inexistente com matéria válida marca órfã por tópico', () {
      final q = questao(id: 'q1', materiaId: 'm1', topicoId: 'fantasma');
      final orfas = calcularQuestoesOrfas([q], [mat('m1')], [top('t1', 'm1')]);
      expect(orfas.length, 1);
      expect(orfas.first.motivo, MotivoOrfandade.topicoInexistente);
    });

    test('questão sã sem tópico não é marcada como órfã', () {
      final q = questao(id: 'q1', materiaId: 'm1');
      final orfas = calcularQuestoesOrfas([q], [mat('m1')], const []);
      expect(orfas, isEmpty);
    });

    test('questão sã com matéria e tópico válidos não é marcada como órfã', () {
      final q = questao(id: 'q1', materiaId: 'm1', topicoId: 't1');
      final orfas = calcularQuestoesOrfas([q], [mat('m1')], [top('t1', 'm1')]);
      expect(orfas, isEmpty);
    });

    test('materiaId inexistente tem prioridade sobre o tópico (não relista o mesmo erro 2x)', () {
      // A matéria já era: o tópico (que pertencia a ela) também sumiu, mas o
      // motivo relatado é o da matéria — resolvê-la já resolve o resto, não
      // faz sentido reportar os dois problemas como órfãs separadas.
      final q = questao(id: 'q1', materiaId: 'fantasma', topicoId: 'tambem-fantasma');
      final orfas = calcularQuestoesOrfas([q], const [], const []);
      expect(orfas.length, 1);
      expect(orfas.first.motivo, MotivoOrfandade.materiaInexistente);
    });

    test('caderno vazio não quebra', () {
      expect(calcularQuestoesOrfas(const [], const [], const []), isEmpty);
    });
  });
}
