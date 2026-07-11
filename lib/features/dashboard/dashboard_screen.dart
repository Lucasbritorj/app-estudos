import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/materia.dart';
import '../../data/models/registro_hora.dart';
import '../../data/models/revisao.dart';
import '../../data/models/simulado.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/planejamento_repositorio.dart';
import '../../data/repositories/repositorios.dart';
import '../../app.dart';
import '../../domain/gamificacao_service.dart';
import '../../domain/insights_service.dart';
import '../../domain/planejamento_service.dart';
import '../../domain/stats_service.dart';
import '../ambientes/ambiente_selector.dart';
import '../registro/registro_form.dart';
import '../simulados/simulados_screen.dart';
import 'confete_leve.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registros = ref.watch(registrosDoAmbienteProvider);
    final materias = ref.watch(materiasDoAmbienteProvider);
    final ambienteAtivo = ref.watch(ambienteAtivoProvider);
    final hoje = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(ambienteAtivo?.nome ?? 'Visão Geral'),
        actions: const [AmbienteSelector(), SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Registro manual',
        onPressed: () => mostrarFormularioRegistro(context),
        child: const Icon(Icons.add),
      ),
      body: registros.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sem registros ainda.\nUse o cronômetro ou o botão + para lançar a primeira sessão.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ConteudoCentral(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _mensagemDoDia(hoje),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: VizColors.inkSecondary,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                  // Geralzão: tudo de relance, clicável, sem rolar.
                  _HeroGeral(hoje: hoje),
                  const SizedBox(height: 10),
                  _CardAlertas(hoje: hoje),
                  _CardMelhorarHoje(hoje: hoje),
                  const SizedBox(height: 10),
                  _CardRankings(
                      registros: registros, materias: materias, hoje: hoje),
                  const SizedBox(height: 10),
                  if (ambienteAtivo == null) ...[
                    _CardAmbientes(hoje: hoje),
                    const SizedBox(height: 10),
                  ],
                  _CardPlano(hoje: hoje),
                  const SizedBox(height: 10),
                  _CardSugestaoHoje(hoje: hoje),
                  const SizedBox(height: 10),
                  _CardDesempenho(registros: registros, materias: materias),
                  const SizedBox(height: 10),
                  _CardGrafico(
                    titulo: 'Horas da semana por matéria',
                    child: _BarrasSemana(
                        registros: registros,
                        materias: materias,
                        hoje: hoje),
                  ),
                  const SizedBox(height: 10),
                  _CardGrafico(
                    titulo: 'Evolução — últimos 14 dias',
                    child: _LinhaEvolucao(registros: registros, hoje: hoje),
                  ),
                  const SizedBox(height: 10),
                  _CardGrafico(
                    titulo: 'Distribuição total por matéria',
                    child: _DonutDistribuicao(
                        registros: registros, materias: materias),
                  ),
                  const SizedBox(height: 10),
                  _CardSimulados(),
                  const SizedBox(height: 10),
                  _CardGamificacao(hoje: hoje),
                  const SizedBox(height: 10),
                  _TilesResumo(registros: registros, hoje: hoje),
                  const SizedBox(height: 10),
                  _CardAnos(registros: registros, hoje: hoje),
                ],
              ),
            ),
    );
  }
}

const _mensagens = [
  'Constância vence intensidade. Um bloco de cada vez.',
  'A banca cobra o básico bem feito. Faça o básico hoje.',
  'Revisar vale mais que avançar sem reter.',
  'Quem mede, melhora. Registre a sessão.',
  'Edital não assusta quem tem ciclo.',
  'Hoje estudado é ansiedade de amanhã reduzida.',
  'Questões erradas hoje são pontos ganhos na prova.',
  'O streak não se quebra sozinho: proteja-o.',
  'Menos redes, mais horas líquidas.',
  'Aprovado é quem continua quando ninguém vê.',
  'Seu concorrente também está cansado.',
  'Página lida sem revisão é página emprestada.',
  'Disciplina é escolher o que você quer MAIS.',
  'Um dia de cada vez, com método.',
];

String _mensagemDoDia(DateTime d) {
  final diaDoAno = d.difference(DateTime(d.year, 1, 1)).inDays;
  return _mensagens[diaDoAno % _mensagens.length];
}

class _TilesResumo extends StatelessWidget {
  final List<RegistroHora> registros;
  final DateTime hoje;

  const _TilesResumo({required this.registros, required this.hoje});

  @override
  Widget build(BuildContext context) {
    final ontem = DateTime(hoje.year, hoje.month, hoje.day - 1);
    final resumo = StatsService.resumoDiario(registros);
    final ritmo = StatsService.paginasPorHoraGeral(registros);
    final total = registros.fold(0, (soma, r) => soma + r.minutos);
    final streak = StatsService.streakAtual(registros, hoje);

    final tiles = <(String, String, IconData?, Color?)>[
      (
        'Hoje',
        formatarMinutos(StatsService.minutosNoDia(registros, hoje)),
        null,
        null,
      ),
      (
        'Semana',
        formatarMinutos(StatsService.minutosNaSemana(registros, hoje)),
        null,
        null,
      ),
      (
        'Streak',
        '$streak ${streak == 1 ? 'dia' : 'dias'}',
        Icons.local_fire_department,
        LuminaColors.ouro,
      ),
      ('Total', formatarMinutos(total), null, null),
      (
        'Mês',
        formatarMinutos(StatsService.minutosNoMes(registros, hoje)),
        null,
        null,
      ),
      (
        'Ano',
        formatarMinutos(StatsService.minutosNoAno(registros, hoje.year)),
        null,
        null,
      ),
      (
        'Ontem',
        formatarMinutos(StatsService.minutosNoDia(registros, ontem)),
        null,
        null,
      ),
      ('Média/dia', formatarMinutos(resumo.media), null, null),
      ('Melhor dia', formatarMinutos(resumo.maximo), null, null),
      if (ritmo != null)
        ('Ritmo', '${ritmo.toStringAsFixed(1)} pág/h', null, null),
    ];

    // Extent máximo fixo: em tela larga entram 3-4 por linha COMPACTOS —
    // crossAxisCount fixo virava "quadros enormes" em 1900px (feedback).
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 210,
        mainAxisExtent: 62,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      children: [
        for (final (rotulo, valor, icone, corIcone) in tiles)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(rotulo,
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: VizColors.muted)),
                  Row(
                    children: [
                      if (icone != null) ...[
                        Icon(icone, size: 20, color: corIcone),
                        const SizedBox(width: 4),
                      ],
                      // Troca de valor com fade curto — vida sem exagero.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        child: Text(valor,
                            key: ValueKey(valor),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: VizColors.inkPrimary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "Geralzão": o dia inteiro de relance no topo — números, meta da semana
/// e atalhos. Tudo clicável (navega pelas abas via abaProvider).
class _HeroGeral extends ConsumerWidget {
  final DateTime hoje;

  const _HeroGeral({required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registros = ref.watch(registrosDoAmbienteProvider);
    final revisoes = ref.watch(revisoesDoAmbienteProvider);
    final materias = ref.watch(materiasDoAmbienteProvider);
    final plano = ref.watch(planejamentoProvider);
    final config = ref.watch(configuracoesProvider);

    final minutosHoje = StatsService.minutosNoDia(registros, hoje);
    final minutosSemana = StatsService.minutosNaSemana(registros, hoje);
    final streak = StatsService.streakAtual(registros, hoje);
    final total = registros.fold(0, (soma, r) => soma + r.minutos);

    final metaSemana = PlanejamentoService.totalPlanejado(plano) > 0
        ? PlanejamentoService.totalPlanejado(plano)
        : config.metaSemanalMinutos;
    final progressoMeta =
        metaSemana == 0 ? 0.0 : (minutosSemana / metaSemana).clamp(0.0, 1.0);

    var pendentes = 0;
    var atrasadas = 0;
    for (final r in revisoes) {
      final status = r.statusEm(hoje);
      if (status == RevisaoStatus.atrasada) atrasadas++;
      if (status != RevisaoStatus.feita) pendentes++;
    }

    void irPara(int aba) => ref.read(abaProvider.notifier).ir(aba);

    // Tile tintado (pastel adaptado ao escuro): cor identifica a métrica,
    // texto continua branco por contraste.
    Widget stat(String rotulo, String valor, Color tinta,
        {IconData? icone, VoidCallback? onTap}) {
      return Material(
        color: tinta.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: tinta.withValues(alpha: 0.28)),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icone != null) ...[
                      Icon(icone, size: 13, color: tinta),
                      const SizedBox(width: 4),
                    ],
                    Text(rotulo,
                        style: const TextStyle(
                            color: VizColors.muted, fontSize: 11)),
                    if (onTap != null) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_outward,
                          size: 11, color: VizColors.muted),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(valor,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: VizColors.inkPrimary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                stat('Hoje', formatarMinutos(minutosHoje),
                    LuminaColors.safiraClara,
                    onTap: () => irPara(Abas.cronometro)),
                stat('Semana', formatarMinutos(minutosSemana),
                    const Color(0xFF199E70),
                    onTap: () => irPara(Abas.cronometro)),
                stat('Streak', '$streak ${streak == 1 ? 'dia' : 'dias'}',
                    LuminaColors.ouro,
                    icone: Icons.local_fire_department),
                stat('Total', formatarMinutos(total),
                    const Color(0xFF9085E9)),
                stat(
                    'Revisões',
                    pendentes == 0
                        ? 'em dia'
                        : '$pendentes${atrasadas > 0 ? ' ($atrasadas atrasadas)' : ''}',
                    atrasadas > 0
                        ? _statusCritico
                        : (pendentes > 0 ? _statusAtencao : _statusBom),
                    icone: Icons.event_repeat,
                    onTap: () => irPara(Abas.revisoes)),
                stat('Matérias', '${materias.length}',
                    const Color(0xFFD55181),
                    onTap: () => irPara(Abas.materias)),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progressoMeta,
                      minHeight: 8,
                      backgroundColor: VizColors.gridline,
                      color: progressoMeta >= 1.0
                          ? LuminaColors.ouro
                          : LuminaColors.safiraClara,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Meta da semana: ${formatarMinutos(minutosSemana)} de '
                    '${formatarMinutos(metaSemana)} '
                    '(${(progressoMeta * 100).toStringAsFixed(0)}%)',
                    style: const TextStyle(
                        color: VizColors.muted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Registrar sessão'),
                    onPressed: () => mostrarFormularioRegistro(context),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.timer_outlined, size: 16),
                    label: const Text('Cronômetro'),
                    onPressed: () => irPara(Abas.cronometro),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardSugestaoHoje extends ConsumerWidget {
  final DateTime hoje;

  const _CardSugestaoHoje({required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plano = ref.watch(planejamentoProvider);
    final materias = ref.watch(materiasDoAmbienteProvider);
    final registros = ref.watch(registrosDoAmbienteProvider);
    final planejado = PlanejamentoService.totalPlanejado(plano);
    if (planejado == 0 || materias.isEmpty) return const SizedBox.shrink();

    final alvo = PlanejamentoService.distribuirPorPeso(planejado, materias);
    final feito = StatsService.minutosPorMateria(registros,
        de: StatsService.inicioDaSemana(hoje), ate: hoje);

    // Sugestão: a matéria com maior déficit no ciclo da semana.
    String? sugestaoId;
    var maiorDeficit = 0;
    for (final e in alvo.entries) {
      final deficit = e.value - (feito[e.key] ?? 0);
      if (deficit > maiorDeficit) {
        maiorDeficit = deficit;
        sugestaoId = e.key;
      }
    }
    if (sugestaoId == null) return const SizedBox.shrink();
    final materia =
        materias.where((m) => m.id == sugestaoId).firstOrNull;
    if (materia == null) return const SizedBox.shrink();

    return Card(
      child: ListTile(
        leading: CircleAvatar(
            radius: 10, backgroundColor: corDaSerie(materia.corSlot)),
        title: Text('Sugestão de hoje: ${materia.nome}'),
        subtitle: Text(
            'Faltam ${formatarMinutos(maiorDeficit)} no ciclo desta semana'),
        trailing: const Icon(Icons.arrow_forward, color: VizColors.muted),
        onTap: () => mostrarFormularioRegistro(context,
            materiaInicial: materia.id),
      ),
    );
  }
}

/// Cores de status reservadas — sempre com ícone/rótulo junto.
const _statusBom = Color(0xFF0CA30C);
const _statusAtencao = Color(0xFFFAB219);
const _statusCritico = Color(0xFFD03B3B);

/// Alertas dinâmicos: revisões atrasadas por matéria + falso domínio
/// (intimidade alta × acerto baixo). Some quando não há nada a alertar.
class _CardAlertas extends ConsumerWidget {
  final DateTime hoje;

  const _CardAlertas({required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revisoes = ref.watch(revisoesDoAmbienteProvider);
    final registros = ref.watch(registrosDoAmbienteProvider);
    final materias = ref
        .watch(materiasDoAmbienteProvider)
        .where((m) => !m.arquivada)
        .toList();
    final materiasPorId = {for (final m in materias) m.id: m};

    final atrasadasPorMateria = <String, int>{};
    for (final r in revisoes) {
      if (r.statusEm(hoje) == RevisaoStatus.atrasada) {
        atrasadasPorMateria[r.materiaId] =
            (atrasadasPorMateria[r.materiaId] ?? 0) + 1;
      }
    }

    final desempenho = StatsService.desempenhoPorMateria(registros);
    final falsoDominio = materias.where((m) {
      final d = desempenho[m.id];
      final taxa =
          d == null || d.questoes == 0 ? null : d.acertos / d.questoes;
      return PlanejamentoService.diagnostico(m.intimidade, taxa) ==
          DiagnosticoMateria.falsoDominio;
    }).toList();

    if (atrasadasPorMateria.isEmpty && falsoDominio.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in atrasadasPorMateria.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: _statusCritico),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Você tem ${e.value} '
                        '${e.value == 1 ? 'revisão atrasada' : 'revisões atrasadas'} '
                        'de ${materiasPorId[e.key]?.nome ?? 'matéria removida'}',
                        style: const TextStyle(
                            color: _statusCritico, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            for (final m in falsoDominio)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber,
                        size: 16, color: _statusAtencao),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Falso domínio em ${m.nome}: intimidade alta, '
                        'acerto abaixo de 75% — reforce questões e revisão',
                        style: const TextStyle(
                            color: _statusAtencao, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _CardDesempenho extends StatelessWidget {
  final List<RegistroHora> registros;
  final List<Materia> materias;

  const _CardDesempenho({required this.registros, required this.materias});

  @override
  Widget build(BuildContext context) {
    final desempenho = StatsService.desempenhoPorMateria(registros);
    if (desempenho.isEmpty) return const SizedBox.shrink();
    final materiasPorId = {for (final m in materias) m.id: m};
    final geral = StatsService.taxaAcertoGeral(registros);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Desempenho em questões',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: VizColors.inkSecondary)),
                const Spacer(),
                if (geral != null)
                  Text('${(geral * 100).toStringAsFixed(0)}% geral',
                      style: const TextStyle(color: VizColors.muted)),
              ],
            ),
            const SizedBox(height: 12),
            for (final e in desempenho.entries)
              _LinhaDesempenho(
                materia: materiasPorId[e.key],
                questoes: e.value.questoes,
                acertos: e.value.acertos,
              ),
          ],
        ),
      ),
    );
  }
}

class _LinhaDesempenho extends StatelessWidget {
  final Materia? materia;
  final int questoes;
  final int acertos;

  const _LinhaDesempenho(
      {required this.materia, required this.questoes, required this.acertos});

  @override
  Widget build(BuildContext context) {
    final taxa = questoes == 0 ? 0.0 : acertos / questoes;
    // Regra do alerta (protocolo Nexus): < 75% em disciplina = alerta vermelho.
    final (corStatus, icone, rotulo) = taxa < 0.75
        ? (_statusCritico, Icons.error_outline, 'reforçar')
        : taxa < 0.85
            ? (_statusAtencao, Icons.trending_up, 'evoluindo')
            : (_statusBom, Icons.check_circle_outline, 'dominado');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: corDaSerie(materia?.corSlot ?? 0),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(materia?.nome ?? '—')),
              Icon(icone, size: 14, color: corStatus),
              const SizedBox(width: 4),
              Text(
                '$acertos/$questoes · ${(taxa * 100).toStringAsFixed(0)}% $rotulo',
                style: TextStyle(color: corStatus, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: taxa,
              minHeight: 6,
              backgroundColor: VizColors.gridline,
              color: corStatus,
            ),
          ),
        ],
      ),
    );
  }
}

/// Planejado vs feito vs restante em semana, mês e ano (aba "Visão Geral").
/// Planejado vem do cronograma por dia da semana; sem cronograma, cai na
/// meta semanal das configurações (30h padrão) escalada pelo período.
class _CardPlano extends ConsumerWidget {
  final DateTime hoje;

  const _CardPlano({required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plano = ref.watch(planejamentoProvider);
    final config = ref.watch(configuracoesProvider);
    final registros = ref.watch(registrosDoAmbienteProvider);
    final temCronograma = PlanejamentoService.totalPlanejado(plano) > 0;

    final inicioSemana = StatsService.inicioDaSemana(hoje);
    final fimSemana = DateTime(
        inicioSemana.year, inicioSemana.month, inicioSemana.day + 6);
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

    final linhas = [
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
    if (linhas.every((l) => l.planejado == 0)) {
      return const SizedBox.shrink();
    }

    final semana = linhas.first;
    final metaSemanaBatida =
        semana.planejado > 0 && semana.feito >= semana.planejado;

    return ConfeteLeve(
      disparar: metaSemanaBatida,
      chave: 'meta-semana-${inicioSemana.toIso8601String()}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Plano de estudo',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: VizColors.inkSecondary)),
                  const Spacer(),
                  if (!temCronograma)
                    Text(
                        'meta ${formatarMinutos(config.metaSemanalMinutos)}/sem',
                        style: const TextStyle(
                            color: VizColors.muted, fontSize: 11)),
                  if (metaSemanaBatida) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.celebration,
                        size: 16, color: LuminaColors.ouro),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              for (final linha in linhas) ...[
                Row(
                  children: [
                    SizedBox(
                        width: 56,
                        child: Text(linha.rotulo,
                            style: const TextStyle(
                                color: VizColors.inkSecondary))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: linha.planejado == 0
                              ? 0
                              : (linha.feito / linha.planejado)
                                  .clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: VizColors.gridline,
                          color: seriesColors[0],
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 56, top: 2, bottom: 8),
                  child: Text(
                    '${formatarMinutos(linha.feito)} de ${formatarMinutos(linha.planejado)} · '
                    'restante ${formatarMinutos((linha.planejado - linha.feito).clamp(0, linha.planejado))}',
                    style: const TextStyle(
                        color: VizColors.muted, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Horas acumuladas por ano + projeção do ano corrente (abas "Visão Geral"
/// e "Cálculos" da planilha).
class _CardAnos extends StatelessWidget {
  final List<RegistroHora> registros;
  final DateTime hoje;

  const _CardAnos({required this.registros, required this.hoje});

  @override
  Widget build(BuildContext context) {
    final porAno = StatsService.minutosPorAno(registros);
    if (porAno.isEmpty) return const SizedBox.shrink();
    final total = porAno.values.fold(0, (a, b) => a + b);
    final projecao = StatsService.projecaoAno(registros, hoje);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Horas acumuladas por ano',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: VizColors.inkSecondary)),
            const SizedBox(height: 12),
            for (final e in porAno.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Text('${e.key}',
                        style:
                            const TextStyle(color: VizColors.inkSecondary)),
                    const Spacer(),
                    Text(formatarMinutos(e.value),
                        style: const TextStyle(color: VizColors.inkPrimary)),
                  ],
                ),
              ),
            const Divider(color: VizColors.gridline),
            Row(
              children: [
                const Text('Total',
                    style: TextStyle(color: VizColors.inkSecondary)),
                const Spacer(),
                Text(formatarMinutos(total),
                    style: const TextStyle(color: VizColors.inkPrimary)),
              ],
            ),
            if (projecao > (porAno[hoje.year] ?? 0))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Projeção ${hoje.year} no ritmo atual: ~${formatarMinutos(projecao)}',
                    style: const TextStyle(
                        color: VizColors.muted, fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}

const _iconesBadge = <String, IconData>{
  'primeira-sessao': Icons.flag,
  'dez-sessoes': Icons.repeat,
  'streak-7': Icons.local_fire_department,
  'streak-30': Icons.whatshot,
  'horas-50': Icons.timelapse,
  'horas-100': Icons.military_tech,
  'primeira-revisao': Icons.fact_check,
  'revisoes-em-dia': Icons.verified,
};

class _CardGamificacao extends ConsumerWidget {
  final DateTime hoje;

  const _CardGamificacao({required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // XP/nível/badges são do USUÁRIO, não do ambiente — sempre globais,
    // senão trocar de ambiente "rebaixaria" o nível.
    final registros = ref.watch(registrosProvider);
    final revisoes = ref.watch(revisoesProvider);
    final xp = GamificacaoService.xpDetalhado(registros, revisoes, hoje);
    final progresso = GamificacaoService.progressoNivel(xp.total);
    final badges = GamificacaoService.badges(registros, revisoes, hoje);
    const corConquista = LuminaColors.ouro;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Nível ${progresso.nivel}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: VizColors.inkPrimary)),
                const Spacer(),
                Text('${xp.total} XP',
                    style: const TextStyle(color: VizColors.muted)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progresso.xpParaProximo == 0
                    ? 0
                    : progresso.xpNoNivel / progresso.xpParaProximo,
                minHeight: 6,
                backgroundColor: VizColors.gridline,
                color: LuminaColors.ouro,
              ),
            ),
            const SizedBox(height: 4),
            Text(
                'Faltam ${progresso.xpParaProximo - progresso.xpNoNivel} XP para o nível ${progresso.nivel + 1} · '
                'estudo ${xp.base} + revisões ${xp.bonusRevisoes} + streak ${xp.bonusStreak}',
                style:
                    const TextStyle(color: VizColors.muted, fontSize: 11)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final badge in badges)
                  Tooltip(
                    message: badge.descricao,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          badge.conquistada
                              ? (_iconesBadge[badge.id] ?? Icons.star)
                              : Icons.lock_outline,
                          size: 16,
                          color: badge.conquistada
                              ? corConquista
                              : VizColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          badge.titulo,
                          style: TextStyle(
                            fontSize: 12,
                            color: badge.conquistada
                                ? VizColors.inkSecondary
                                : VizColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardGrafico extends StatelessWidget {
  final String titulo;
  final Widget child;

  const _CardGrafico({required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: VizColors.inkSecondary)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

String _abreviar(String nome, [int limite = 8]) =>
    nome.length <= limite ? nome : '${nome.substring(0, limite - 1)}…';

class _BarrasSemana extends StatelessWidget {
  final List<RegistroHora> registros;
  final List<Materia> materias;
  final DateTime hoje;

  const _BarrasSemana(
      {required this.registros, required this.materias, required this.hoje});

  @override
  Widget build(BuildContext context) {
    final inicio = StatsService.inicioDaSemana(hoje);
    final porMateria =
        StatsService.minutosPorMateria(registros, de: inicio, ate: hoje);
    final materiasPorId = {for (final m in materias) m.id: m};

    final linhas = porMateria.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (linhas.isEmpty) {
      return const SizedBox(
          height: 120,
          child: Center(
              child: Text('Sem estudo nesta semana',
                  style: TextStyle(color: VizColors.muted))));
    }

    final maxMinutos =
        linhas.map((e) => e.value).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxMinutos * 1.15,
          barTouchData: BarTouchData(enabled: true),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxMinutos / 3).clamp(15, double.infinity),
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: VizColors.gridline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (valor, meta) {
                  final i = valor.toInt();
                  if (i < 0 || i >= linhas.length) return const SizedBox();
                  final materia = materiasPorId[linhas[i].key];
                  // Rótulo direto: nome + valor, identidade nunca só pela cor.
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      children: [
                        Text(_abreviar(materia?.nome ?? '—'),
                            style: const TextStyle(
                                color: VizColors.inkSecondary, fontSize: 11)),
                        Text(formatarMinutos(linhas[i].value),
                            style: const TextStyle(
                                color: VizColors.muted, fontSize: 10)),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < linhas.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: linhas[i].value.toDouble(),
                    width: 18,
                    color: corDaSerie(
                        materiasPorId[linhas[i].key]?.corSlot ?? 0),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LinhaEvolucao extends StatelessWidget {
  final List<RegistroHora> registros;
  final DateTime hoje;

  const _LinhaEvolucao({required this.registros, required this.hoje});

  @override
  Widget build(BuildContext context) {
    final serie = StatsService.serieDiaria(registros, hoje, 14);
    final horas = serie.map((p) => p.minutos / 60.0).toList();
    final maxHoras = horas.reduce((a, b) => a > b ? a : b);
    final tetoY = maxHoras < 1 ? 1.0 : maxHoras * 1.2;

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: tetoY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (tetoY / 3).clamp(0.5, double.infinity),
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: VizColors.gridline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: (tetoY / 3).clamp(0.5, double.infinity),
                getTitlesWidget: (v, meta) => Text(
                  '${v.toStringAsFixed(v < 2 ? 1 : 0)}h',
                  style:
                      const TextStyle(color: VizColors.muted, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 4,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= serie.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(formatarDiaMes(serie[i].dia),
                        style: const TextStyle(
                            color: VizColors.muted, fontSize: 10)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: true),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < serie.length; i++)
                  FlSpot(i.toDouble(), horas[i]),
              ],
              color: seriesColors[0],
              barWidth: 2,
              isCurved: false,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// "O que melhorar hoje": recomendações acionáveis do InsightsService,
/// no escopo ativo. Insight com matéria vira atalho de registro.
class _CardMelhorarHoje extends ConsumerWidget {
  final DateTime hoje;

  const _CardMelhorarHoje({required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registros = ref.watch(registrosDoAmbienteProvider);
    final materias = ref.watch(materiasDoAmbienteProvider);
    final revisoes = ref.watch(revisoesDoAmbienteProvider);
    final acoes = InsightsService.melhorarHoje(
      registros: registros,
      materias: materias,
      revisoes: revisoes,
      hoje: hoje,
    );

    (IconData, Color) visual(TipoInsight tipo) => switch (tipo) {
          TipoInsight.revisao => (Icons.event_repeat, _statusCritico),
          TipoInsight.desempenho => (Icons.trending_down, _statusAtencao),
          TipoInsight.streak =>
            (Icons.local_fire_department, LuminaColors.ouro),
          TipoInsight.ritmo => (Icons.speed, VizColors.inkSecondary),
          TipoInsight.positivo => (Icons.check_circle_outline, _statusBom),
        };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('O que melhorar hoje',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: VizColors.inkSecondary)),
            const SizedBox(height: 8),
            for (final acao in acoes)
              InkWell(
                onTap: acao.materiaId == null
                    ? null
                    : () => mostrarFormularioRegistro(context,
                        materiaInicial: acao.materiaId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(visual(acao.tipo).$1,
                          size: 16, color: visual(acao.tipo).$2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(acao.mensagem,
                            style: const TextStyle(
                                color: VizColors.inkSecondary,
                                fontSize: 13)),
                      ),
                      if (acao.materiaId != null)
                        const Icon(Icons.arrow_forward,
                            size: 14, color: VizColors.muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const _nomesDiaSemana = [
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
  'domingo',
];

/// Rankings inteligentes: mais estudada, melhor/pior taxa, dia forte e
/// ranking de acertos por matéria (amostra mínima de 10 questões).
class _CardRankings extends StatelessWidget {
  final List<RegistroHora> registros;
  final List<Materia> materias;
  final DateTime hoje;

  const _CardRankings(
      {required this.registros, required this.materias, required this.hoje});

  @override
  Widget build(BuildContext context) {
    final nomes = {for (final m in materias) m.id: m};
    final maisEstudada = InsightsService.maisEstudada(registros);
    final ranking = InsightsService.rankingAcertos(registros);
    final melhorDia = InsightsService.melhorDiaSemana(registros);

    String nomeDe(String materiaId) => nomes[materiaId]?.nome ?? '—';

    final linhas = <(IconData, Color, String, String)>[
      if (maisEstudada != null && nomes.containsKey(maisEstudada.materiaId))
        (
          Icons.emoji_events,
          LuminaColors.ouro,
          'Mais estudada',
          '${nomeDe(maisEstudada.materiaId)} · '
              '${formatarMinutos(maisEstudada.minutos)}',
        ),
      if (ranking.isNotEmpty && nomes.containsKey(ranking.first.materiaId))
        (
          Icons.military_tech,
          _statusBom,
          'Maior taxa de acerto',
          '${nomeDe(ranking.first.materiaId)} · '
              '${(ranking.first.taxa * 100).toStringAsFixed(0)}%',
        ),
      if (ranking.length > 1 && nomes.containsKey(ranking.last.materiaId))
        (
          Icons.priority_high,
          _statusAtencao,
          'Menor taxa (foco sugerido)',
          '${nomeDe(ranking.last.materiaId)} · '
              '${(ranking.last.taxa * 100).toStringAsFixed(0)}%',
        ),
      if (melhorDia != null)
        (
          Icons.calendar_today,
          LuminaColors.safiraClara,
          'Dia em que você mais estuda',
          '${_nomesDiaSemana[melhorDia.diaSemana - 1]} · '
              '${formatarMinutos(melhorDia.minutos)}',
        ),
    ];
    if (linhas.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rankings',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: VizColors.inkSecondary)),
            const SizedBox(height: 10),
            for (final (icone, cor, rotulo, valor) in linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(icone, size: 16, color: cor),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(rotulo,
                            style: const TextStyle(
                                color: VizColors.inkSecondary,
                                fontSize: 13))),
                    Text(valor,
                        style: const TextStyle(
                            color: VizColors.inkPrimary, fontSize: 13)),
                  ],
                ),
              ),
            if (ranking.isNotEmpty) ...[
              const Divider(color: VizColors.gridline),
              const SizedBox(height: 4),
              const Text('Acertos por matéria (mín. 10 questões)',
                  style: TextStyle(color: VizColors.muted, fontSize: 11)),
              const SizedBox(height: 6),
              for (final linha in ranking)
                if (nomes.containsKey(linha.materiaId))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                            radius: 5,
                            backgroundColor: corDaSerie(
                                nomes[linha.materiaId]!.corSlot)),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(nomeDe(linha.materiaId),
                                style: const TextStyle(
                                    color: VizColors.inkSecondary,
                                    fontSize: 12))),
                        Text(
                          '${linha.acertos}✓ ${linha.questoes - linha.acertos}✗ · '
                          '${(linha.taxa * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: VizColors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Resumo por Ambiente (só na visão consolidada): tempo da semana em cada
/// ambiente, com participação relativa.
class _CardAmbientes extends ConsumerWidget {
  final DateTime hoje;

  const _CardAmbientes({required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ambientes = ref.watch(ambientesProvider);
    final materias = ref.watch(materiasProvider);
    final registros = ref.watch(registrosProvider);
    if (ambientes.length < 2) return const SizedBox.shrink();

    final inicioSemana = StatsService.inicioDaSemana(hoje);
    final porAmbiente = InsightsService.minutosPorAmbiente(
        registros, materias,
        de: inicioSemana, ate: hoje);
    final total = porAmbiente.values.fold(0, (a, b) => a + b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ambientes nesta semana',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: VizColors.inkSecondary)),
            const SizedBox(height: 10),
            if (total == 0)
              const Text('Sem estudo nesta semana',
                  style: TextStyle(color: VizColors.muted, fontSize: 12))
            else
              for (final ambiente in ambientes)
                if ((porAmbiente[ambiente.id] ?? 0) > 0) ...[
                  Row(
                    children: [
                      CircleAvatar(
                          radius: 5,
                          backgroundColor: corDaSerie(ambiente.corSlot)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(ambiente.nome,
                              style: const TextStyle(
                                  color: VizColors.inkSecondary,
                                  fontSize: 13))),
                      Text(
                          '${formatarMinutos(porAmbiente[ambiente.id]!)} · '
                          '${(porAmbiente[ambiente.id]! * 100 / total).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: VizColors.inkPrimary, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: porAmbiente[ambiente.id]! / total,
                      minHeight: 5,
                      backgroundColor: VizColors.gridline,
                      color: corDaSerie(ambiente.corSlot),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
          ],
        ),
      ),
    );
  }
}

/// Desempenho em simulados/provas — ISOLADO do estudo diário de propósito:
/// mesmas métricas (taxa, erros), mas prova não se mistura com sessão de
/// estudo em nenhum somatório. Some quando não há simulados.
class _CardSimulados extends ConsumerWidget {
  const _CardSimulados();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ativo = ref.watch(ambienteAtivoProvider);
    final simulados = ref
        .watch(simuladosProvider)
        .where((s) => ativo == null || s.ambienteId == ativo.id)
        .toList();
    if (simulados.isEmpty) return const SizedBox.shrink();

    // Repo já ordena por data desc; delta = último vs anterior.
    final ultimos = simulados.take(3).toList();
    final taxaAtual = simulados.first.taxaGeral;
    final taxaAnterior =
        simulados.length > 1 ? simulados[1].taxaGeral : null;
    final delta = (taxaAtual != null && taxaAnterior != null)
        ? (taxaAtual - taxaAnterior) * 100
        : null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SimuladosScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Simulados & Provas',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: VizColors.inkSecondary)),
                  const SizedBox(width: 8),
                  if (delta != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          delta >= 0
                              ? Icons.trending_up
                              : Icons.trending_down,
                          size: 16,
                          color:
                              delta >= 0 ? _statusBom : _statusCritico,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)} pp',
                          style: TextStyle(
                              fontSize: 12,
                              color: delta >= 0
                                  ? _statusBom
                                  : _statusCritico),
                        ),
                      ],
                    ),
                  const Spacer(),
                  const Text('ver todos',
                      style:
                          TextStyle(color: VizColors.muted, fontSize: 12)),
                  const Icon(Icons.arrow_forward,
                      size: 14, color: VizColors.muted),
                ],
              ),
              const SizedBox(height: 2),
              const Text('Métricas de prova — não somam no estudo diário',
                  style: TextStyle(color: VizColors.muted, fontSize: 11)),
              const SizedBox(height: 10),
              for (final s in ultimos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        s.tipo == TipoSimulado.prova
                            ? Icons.workspace_premium_outlined
                            : Icons.fact_check_outlined,
                        size: 15,
                        color: s.tipo == TipoSimulado.prova
                            ? LuminaColors.ouro
                            : LuminaColors.safiraClara,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: VizColors.inkSecondary,
                                fontSize: 13)),
                      ),
                      Text(
                        '${formatarDiaMes(s.data)} · '
                        '${s.totalAcertos}/${s.totalQuestoes}'
                        '${s.taxaGeral == null ? '' : ' · ${(s.taxaGeral! * 100).toStringAsFixed(0)}%'}'
                        '${s.minutosPorQuestao == null ? '' : ' · ${s.minutosPorQuestao!.toStringAsFixed(1)} min/q'}',
                        style: const TextStyle(
                            color: VizColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutDistribuicao extends StatelessWidget {
  final List<RegistroHora> registros;
  final List<Materia> materias;

  const _DonutDistribuicao(
      {required this.registros, required this.materias});

  @override
  Widget build(BuildContext context) {
    final porMateria = StatsService.minutosPorMateria(registros);
    final materiasPorId = {for (final m in materias) m.id: m};
    final linhas = porMateria.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = linhas.fold(0, (soma, e) => soma + e.value);

    if (total == 0) {
      return const SizedBox(
          height: 120,
          child: Center(
              child: Text('Sem dados',
                  style: TextStyle(color: VizColors.muted))));
    }

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 48,
                  sectionsSpace: 2,
                  sections: [
                    for (final e in linhas)
                      PieChartSectionData(
                        value: e.value.toDouble(),
                        color: corDaSerie(
                            materiasPorId[e.key]?.corSlot ?? 0),
                        radius: 22,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatarMinutos(total),
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: VizColors.inkPrimary)),
                  const Text('total',
                      style:
                          TextStyle(color: VizColors.muted, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Legenda: identidade + valor em texto, nunca só cor.
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final e in linhas)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          corDaSerie(materiasPorId[e.key]?.corSlot ?? 0),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${materiasPorId[e.key]?.nome ?? '—'} · '
                    '${(e.value * 100 / total).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: VizColors.inkSecondary, fontSize: 12),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
