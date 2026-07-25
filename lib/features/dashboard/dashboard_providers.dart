import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ambiente.dart';
import '../../data/models/materia.dart';
import '../../data/models/revisao.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/planejamento_repositorio.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/diagnostico_service.dart';
import '../../domain/dominio_service.dart';
import '../../domain/gamificacao_service.dart';
import '../../domain/insights_service.dart';
import '../../domain/mapa_estudos_service.dart';
import '../../domain/planejamento_service.dart';
import '../../domain/prontidao_service.dart';
import '../../domain/quests_service.dart';
import '../../domain/retencao_service.dart';
import '../../domain/revisao_service.dart';
import '../../domain/stats_service.dart';

/// Camada de agregados derivados do dashboard (item 2 da auditoria).
///
/// Antes cada card chamava os `*Service` direto sobre as listas cruas dentro
/// do `build`, então TODA agregação O(n) rodava de novo a cada rebuild do
/// dashboard (troca de aba com IndexedStack vivo, animação, seleção). Aqui a
/// agregação vira `Provider`: o Riverpod memoiza o resultado e só reexecuta
/// quando uma dependência muda por `==`. As listas escopadas por ambiente
/// (`registrosDoAmbienteProvider` etc.) só trocam de identidade quando o
/// dado ou o ambiente muda — logo a memoização atravessa rebuilds. Ganho
/// extra: agregados compartilhados (ex. `desempenhoPorMateria`) são
/// calculados uma vez e lidos por vários cards, em vez de recalculados por
/// card.

/// Data de hoje truncada no dia — base estável para toda a matemática de
/// datas. Sendo um `Provider` cacheado, mantém a mesma identidade entre
/// rebuilds (o antigo `DateTime.now()` no `build` mudava a cada frame e
/// impediria a memoização dos agregados por data). Rola para o novo dia num
/// rebuild que invalide o provider (reabertura do app) — trade aceito.
final hojeProvider = Provider<DateTime>((ref) {
  final agora = DateTime.now();
  return DateTime(agora.year, agora.month, agora.day);
});

// ---------------------------------------------------------------------------
// Agregados no escopo do ambiente ativo
// ---------------------------------------------------------------------------

typedef ResumoGeral = ({
  int minutosHoje,
  int minutosSemana,
  int total,
  int streak,
  int streakCongelados,
  bool streakEmRisco,
  int metaSemana,
  double progressoMeta,
  // M-18: percentual sem teto, só para exibição — "44h45 de 24h" precisa
  // dizer 186%, não travar em "100%" (progressoMeta é clampado em 1.0 de
  // propósito, porque alimenta o `value` do LinearProgressIndicator, que
  // lança assertion error fora de [0,1]).
  double progressoMetaReal,
  int pendentes,
  int atrasadas,
  int qtdMaterias,
});

/// Números do "geralzão" (HeroGeral): dia/semana/total/streak, meta e
/// contagem de revisões pendentes/atrasadas.
final resumoGeralProvider = Provider<ResumoGeral>((ref) {
  final registros = ref.watch(registrosDoAmbienteProvider);
  final revisoes = ref.watch(revisoesDoAmbienteProvider);
  final materias = ref.watch(materiasDoAmbienteProvider);
  final hoje = ref.watch(hojeProvider);
  final plano = ref.watch(planejamentoProvider);
  final config = ref.watch(configuracoesProvider);

  final minutosSemana = StatsService.minutosNaSemana(registros, hoje);
  final metaSemana = PlanejamentoService.totalPlanejado(plano) > 0
      ? PlanejamentoService.totalPlanejado(plano)
      : config.metaSemanalMinutos;

  var pendentes = 0;
  var atrasadas = 0;
  for (final r in revisoes) {
    final status = r.statusEm(hoje);
    if (status == RevisaoStatus.atrasada) atrasadas++;
    if (status != RevisaoStatus.feita) pendentes++;
  }

  final streak = StatsService.streakDetalhado(registros, hoje);

  return (
    minutosHoje: StatsService.minutosNoDia(registros, hoje),
    minutosSemana: minutosSemana,
    total: registros.fold(0, (soma, r) => soma + r.minutos),
    streak: streak.dias,
    streakCongelados: streak.congelados,
    streakEmRisco: streak.emRisco,
    metaSemana: metaSemana,
    progressoMeta: metaSemana == 0
        ? 0.0
        : (minutosSemana / metaSemana).clamp(0.0, 1.0),
    progressoMetaReal: metaSemana == 0 ? 0.0 : minutosSemana / metaSemana,
    pendentes: pendentes,
    atrasadas: atrasadas,
    qtdMaterias: materias.length,
  );
});

/// Questões/acertos acumulados por matéria — compartilhado por
/// CardDesempenho, rankings (via [rankingsProvider]) e CardAlertas.
final desempenhoPorMateriaProvider =
    Provider<Map<String, ({int questoes, int acertos})>>(
      (ref) => StatsService.desempenhoPorMateria(
        ref.watch(registrosDoAmbienteProvider),
      ),
    );

/// Medição Elo por matéria numa passada única sobre os registros —
/// compartilhada por prontidão, alertas e diagnóstico (antes cada consumidor
/// re-filtrava a lista inteira por matéria: O(matérias × registros) cada).
final dominioPorMateriaProvider = Provider<Map<String, MedicaoDominio?>>(
  (ref) => DominioService.dominioPorMateria(
    ref.watch(registrosDoAmbienteProvider),
    ref.watch(materiasDoAmbienteProvider).map((m) => m.id),
    // Staleness: domínio de matéria parada há tempo regride ao neutro.
    referencia: ref.watch(hojeProvider),
  ),
);

/// Taxa de acerto geral ponderada (null sem questões).
final taxaAcertoGeralProvider = Provider<double?>(
  (ref) => StatsService.taxaAcertoGeral(ref.watch(registrosDoAmbienteProvider)),
);

/// True retention: taxa de acerto NAS REVISÕES (recall no vencimento), geral
/// e por matéria — mede se o intervalo de SR está calibrado. Escopo do
/// ambiente ativo. null geral quando ainda não há revisão concluída.
typedef TrueRetention = ({
  double? geral,
  Map<String, ({int questoes, int acertos, double taxa})> porMateria,
});

final trueRetentionProvider = Provider<TrueRetention>((ref) {
  final registros = ref.watch(registrosDoAmbienteProvider);
  return (
    geral: RetencaoService.geral(registros),
    porMateria: RetencaoService.porMateria(registros),
  );
});

/// Forecast de carga de revisão dos próximos 30 dias (escopo do ambiente) —
/// antecipa picos de backlog. Base do gráfico de barras "o que vem aí".
final forecastRevisaoProvider =
    Provider<List<({DateTime dia, int quantidade})>>((ref) {
  return RevisaoService.forecastCarga(
    ref.watch(revisoesDoAmbienteProvider),
    ref.watch(hojeProvider),
  );
});

typedef Rankings = ({
  ({String materiaId, int minutos})? maisEstudada,
  List<({String materiaId, int questoes, int acertos, double taxa})> ranking,
  ({int diaSemana, int minutos})? melhorDia,
});

/// Entradas do card Rankings (mais estudada, ranking de acertos, melhor dia).
final rankingsProvider = Provider<Rankings>((ref) {
  final registros = ref.watch(registrosDoAmbienteProvider);
  return (
    maisEstudada: InsightsService.maisEstudada(registros),
    ranking: InsightsService.rankingAcertos(registros),
    melhorDia: InsightsService.melhorDiaSemana(registros),
  );
});

/// "O que melhorar hoje" — recomendações acionáveis já ordenadas.
final insightsProvider = Provider<List<InsightAcao>>(
  (ref) => InsightsService.melhorarHoje(
    registros: ref.watch(registrosDoAmbienteProvider),
    materias: ref.watch(materiasDoAmbienteProvider),
    revisoes: ref.watch(revisoesDoAmbienteProvider),
    hoje: ref.watch(hojeProvider),
  ),
);

typedef Alertas = ({
  Map<String, int> atrasadasPorMateria,
  List<Materia> falsoDominio,
});

/// Alertas dinâmicos: revisões atrasadas por matéria + falso domínio.
final alertasProvider = Provider<Alertas>((ref) {
  final revisoes = ref.watch(revisoesDoAmbienteProvider);
  final materias = ref
      .watch(materiasDoAmbienteProvider)
      .where((m) => !m.arquivada)
      .toList();
  final hoje = ref.watch(hojeProvider);
  // Falso domínio pela MESMA medição Elo do ciclo/prontidão — a taxa
  // acumulada acusava para sempre um erro de meses atrás mesmo com o
  // desempenho recente já recuperado, contradizendo o resto do app.
  final medidos = ref.watch(dominioPorMateriaProvider);

  final atrasadasPorMateria = <String, int>{};
  for (final r in revisoes) {
    if (r.statusEm(hoje) == RevisaoStatus.atrasada) {
      atrasadasPorMateria[r.materiaId] =
          (atrasadasPorMateria[r.materiaId] ?? 0) + 1;
    }
  }

  final falsoDominio = materias
      .where(
        (m) =>
            PlanejamentoService.diagnostico(m.intimidade, medidos[m.id]) ==
            DiagnosticoMateria.falsoDominio,
      )
      .toList();

  return (atrasadasPorMateria: atrasadasPorMateria, falsoDominio: falsoDominio);
});

typedef SugestaoHoje = ({
  Materia materia,
  int deficitMinutos,
  Topico? proximoTopico,
});

/// Ciclo da semana → matéria com maior déficit → próximo tópico da fronteira
/// do grafo. Null sem cronograma ou sem matéria em déficit. (É o
/// "cicloDaSemanaProvider" pedido na auditoria, já resolvido em sugestão.)
final sugestaoHojeProvider = Provider<SugestaoHoje?>((ref) {
  final plano = ref.watch(planejamentoProvider);
  final planejado = PlanejamentoService.totalPlanejado(plano);
  final materias = ref.watch(materiasDoAmbienteProvider);
  if (planejado == 0 || materias.isEmpty) return null;

  final registros = ref.watch(registrosDoAmbienteProvider);
  final hoje = ref.watch(hojeProvider);
  final alvo = PlanejamentoService.cicloPorUtilidade(
    planejado,
    materias,
    registros,
    referencia: hoje,
  );
  final feito = StatsService.minutosPorMateria(
    registros,
    de: StatsService.inicioDaSemana(hoje),
    ate: hoje,
  );

  String? sugestaoId;
  var maiorDeficit = 0;
  for (final e in alvo.entries) {
    final deficit = e.value - (feito[e.key] ?? 0);
    if (deficit > maiorDeficit) {
      maiorDeficit = deficit;
      sugestaoId = e.key;
    }
  }
  if (sugestaoId == null) return null;
  final materia = materias.where((m) => m.id == sugestaoId).firstOrNull;
  if (materia == null) return null;

  final topicosDaMateria = ref
      .watch(topicosProvider)
      .where((t) => t.materiaId == materia.id)
      .toList();
  final proximoTopico = MapaEstudosService.fronteira(
    topicosDaMateria,
    registros,
  ).firstOrNull;

  return (
    materia: materia,
    deficitMinutos: maiorDeficit,
    proximoTopico: proximoTopico,
  );
});

typedef PlanoLinha = ({String rotulo, int planejado, int feito});
typedef PlanoResumo = ({
  bool temCronograma,
  int metaSemanalMinutos,
  List<PlanoLinha> linhas,
  bool metaSemanaBatida,
  DateTime inicioSemana,
});

/// Planejado vs feito vs restante em semana/mês/ano.
final planoProvider = Provider<PlanoResumo>((ref) {
  final plano = ref.watch(planejamentoProvider);
  final config = ref.watch(configuracoesProvider);
  final registros = ref.watch(registrosDoAmbienteProvider);
  final hoje = ref.watch(hojeProvider);
  final temCronograma = PlanejamentoService.totalPlanejado(plano) > 0;

  final inicioSemana = StatsService.inicioDaSemana(hoje);
  final fimSemana = DateTime(
    inicioSemana.year,
    inicioSemana.month,
    inicioSemana.day + 6,
  );
  final inicioMes = DateTime(hoje.year, hoje.month, 1);
  final fimMes = DateTime(hoje.year, hoje.month + 1, 0);
  final inicioAno = DateTime(hoje.year, 1, 1);
  final fimAno = DateTime(hoje.year, 12, 31);

  int planejadoEm(DateTime de, DateTime ate) {
    if (temCronograma) {
      return PlanejamentoService.planejadoEntre(plano, de, ate);
    }
    final dias = ate.difference(de).inDays + 1;
    return (config.metaSemanalMinutos * dias / 7).round();
  }

  final linhas = <PlanoLinha>[
    (
      rotulo: 'Semana',
      planejado: planejadoEm(inicioSemana, fimSemana),
      feito: StatsService.minutosNaSemana(registros, hoje),
    ),
    (
      rotulo: 'Mês',
      planejado: planejadoEm(inicioMes, fimMes),
      feito: StatsService.minutosNoMes(registros, hoje),
    ),
    (
      rotulo: 'Ano',
      planejado: planejadoEm(inicioAno, fimAno),
      feito: StatsService.minutosNoAno(registros, hoje.year),
    ),
  ];
  final semana = linhas.first;

  return (
    temCronograma: temCronograma,
    metaSemanalMinutos: config.metaSemanalMinutos,
    linhas: linhas,
    metaSemanaBatida: semana.planejado > 0 && semana.feito >= semana.planejado,
    inicioSemana: inicioSemana,
  );
});

typedef TilesResumoDados = ({
  int mes,
  int ano,
  int ontem,
  int media,
  int maximo,
  double? ritmo,
});

/// Tiles complementares (mês/ano/ontem/média/melhor dia/ritmo).
final tilesResumoProvider = Provider<TilesResumoDados>((ref) {
  final registros = ref.watch(registrosDoAmbienteProvider);
  final hoje = ref.watch(hojeProvider);
  final ontem = DateTime(hoje.year, hoje.month, hoje.day - 1);
  final resumo = StatsService.resumoDiario(registros);
  return (
    mes: StatsService.minutosNoMes(registros, hoje),
    ano: StatsService.minutosNoAno(registros, hoje.year),
    ontem: StatsService.minutosNoDia(registros, ontem),
    media: resumo.media,
    maximo: resumo.maximo,
    ritmo: StatsService.paginasPorHoraGeral(registros),
  );
});

/// Comparativo mês corrente vs mesmo trecho do mês anterior (MoM,
/// parcial-vs-parcial) — base da seta de variação no tile "Mês".
final comparativoMensalProvider = Provider<Comparativo>((ref) {
  return StatsService.comparativoMensal(
    ref.watch(registrosDoAmbienteProvider),
    ref.watch(hojeProvider),
  );
});

/// Comparativo ano corrente vs mesmo trecho do ano anterior (YoY,
/// parcial-vs-parcial) — base da seta de variação no tile "Ano".
final comparativoAnualProvider = Provider<Comparativo>((ref) {
  return StatsService.comparativoAnual(
    ref.watch(registrosDoAmbienteProvider),
    ref.watch(hojeProvider),
  );
});

typedef AnosResumo = ({Map<int, int> porAno, int total, int projecao, int ano});

/// Horas acumuladas por ano + projeção do ano corrente.
final anosProvider = Provider<AnosResumo>((ref) {
  final registros = ref.watch(registrosDoAmbienteProvider);
  final hoje = ref.watch(hojeProvider);
  final porAno = StatsService.minutosPorAno(registros);
  return (
    porAno: porAno,
    total: porAno.values.fold(0, (a, b) => a + b),
    projecao: StatsService.projecaoAno(registros, hoje),
    ano: hoje.year,
  );
});

typedef ProntidaoResumo = ({
  DateTime dataProva,
  int diasAteProva,
  double prontidaoHoje,
  double prontidaoProva,
  double prontidaoAjustada,
  double coberturaConfiavel,
  int minutosSemanais,
  List<({Materia materia, double projetado})> emRisco,
  List<Materia> semMedicao,
});

/// Prontidão para a prova (a agregação mais cara do dashboard: projeta o
/// domínio semana a semana). Null sem ambiente ativo com data de prova ou
/// sem matérias/medição suficiente.
final prontidaoProvider = Provider<ProntidaoResumo?>((ref) {
  final ambiente = ref.watch(ambienteAtivoProvider);
  final dataProva = ambiente?.dataProva;
  if (ambiente == null || dataProva == null) return null;

  final materias = ref
      .watch(materiasDoAmbienteProvider)
      .where((m) => !m.arquivada)
      .toList();
  if (materias.isEmpty) return null;

  final plano = ref.watch(planejamentoProvider);
  final hoje = ref.watch(hojeProvider);

  final diasAteProva = DateTime(
    dataProva.year,
    dataProva.month,
    dataProva.day,
  ).difference(DateTime(hoje.year, hoje.month, hoje.day)).inDays;
  final minutosSemanais = PlanejamentoService.totalPlanejado(plano);

  final medidos = ref.watch(dominioPorMateriaProvider);
  final dominiosHoje = ProntidaoService.dominiosAtuais(materias, medidos);
  final projetados = ProntidaoService.projetarDominios(
    materias: materias,
    dominiosHoje: dominiosHoje,
    minutosSemanais: minutosSemanais,
    diasAteProva: diasAteProva,
  );
  final prontidaoHoje = ProntidaoService.prontidao(materias, dominiosHoje);
  final prontidaoProva = ProntidaoService.prontidao(materias, projetados);
  if (prontidaoHoje == null || prontidaoProva == null) return null;
  // Ajustada ao risco (penaliza dispersão) + % do peso com Elo confiável —
  // a projeção honesta que o número único escondia (M2).
  final ajustada =
      ProntidaoService.prontidaoAjustada(materias, projetados) ?? prontidaoProva;
  final cobertura = ProntidaoService.coberturaConfiavel(materias, medidos);

  return (
    dataProva: dataProva,
    diasAteProva: diasAteProva,
    prontidaoHoje: prontidaoHoje,
    prontidaoProva: prontidaoProva,
    prontidaoAjustada: ajustada,
    coberturaConfiavel: cobertura,
    minutosSemanais: minutosSemanais,
    emRisco: ProntidaoService.materiasEmRisco(materias, projetados),
    semMedicao: ProntidaoService.semMedicao(materias, medidos),
  );
});

// ---------------------------------------------------------------------------
// Dados dos gráficos (agregação memoizada, o desenho fica no widget)
// ---------------------------------------------------------------------------

typedef MinutosPorMateria = List<({String materiaId, int minutos})>;

/// Minutos da semana por matéria, só matérias com estudo, maior primeiro.
final barrasSemanaProvider = Provider<MinutosPorMateria>((ref) {
  final registros = ref.watch(registrosDoAmbienteProvider);
  final hoje = ref.watch(hojeProvider);
  final inicio = StatsService.inicioDaSemana(hoje);
  final porMateria = StatsService.minutosPorMateria(
    registros,
    de: inicio,
    ate: hoje,
  );
  return [
    for (final e in porMateria.entries)
      if (e.value > 0) (materiaId: e.key, minutos: e.value),
  ]..sort((a, b) => b.minutos.compareTo(a.minutos));
});

/// Série diária dos últimos 14 dias para a linha de evolução.
final serieEvolucaoProvider = Provider<List<({DateTime dia, int minutos})>>(
  (ref) => StatsService.serieDiaria(
    ref.watch(registrosDoAmbienteProvider),
    ref.watch(hojeProvider),
    14,
  ),
);

/// Distribuição total por matéria (donut), só matérias com estudo.
final donutProvider = Provider<MinutosPorMateria>((ref) {
  final porMateria = StatsService.minutosPorMateria(
    ref.watch(registrosDoAmbienteProvider),
  );
  return [
    for (final e in porMateria.entries)
      if (e.value > 0) (materiaId: e.key, minutos: e.value),
  ]..sort((a, b) => b.minutos.compareTo(a.minutos));
});

// ---------------------------------------------------------------------------
// Agregados globais (independentes do ambiente por decisão de produto)
// ---------------------------------------------------------------------------

typedef GamificacaoResumo = ({
  ({int base, int bonusRevisoes, int bonusStreak, int total}) xp,
  ({int nivel, int xpNoNivel, int xpParaProximo}) progresso,
  List<BadgeStatus> badges,
});

/// XP/nível/badges — SEMPRE global (trocar de ambiente não rebaixa o nível).
final gamificacaoProvider = Provider<GamificacaoResumo>((ref) {
  final registros = ref.watch(registrosProvider);
  final revisoes = ref.watch(revisoesProvider);
  final hoje = ref.watch(hojeProvider);
  // Peso do edital vira multiplicador de dificuldade do XP (teto ×1.5).
  final pesoPorMateria = {
    for (final m in ref.watch(materiasProvider)) m.id: m.peso,
  };
  final xp = GamificacaoService.xpDetalhado(
    registros,
    revisoes,
    hoje,
    pesoPorMateria: pesoPorMateria,
  );
  return (
    xp: xp,
    progresso: GamificacaoService.progressoNivel(xp.total),
    badges: GamificacaoService.badges(registros, revisoes, hoje),
  );
});

/// Badges já vistas nesta execução — base da celebração de conquista NOVA
/// (as pré-existentes não celebram ao abrir o app). Null = ainda não
/// inicializado pelo primeiro build do card.
class BadgesVistasNotifier extends Notifier<Set<String>?> {
  @override
  Set<String>? build() => null;

  void registrar(Set<String> ids) => state = {...ids};
}

final badgesVistasProvider =
    NotifierProvider<BadgesVistasNotifier, Set<String>?>(
      BadgesVistasNotifier.new,
    );

/// Quests do dia derivadas do planejador (matéria em déficit, revisões
/// pendentes, mapa) — escopo do ambiente ativo, igual à sugestão de hoje.
final questsDoDiaProvider = Provider<List<QuestDia>>((ref) {
  final sugestao = ref.watch(sugestaoHojeProvider);
  return QuestsService.questsDoDia(
    hoje: ref.watch(hojeProvider),
    registros: ref.watch(registrosDoAmbienteProvider),
    revisoes: ref.watch(revisoesDoAmbienteProvider),
    materiaDeficitId: sugestao?.materia.id,
    materiaDeficitNome: sugestao?.materia.nome,
    temTopicos: ref.watch(topicosProvider).isNotEmpty,
  );
});

typedef HeatmapDados = ({
  Map<DateTime, int> minutosPorDia,
  Set<DateTime> diasCongelados,
  DateTime hoje,
});

/// Constância diária (escopo do ambiente ativo) + dias protegidos pelo
/// congelamento do streak — base do heatmap estilo calendário.
final heatmapDadosProvider = Provider<HeatmapDados>((ref) {
  final registros = ref.watch(registrosDoAmbienteProvider);
  final hoje = ref.watch(hojeProvider);
  return (
    minutosPorDia: StatsService.minutosPorDia(registros),
    diasCongelados: StatsService.diasCongeladosDoStreak(registros, hoje),
    hoje: hoje,
  );
});

/// Diagnóstico do dia: veredito único, honesto e acionável, derivado dos
/// agregados que o dashboard já calcula (nenhuma passada extra sobre os
/// registros — só composição de providers memoizados).
final diagnosticoProvider = Provider<Diagnostico>((ref) {
  final resumo = ref.watch(resumoGeralProvider);
  final serie = ref.watch(serieEvolucaoProvider);
  final retencao = ref.watch(trueRetentionProvider).geral;
  final taxa = ref.watch(taxaAcertoGeralProvider);
  final prontidao = ref.watch(prontidaoProvider);
  final alertas = ref.watch(alertasProvider);
  final sugestao = ref.watch(sugestaoHojeProvider);

  final diasEstudados14 = serie
      .where((d) => d.minutos >= DiagnosticoService.pisoMinutosDia)
      .length;

  return DiagnosticoService.gerar(
    totalMinutos: resumo.total,
    minutosHoje: resumo.minutosHoje,
    minutosSemana: resumo.minutosSemana,
    metaSemana: resumo.metaSemana,
    streak: resumo.streak,
    streakEmRisco: resumo.streakEmRisco,
    atrasadas: resumo.atrasadas,
    diasEstudados14: diasEstudados14,
    trueRetention: retencao,
    taxaAcertoGeral: taxa,
    prontidaoAjustada: prontidao?.prontidaoAjustada,
    diasAteProva: prontidao?.diasAteProva,
    falsoDominio: alertas.falsoDominio.length,
    materiaSugerida: sugestao?.materia.nome,
    deficitMinutos: sugestao?.deficitMinutos ?? 0,
  );
});

typedef AmbientesSemana = ({
  List<Ambiente> ambientes,
  Map<String, int> porAmbiente,
  int total,
});

/// Tempo da semana por ambiente (card só da visão consolidada).
final ambientesSemanaProvider = Provider<AmbientesSemana>((ref) {
  final ambientes = ref.watch(ambientesProvider);
  final materias = ref.watch(materiasProvider);
  final registros = ref.watch(registrosProvider);
  final hoje = ref.watch(hojeProvider);
  final inicioSemana = StatsService.inicioDaSemana(hoje);
  final porAmbiente = InsightsService.minutosPorAmbiente(
    registros,
    materias,
    de: inicioSemana,
    ate: hoje,
  );
  return (
    ambientes: ambientes,
    porAmbiente: porAmbiente,
    total: porAmbiente.values.fold(0, (a, b) => a + b),
  );
});
