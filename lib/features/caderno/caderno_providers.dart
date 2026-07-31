import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/materia.dart';
import '../../data/models/questao_errada.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/caderno_erros_service.dart';
import '../dashboard/dashboard_providers.dart';

/// Agregados derivados do caderno de erros — mesma filosofia dos providers
/// do dashboard (dashboard_providers.dart): cada tela/card lê um `Provider`
/// memoizado em vez de rodar `CadernoErrosService` direto no `build`, e toda
/// data usada em regra de negócio vem de [hojeProvider] — nunca
/// `DateTime.now()` aqui — para os testes ficarem determinísticos.

/// Questões erradas do ambiente ativo (todas na visão consolidada).
///
/// [QuestaoErrada] não carrega `ambienteId` direto (não é entidade "de
/// topo" como Simulado) — o escopo vem por associação via `materiaId`,
/// exatamente como `registrosDoAmbienteProvider`/`revisoesDoAmbienteProvider`
/// fazem em ambiente_filtros.dart. Replicado aqui (em vez de editar aquele
/// arquivo) para não mexer em código de outra frente de trabalho.
final questoesErradasDoAmbienteProvider = Provider<List<QuestaoErrada>>((ref) {
  final questoes = ref.watch(questoesErradasProvider);
  final ativo = ref.watch(ambienteAtivoProvider);
  if (ativo == null) return questoes;
  final idsDoAmbiente = ref
      .watch(materiasDoAmbienteProvider)
      .map((m) => m.id)
      .toSet();
  return [
    for (final q in questoes)
      if (idsDoAmbiente.contains(q.materiaId)) q,
  ];
});

/// Peso do edital por matéria, só das matérias vivas no ambiente ativo — a
/// fila do caderno usa isso pra priorizar "o que vale mais na prova primeiro"
/// (mesmo critério do `CadernoErrosService.fila`). Matéria fora do mapa cai
/// no peso 1 (default do próprio serviço), então não precisa cobrir matéria
/// excluída aqui.
final _pesoPorMateriaCadernoProvider = Provider<Map<String, int>>((ref) {
  return {for (final m in ref.watch(materiasDoAmbienteProvider)) m.id: m.peso};
});

/// Fila de hoje: questões vencidas e ativas, mais urgentes primeiro.
final filaDoDiaProvider = Provider<List<QuestaoErrada>>((ref) {
  return CadernoErrosService.fila(
    ref.watch(questoesErradasDoAmbienteProvider),
    ref.watch(hojeProvider),
    pesoPorMateria: ref.watch(_pesoPorMateriaCadernoProvider),
  );
});

/// Números-resumo do caderno — cabeçalho da tela e card do dashboard.
typedef ResumoCaderno = ({
  int totalAtivas,
  int totalDominadas,
  int venceHoje,
  double? taxaRecuperacao,
});

final resumoCadernoProvider = Provider<ResumoCaderno>((ref) {
  final questoes = ref.watch(questoesErradasDoAmbienteProvider);
  final hoje = ref.watch(hojeProvider);
  final ativas = questoes.where((q) => !q.arquivada).length;
  return (
    totalAtivas: ativas,
    totalDominadas: questoes.length - ativas,
    // venceEm() já exclui arquivada — contagem "de relance" do que precisa
    // de atenção hoje.
    venceHoje: questoes.where((q) => q.venceEm(hoje)).length,
    taxaRecuperacao: CadernoErrosService.taxaRecuperacao(questoes),
  );
});

/// Matérias com mais erros ativos, piores primeiro — "onde estou sangrando".
final rankingCadernoProvider =
    Provider<List<({Materia materia, ResumoErros resumo})>>((ref) {
      return CadernoErrosService.ranking(
        ref.watch(questoesErradasDoAmbienteProvider),
        ref.watch(materiasDoAmbienteProvider),
      );
    });

/// Bancas com mais erros ativos, piores primeiro — mesma leitura do ranking
/// por matéria numa dimensão a mais: bancas cobram de jeitos diferentes (ver
/// [Bancas]), então a taxa ao refazer por banca aponta ONDE o estilo de
/// prova pega o candidato. Função pura (sem `ref`) para ser testável direto,
/// igual aos métodos de [CadernoErrosService] — o provider abaixo só
/// encaixa a leitura reativa.
List<({String banca, ResumoErros resumo})> ordenarPorBanca(
  List<QuestaoErrada> questoes,
) {
  final agregado = CadernoErrosService.porBanca(questoes);
  return [
    for (final entry in agregado.entries) (banca: entry.key, resumo: entry.value),
  ]..sort((a, b) {
    final porAtivas = b.resumo.ativas.compareTo(a.resumo.ativas);
    if (porAtivas != 0) return porAtivas;
    final porTotal = b.resumo.total.compareTo(a.resumo.total);
    if (porTotal != 0) return porTotal;
    return a.banca.compareTo(b.banca);
  });
}

final rankingPorBancaCadernoProvider =
    Provider<List<({String banca, ResumoErros resumo})>>((ref) {
      return ordenarPorBanca(ref.watch(questoesErradasDoAmbienteProvider));
    });

/// Tópicos com mais erros ativos, piores primeiro. Só entram tópicos que
/// ainda existem em [topicos]: uma questão cujo tópico foi excluído fica
/// órfã de propósito (enunciado é conteúdo caro — ver
/// [questoesOrfasProvider]) e some daqui até ser reatribuída, mesmo filtro
/// que `CadernoErrosService.ranking` já aplica para matéria excluída.
List<({Topico topico, ResumoErros resumo})> ordenarPorTopico(
  List<QuestaoErrada> questoes,
  List<Topico> topicos,
) {
  final agregado = CadernoErrosService.porTopico(questoes);
  return [
    for (final t in topicos)
      if (agregado[t.id] != null) (topico: t, resumo: agregado[t.id]!),
  ]..sort((a, b) {
    final porAtivas = b.resumo.ativas.compareTo(a.resumo.ativas);
    if (porAtivas != 0) return porAtivas;
    final porTotal = b.resumo.total.compareTo(a.resumo.total);
    if (porTotal != 0) return porTotal;
    return a.topico.nome.toLowerCase().compareTo(b.topico.nome.toLowerCase());
  });
}

final rankingPorTopicoCadernoProvider =
    Provider<List<({Topico topico, ResumoErros resumo})>>((ref) {
      return ordenarPorTopico(
        ref.watch(questoesErradasDoAmbienteProvider),
        ref.watch(topicosProvider),
      );
    });

/// Forecast de carga dos próximos 14 dias (aba Estatísticas).
final forecastCadernoProvider = Provider<List<({DateTime dia, int quantidade})>>((
  ref,
) {
  return CadernoErrosService.forecast(
    ref.watch(questoesErradasDoAmbienteProvider),
    ref.watch(hojeProvider),
    dias: 14,
  );
});

/// Bancas já usadas em QUALQUER questão do caderno (não escopado por
/// ambiente: banca é uma classificação estável — CEBRASPE é CEBRASPE em
/// qualquer concurso — então vale sugerir mesmo a usada em outro ambiente).
/// Alimenta o Autocomplete do formulário junto com `Bancas.sugestoes`.
/// Renomeado de `bancasUsadasProvider` para não colidir com o homônimo de
/// `dashboard/bancas_providers.dart`, que agrega sessões + simulados. Este
/// aqui olha só o caderno de erros e serve de sugestão no formulário.
final bancasDoCadernoProvider = Provider<List<String>>((ref) {
  final usadas = <String>{
    for (final q in ref.watch(questoesErradasProvider))
      if (q.banca != null) q.banca!,
  };
  return usadas.toList()..sort();
});

// ---------------------------------------------------------------------------
// Questões órfãs (B5) — matéria ou tópico excluído deixou o vínculo pendurado
// ---------------------------------------------------------------------------

/// Por que a questão ficou órfã. Guia a tela de resolução: matéria
/// inexistente força escolher uma matéria nova (o tópico antigo também some
/// junto, já que pertencia à matéria excluída); tópico inexistente permite
/// manter a matéria e só trocar/limpar o tópico.
enum MotivoOrfandade { materiaInexistente, topicoInexistente }

typedef QuestaoOrfa = ({QuestaoErrada questao, MotivoOrfandade motivo});

/// Questões cujo `materiaId` ou `topicoId` (quando informado) aponta para
/// algo que não existe mais em [materias]/[topicos]. Função pura — sem
/// Hive/Riverpod — para ser testável com listas soltas em memória; o
/// provider abaixo só encaixa a leitura reativa.
List<QuestaoOrfa> calcularQuestoesOrfas(
  List<QuestaoErrada> questoes,
  List<Materia> materias,
  List<Topico> topicos,
) {
  final materiaIds = materias.map((m) => m.id).toSet();
  final topicoIds = topicos.map((t) => t.id).toSet();
  final orfas = <QuestaoOrfa>[];
  for (final q in questoes) {
    if (!materiaIds.contains(q.materiaId)) {
      orfas.add((questao: q, motivo: MotivoOrfandade.materiaInexistente));
    } else if (q.topicoId != null && !topicoIds.contains(q.topicoId)) {
      orfas.add((questao: q, motivo: MotivoOrfandade.topicoInexistente));
    }
  }
  return orfas;
}

/// Excluir matéria ou tópico preserva a `QuestaoErrada` de propósito (o
/// enunciado é conteúdo caro escrito à mão — ver `MateriaUseCase`/
/// `TopicoUseCase`), então o vínculo fica pendurado em vez de a questão
/// sumir junto. Varre as coleções GLOBAIS (`materiasProvider`/
/// `topicosProvider`, não as `DoAmbiente`): uma questão órfã não pertence a
/// ambiente nenhum — a matéria que a colocaria num ambiente já era —, então
/// filtrar pelo ambiente ativo esconderia o aviso sempre que o usuário não
/// estivesse na visão consolidada.
final questoesOrfasProvider = Provider<List<QuestaoOrfa>>((ref) {
  return calcularQuestoesOrfas(
    ref.watch(questoesErradasProvider),
    ref.watch(materiasProvider),
    ref.watch(topicosProvider),
  );
});
