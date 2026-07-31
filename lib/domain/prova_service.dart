import '../data/models/execucao_prova.dart';
import '../data/models/questao_errada.dart';
import '../data/models/registro_hora.dart';
import '../data/models/simulado.dart';

/// Resultado da correção de uma prova — ver [ProvaService.corrigir].
typedef CorrecaoProva = ({
  int acertos,
  int erros,
  int embranco,
  List<ResultadoMateria> resultados,
  List<ItemProva> itensErrados,
});

/// Quantas questões já têm resposta marcada, do total da prova.
typedef ProgressoProva = ({int respondidas, int total});

/// Regras puras da prova cronometrada — tempo, progresso e correção.
///
/// 100% funções puras sobre [ExecucaoProva]: quem chama injeta `agora`/
/// `hoje`, o serviço nunca lê o relógio. Mesma disciplina do resto de
/// domain/ (RevisaoService, CadernoErrosService).
class ProvaService {
  /// Bucket de questões sem matéria classificada. O setup da prova permite
  /// pular as faixas por matéria (campo opcional), e sem um valor aqui
  /// ResultadoMateria/QuestaoErrada/RegistroHora — todos com materiaId
  /// obrigatório — descartariam essas questões em silêncio. Prefixo e sufixo
  /// com underscore: não deve colidir com um id de Materia real (uuid v4).
  /// A UI trata como matéria desconhecida e mostra "—" (mesmo fallback que
  /// SimuladosScreen já usa pra materiaId sem matéria correspondente).
  static const materiaNaoClassificada = '_prova_sem_materia_';

  /// Tempo até o fim da prova pelo relógio de parede — nunca negativo.
  /// Depois de finalizada trava em zero (não tem mais o que contar).
  static Duration tempoRestante(ExecucaoProva execucao, DateTime agora) {
    if (execucao.finalizadaEm != null) return Duration.zero;
    final restante = execucao.fimPrevisto.difference(agora);
    return restante.isNegative ? Duration.zero : restante;
  }

  /// Quantas questões já têm resposta marcada, do total.
  static ProgressoProva progresso(ExecucaoProva execucao) {
    final total = execucao.itens.length;
    final respondidas = execucao.itens
        .where((i) => i.respostaMarcada != null)
        .length;
    return (respondidas: respondidas, total: total);
  }

  /// Corrige a prova pelo gabarito preenchido em cada item.
  ///
  /// Regras do modo prova:
  /// - item SEM gabarito não entra na apuração — nem acerto, nem erro, nem
  ///   nos totais por matéria. A folha de correção pode estar incompleta, e
  ///   contar como erro seria punir sem informação.
  /// - item em branco (sem resposta marcada) COM gabarito conta como erro:
  ///   não respondeu, não pode ter acertado.
  /// - `embranco` conta toda questão sem resposta marcada, tenha gabarito ou
  ///   não — é sobre o COMPORTAMENTO do candidato (quantas ele pulou), não
  ///   sobre a apuração.
  static CorrecaoProva corrigir(ExecucaoProva execucao) {
    var acertos = 0;
    var erros = 0;
    var embranco = 0;
    final itensErrados = <ItemProva>[];
    final questoesPorMateria = <String, int>{};
    final acertosPorMateria = <String, int>{};

    for (final item in execucao.itens) {
      if (item.respostaMarcada == null) embranco++;

      final gabarito = item.gabarito;
      if (gabarito == null) continue;

      final materiaId = item.materiaId ?? materiaNaoClassificada;
      questoesPorMateria[materiaId] = (questoesPorMateria[materiaId] ?? 0) + 1;

      if (item.respostaMarcada == gabarito) {
        acertos++;
        acertosPorMateria[materiaId] =
            (acertosPorMateria[materiaId] ?? 0) + 1;
      } else {
        erros++;
        itensErrados.add(item);
      }
    }

    final resultados = [
      for (final entrada in questoesPorMateria.entries)
        ResultadoMateria(
          materiaId: entrada.key,
          questoes: entrada.value,
          acertos: acertosPorMateria[entrada.key] ?? 0,
        ),
    ];

    return (
      acertos: acertos,
      erros: erros,
      embranco: embranco,
      resultados: resultados,
      itensErrados: itensErrados,
    );
  }

  /// Tempo realmente gasto, em minutos — fim menos início, nunca negativo.
  /// Sem [ExecucaoProva.finalizadaEm] (defensivo: o fluxo real só chama isso
  /// depois de finalizar) cai pro fim previsto — mais plausível que deixar
  /// null se propagar.
  static int _minutosGastos(ExecucaoProva execucao) {
    final fim = execucao.finalizadaEm ?? execucao.fimPrevisto;
    final minutos = fim.difference(execucao.iniciadaEm).inMinutes;
    return minutos < 0 ? 0 : minutos;
  }

  /// Simulado pronto para gravar. `tempoMinutos` é o tempo REAL gasto (fim
  /// − início), não [ExecucaoProva.duracaoMinutos]: terminar antes ou
  /// estourar o relógio precisa refletir no min/questão de verdade.
  static Simulado paraSimulado(
    ExecucaoProva execucao,
    CorrecaoProva correcao, {
    required String simuladoId,
  }) {
    return Simulado(
      id: simuladoId,
      ambienteId: execucao.ambienteId,
      tipo: TipoSimulado.simulado,
      nome: execucao.nome,
      banca: execucao.banca,
      data: execucao.iniciadaEm,
      tempoMinutos: _minutosGastos(execucao),
      resultados: correcao.resultados,
    );
  }

  /// Uma [QuestaoErrada] por item errado — alimenta o caderno de erros
  /// direto da correção, sem o candidato redigitar nada. `simuladoId` é
  /// sempre [ExecucaoProva.id]: é o MESMO id que o call site usa como
  /// `simuladoId` em [paraSimulado] (a execução vira o simulado, mesmo id),
  /// então o vínculo entre a questão e a prova nunca desalinha.
  static List<QuestaoErrada> paraQuestoesErradas(
    ExecucaoProva execucao,
    CorrecaoProva correcao,
    DateTime hoje,
  ) {
    return [
      for (final item in correcao.itensErrados)
        QuestaoErrada(
          // Determinístico (execução + número), não Uuid: reexecutar a
          // correção (ex.: usuário toca "Corrigir e salvar" de novo) faz
          // upsert em vez de duplicar entradas no caderno.
          id: '${execucao.id}-${item.numero}',
          materiaId: item.materiaId ?? materiaNaoClassificada,
          enunciado: (item.enunciado?.trim().isNotEmpty ?? false)
              ? item.enunciado!.trim()
              : 'Questão ${item.numero} — ${execucao.nome}',
          respostaMarcada: item.respostaMarcada,
          respostaCorreta: item.gabarito,
          comentario: item.comentario,
          banca: execucao.banca,
          origem: OrigemQuestao.simulado,
          simuladoId: execucao.id,
          criadaEm: hoje,
        ),
    ];
  }

  /// RegistroHora único de prática para a prova inteira. RegistroHora não
  /// modela prova multi-matéria (uma matéria por registro): com exatamente
  /// uma matéria na correção, o tempo vai pra ela de verdade (alimenta
  /// horas/streak daquela matéria); com zero ou mais de uma, cai no bucket
  /// [materiaNaoClassificada] — não há como escolher uma só sem inventar
  /// peso.
  static RegistroHora paraRegistroHora(
    ExecucaoProva execucao,
    CorrecaoProva correcao, {
    required String id,
  }) {
    final materiaId = correcao.resultados.length == 1
        ? correcao.resultados.first.materiaId
        : materiaNaoClassificada;
    return RegistroHora(
      id: id,
      data: execucao.iniciadaEm,
      materiaId: materiaId,
      tipo: TipoEstudo.pratica,
      tarefa: execucao.nome,
      minutos: _minutosGastos(execucao),
      questoes: correcao.acertos + correcao.erros,
      acertos: correcao.acertos,
      banca: execucao.banca,
    );
  }
}
