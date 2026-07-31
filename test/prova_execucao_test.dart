import 'package:app_estudos/data/models/execucao_prova.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/prova_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final inicio = DateTime(2026, 7, 30, 8, 0);

  ExecucaoProva execucao({
    String id = 'exec1',
    String nome = 'Prova teste',
    String ambienteId = 'geral',
    String? banca,
    DateTime? iniciadaEm,
    int duracaoMinutos = 240,
    List<ItemProva> itens = const [],
    DateTime? finalizadaEm,
  }) => ExecucaoProva(
    id: id,
    nome: nome,
    ambienteId: ambienteId,
    banca: banca,
    iniciadaEm: iniciadaEm ?? inicio,
    duracaoMinutos: duracaoMinutos,
    itens: itens,
    finalizadaEm: finalizadaEm,
  );

  group('ItemProva — invariantes', () {
    test('número < 1 vira 1', () {
      expect(ItemProva(numero: 0).numero, 1);
      expect(ItemProva(numero: -5).numero, 1);
    });

    test('resposta e gabarito normalizados: maiúscula, sem espaço', () {
      final i = ItemProva(numero: 1, respostaMarcada: ' a ', gabarito: 'b');
      expect(i.respostaMarcada, 'A');
      expect(i.gabarito, 'B');
    });

    test('resposta vazia ou só espaço vira null, não string vazia', () {
      final i = ItemProva(numero: 1, respostaMarcada: '   ', gabarito: '');
      expect(i.respostaMarcada, isNull);
      expect(i.gabarito, isNull);
    });

    test('copyWith com limparResposta desmarca (não reaproveita a antiga)', () {
      final i = ItemProva(numero: 1, respostaMarcada: 'A');
      final desmarcado = i.copyWith(respostaMarcada: null, limparResposta: true);
      expect(desmarcado.respostaMarcada, isNull);
    });

    test('roundtrip JSON preserva tudo', () {
      final i = ItemProva(
        numero: 3,
        materiaId: 'm1',
        respostaMarcada: 'c',
        gabarito: 'D',
        enunciado: 'Enunciado X',
        comentario: 'confundi os prazos',
      );
      final volta = ItemProva.fromJson(i.toJson());
      expect(volta.numero, 3);
      expect(volta.materiaId, 'm1');
      expect(volta.respostaMarcada, 'C');
      expect(volta.gabarito, 'D');
      expect(volta.enunciado, 'Enunciado X');
      expect(volta.comentario, 'confundi os prazos');
    });
  });

  group('ExecucaoProva — invariantes', () {
    test('duração <= 0 vira 1 minuto (nunca trava tempo restante em prova '
        'impossível)', () {
      expect(execucao(duracaoMinutos: 0).duracaoMinutos, 1);
      expect(execucao(duracaoMinutos: -10).duracaoMinutos, 1);
    });

    test('duração acima de 16h é clampada', () {
      expect(execucao(duracaoMinutos: 99999).duracaoMinutos, 16 * 60);
    });

    test('banca normalizada (apelido CESPE -> CEBRASPE)', () {
      expect(execucao(banca: 'cespe').banca, 'CEBRASPE');
    });

    test('ativa == finalizadaEm nulo; fimPrevisto = início + duração', () {
      final e = execucao(duracaoMinutos: 60);
      expect(e.ativa, isTrue);
      expect(e.fimPrevisto, inicio.add(const Duration(minutes: 60)));
      expect(e.copyWith(finalizadaEm: inicio).ativa, isFalse);
    });

    test('comItemAtualizado troca só o item do número pedido', () {
      final e = execucao(
        itens: [ItemProva(numero: 1), ItemProva(numero: 2)],
      );
      final atualizada = e.comItemAtualizado(
        2,
        (i) => i.copyWith(respostaMarcada: 'A'),
      );
      expect(atualizada.itens[0].respostaMarcada, isNull);
      expect(atualizada.itens[1].respostaMarcada, 'A');
    });

    test('roundtrip JSON preserva execução e itens', () {
      final e = execucao(
        banca: 'fgv',
        itens: [
          ItemProva(numero: 1, materiaId: 'm1', respostaMarcada: 'A'),
          ItemProva(numero: 2, gabarito: 'B'),
        ],
        finalizadaEm: inicio.add(const Duration(hours: 1)),
      );
      final volta = ExecucaoProva.fromJson(e.toJson());
      expect(volta.id, e.id);
      expect(volta.nome, e.nome);
      expect(volta.ambienteId, e.ambienteId);
      expect(volta.banca, 'FGV');
      expect(volta.iniciadaEm, e.iniciadaEm);
      expect(volta.duracaoMinutos, e.duracaoMinutos);
      expect(volta.itens.length, 2);
      expect(volta.itens[0].respostaMarcada, 'A');
      expect(volta.itens[1].gabarito, 'B');
      expect(volta.finalizadaEm, e.finalizadaEm);
    });
  });

  group('ProvaService.tempoRestante', () {
    test('nunca negativo — agora depois do fim previsto trava em zero', () {
      final e = execucao(duracaoMinutos: 60);
      final restante = ProvaService.tempoRestante(
        e,
        inicio.add(const Duration(hours: 5)),
      );
      expect(restante, Duration.zero);
    });

    test('agora antes do fim: diferença exata', () {
      final e = execucao(duracaoMinutos: 60);
      final restante = ProvaService.tempoRestante(
        e,
        inicio.add(const Duration(minutes: 15)),
      );
      expect(restante, const Duration(minutes: 45));
    });

    test('exatamente no instante do fim: zero, não negativo por 1ms', () {
      final e = execucao(duracaoMinutos: 60);
      final restante = ProvaService.tempoRestante(e, e.fimPrevisto);
      expect(restante, Duration.zero);
    });

    test('prova finalizada trava em zero mesmo que ainda faltasse tempo', () {
      final e = execucao(
        duracaoMinutos: 60,
        finalizadaEm: inicio.add(const Duration(minutes: 10)),
      );
      final restante = ProvaService.tempoRestante(
        e,
        inicio.add(const Duration(minutes: 12)),
      );
      expect(restante, Duration.zero);
    });
  });

  group('ProvaService.progresso', () {
    test('conta só itens com resposta marcada', () {
      final e = execucao(
        itens: [
          ItemProva(numero: 1, respostaMarcada: 'A'),
          ItemProva(numero: 2),
          ItemProva(numero: 3, respostaMarcada: 'C'),
        ],
      );
      final p = ProvaService.progresso(e);
      expect(p.respondidas, 2);
      expect(p.total, 3);
    });
  });

  group('ProvaService.corrigir', () {
    test('gabarito parcial: item sem gabarito fica fora da apuração', () {
      final e = execucao(
        itens: [
          ItemProva(numero: 1, gabarito: 'A', respostaMarcada: 'A'), // acerto
          ItemProva(numero: 2, gabarito: 'B', respostaMarcada: 'C'), // erro
          ItemProva(numero: 3, respostaMarcada: 'A'), // sem gabarito
        ],
      );
      final c = ProvaService.corrigir(e);
      expect(c.acertos, 1);
      expect(c.erros, 1);
      // Só a 3 está em branco de resposta? Não — só a computação de
      // embranco olha respostaMarcada, e a 3 TEM resposta ('A'); nenhuma
      // está em branco aqui.
      expect(c.embranco, 0);
      // A questão 3 nunca aparece em itensErrados (não foi apurada).
      expect(c.itensErrados.map((i) => i.numero), [2]);
    });

    test('item em branco só conta como erro quando há gabarito', () {
      final e = execucao(
        itens: [
          ItemProva(numero: 1, gabarito: 'A'), // em branco, tem gabarito
          ItemProva(numero: 2), // em branco, SEM gabarito
        ],
      );
      final c = ProvaService.corrigir(e);
      // embranco conta as DUAS (comportamento do candidato).
      expect(c.embranco, 2);
      // erros conta só a 1 (a 2 não tem gabarito pra apurar).
      expect(c.erros, 1);
      expect(c.acertos, 0);
      expect(c.itensErrados.map((i) => i.numero), [1]);
    });

    test('agrupa resultados por matéria; sem matéria cai no bucket '
        'não-classificada', () {
      final e = execucao(
        itens: [
          ItemProva(
            numero: 1,
            materiaId: 'm1',
            gabarito: 'A',
            respostaMarcada: 'A',
          ),
          ItemProva(
            numero: 2,
            materiaId: 'm1',
            gabarito: 'B',
            respostaMarcada: 'C',
          ),
          ItemProva(
            numero: 3,
            materiaId: 'm2',
            gabarito: 'D',
            respostaMarcada: 'D',
          ),
          ItemProva(numero: 4, gabarito: 'A', respostaMarcada: 'A'),
        ],
      );
      final c = ProvaService.corrigir(e);
      final porId = {for (final r in c.resultados) r.materiaId: r};
      expect(porId['m1']!.questoes, 2);
      expect(porId['m1']!.acertos, 1);
      expect(porId['m2']!.questoes, 1);
      expect(porId['m2']!.acertos, 1);
      expect(porId[ProvaService.materiaNaoClassificada]!.questoes, 1);
      expect(porId[ProvaService.materiaNaoClassificada]!.acertos, 1);
    });

    test('itensErrados preserva os ItemProva originais (não só o número)', () {
      final errado = ItemProva(
        numero: 5,
        materiaId: 'm1',
        gabarito: 'A',
        respostaMarcada: 'B',
        comentario: 'troquei o conceito',
      );
      final e = execucao(itens: [errado]);
      final c = ProvaService.corrigir(e);
      expect(c.itensErrados.single.comentario, 'troquei o conceito');
      expect(c.itensErrados.single.materiaId, 'm1');
    });
  });

  group('ProvaService.paraSimulado', () {
    test('tempoMinutos é o tempo REALMENTE gasto, não a duração planejada', () {
      final e = execucao(
        duracaoMinutos: 240, // 4h planejadas
        finalizadaEm: inicio.add(const Duration(minutes: 90)), // só 1h30
        itens: [
          ItemProva(numero: 1, gabarito: 'A', respostaMarcada: 'A'),
        ],
      );
      final c = ProvaService.corrigir(e);
      final simulado = ProvaService.paraSimulado(e, c, simuladoId: 's1');
      expect(simulado.tempoMinutos, 90);
      expect(simulado.id, 's1');
      expect(simulado.data, inicio);
      expect(simulado.resultados, c.resultados);
    });

    test('sem finalizadaEm (defensivo) usa o fim previsto', () {
      final e = execucao(duracaoMinutos: 120);
      final c = ProvaService.corrigir(e);
      final simulado = ProvaService.paraSimulado(e, c, simuladoId: 's2');
      expect(simulado.tempoMinutos, 120);
    });

    test('banca e nome herdados da execução', () {
      final e = execucao(nome: 'SEFAZ objetiva', banca: 'fgv');
      final c = ProvaService.corrigir(e);
      final simulado = ProvaService.paraSimulado(e, c, simuladoId: 's3');
      expect(simulado.nome, 'SEFAZ objetiva');
      expect(simulado.banca, 'FGV');
    });
  });

  group('ProvaService.paraQuestoesErradas', () {
    test('gera só as erradas, uma por item de correcao.itensErrados', () {
      final e = execucao(
        id: 'execX',
        nome: 'Prova ABC',
        banca: 'fgv',
        itens: [
          ItemProva(numero: 1, gabarito: 'A', respostaMarcada: 'A'), // certo
          ItemProva(
            numero: 2,
            materiaId: 'm1',
            gabarito: 'B',
            respostaMarcada: 'C',
            comentario: 'chutei',
          ),
        ],
      );
      final c = ProvaService.corrigir(e);
      final hoje = DateTime(2026, 7, 30);
      final erradas = ProvaService.paraQuestoesErradas(e, c, hoje);

      expect(erradas, hasLength(1));
      final q = erradas.single;
      expect(q.origem, OrigemQuestao.simulado);
      expect(q.simuladoId, 'execX');
      expect(q.banca, 'FGV');
      expect(q.materiaId, 'm1');
      expect(q.respostaMarcada, 'C');
      expect(q.respostaCorreta, 'B');
      expect(q.comentario, 'chutei');
      expect(q.criadaEm, hoje);
      expect(q.enunciado, 'Questão 2 — Prova ABC');
    });

    test('usa o enunciado digitado quando presente, em vez do rótulo padrão', () {
      final e = execucao(
        id: 'execY',
        itens: [
          ItemProva(
            numero: 7,
            gabarito: 'A',
            respostaMarcada: 'B',
            enunciado: 'O que diz o art. 37 da CF/88?',
          ),
        ],
      );
      final c = ProvaService.corrigir(e);
      final erradas = ProvaService.paraQuestoesErradas(
        e,
        c,
        DateTime(2026, 7, 30),
      );
      expect(erradas.single.enunciado, 'O que diz o art. 37 da CF/88?');
    });

    test('sem matéria cai no bucket não-classificada', () {
      final e = execucao(
        itens: [ItemProva(numero: 1, gabarito: 'A', respostaMarcada: 'B')],
      );
      final c = ProvaService.corrigir(e);
      final erradas = ProvaService.paraQuestoesErradas(
        e,
        c,
        DateTime(2026, 7, 30),
      );
      expect(erradas.single.materiaId, ProvaService.materiaNaoClassificada);
    });

    test('ids determinísticos (execução + número): reexecutar não duplica '
        'no upsert do repositório', () {
      final e = execucao(
        id: 'execZ',
        itens: [ItemProva(numero: 4, gabarito: 'A', respostaMarcada: 'B')],
      );
      final c = ProvaService.corrigir(e);
      final primeira = ProvaService.paraQuestoesErradas(
        e,
        c,
        DateTime(2026, 7, 30),
      );
      final segunda = ProvaService.paraQuestoesErradas(
        e,
        c,
        DateTime(2026, 7, 31),
      );
      expect(primeira.single.id, segunda.single.id);
      expect(primeira.single.id, 'execZ-4');
    });
  });

  group('ProvaService.paraRegistroHora', () {
    test('matéria única na correção -> RegistroHora vai pra ela', () {
      final e = execucao(
        nome: 'Prova única matéria',
        banca: 'fgv',
        duracaoMinutos: 60,
        finalizadaEm: inicio.add(const Duration(minutes: 40)),
        itens: [
          ItemProva(
            numero: 1,
            materiaId: 'm1',
            gabarito: 'A',
            respostaMarcada: 'A',
          ),
          ItemProva(
            numero: 2,
            materiaId: 'm1',
            gabarito: 'B',
            respostaMarcada: 'C',
          ),
        ],
      );
      final c = ProvaService.corrigir(e);
      final registro = ProvaService.paraRegistroHora(e, c, id: 'r1');
      expect(registro.materiaId, 'm1');
      expect(registro.minutos, 40);
      expect(registro.questoes, 2);
      expect(registro.acertos, 1);
      expect(registro.banca, 'FGV');
      expect(registro.tipo, TipoEstudo.pratica);
      expect(registro.tarefa, 'Prova única matéria');
    });

    test('múltiplas matérias -> cai no bucket não-classificada', () {
      final e = execucao(
        itens: [
          ItemProva(
            numero: 1,
            materiaId: 'm1',
            gabarito: 'A',
            respostaMarcada: 'A',
          ),
          ItemProva(
            numero: 2,
            materiaId: 'm2',
            gabarito: 'B',
            respostaMarcada: 'B',
          ),
        ],
      );
      final c = ProvaService.corrigir(e);
      final registro = ProvaService.paraRegistroHora(e, c, id: 'r2');
      expect(registro.materiaId, ProvaService.materiaNaoClassificada);
    });

    test('nenhuma matéria classificada (0 resultados) -> bucket também', () {
      final e = execucao(itens: const []);
      final c = ProvaService.corrigir(e);
      final registro = ProvaService.paraRegistroHora(e, c, id: 'r3');
      expect(registro.materiaId, ProvaService.materiaNaoClassificada);
      expect(registro.questoes, 0);
      expect(registro.acertos, 0);
    });
  });

  group('Borda: prova com 0 questões (sem divisão por zero)', () {
    test('progresso, correção e derivados não quebram', () {
      final e = execucao(itens: const []);

      final p = ProvaService.progresso(e);
      expect(p.respondidas, 0);
      expect(p.total, 0);

      final c = ProvaService.corrigir(e);
      expect(c.acertos, 0);
      expect(c.erros, 0);
      expect(c.embranco, 0);
      expect(c.resultados, isEmpty);
      expect(c.itensErrados, isEmpty);

      final simulado = ProvaService.paraSimulado(e, c, simuladoId: 'sZero');
      expect(simulado.totalQuestoes, 0);
      expect(simulado.taxaGeral, isNull); // já guardado no próprio Simulado
      expect(simulado.resultados, isEmpty);

      final erradas = ProvaService.paraQuestoesErradas(
        e,
        c,
        DateTime(2026, 7, 30),
      );
      expect(erradas, isEmpty);

      // tempoRestante não depende do nº de questões — continua íntegro.
      final restante = ProvaService.tempoRestante(
        e,
        inicio.add(const Duration(minutes: 10)),
      );
      expect(restante, const Duration(minutes: 230)); // 240 (padrão) - 10
    });
  });
}
