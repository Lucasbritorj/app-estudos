import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/materia.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../dashboard_providers.dart';

/// Card com título padrão para envolver qualquer gráfico do dashboard.
class CardGrafico extends StatelessWidget {
  final String titulo;
  final Widget child;

  const CardGrafico({super.key, required this.titulo, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: LuminaText.cardTitle),
            const SizedBox(height: Spacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}

String _abreviar(String nome, [int limite = 8]) =>
    nome.length <= limite ? nome : '${nome.substring(0, limite - 1)}…';

class BarrasSemana extends ConsumerWidget {
  const BarrasSemana({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linhas = ref.watch(barrasSemanaProvider);
    final materiasPorId = {
      for (final m in ref.watch(materiasDoAmbienteProvider)) m.id: m,
    };

    if (linhas.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'Sem estudo nesta semana',
            style: TextStyle(color: VizColors.muted),
          ),
        ),
      );
    }

    final maxMinutos = linhas
        .map((e) => e.minutos)
        .reduce((a, b) => a > b ? a : b);

    final resumoA11y = linhas
        .map(
          (e) =>
              '${materiasPorId[e.materiaId]?.nome ?? '—'} ${formatarMinutos(e.minutos)}',
        )
        .join(', ');

    return Semantics(
      container: true,
      label: 'Horas da semana por matéria: $resumoA11y',
      // fl_chart não expõe semântica própria, mas os rótulos dos eixos SÃO
      // widgets de texto reais — sem isto o leitor varria "AFO", "40min",
      // "Penal", "30min" soltos por baixo do resumo já falado acima.
      excludeSemantics: true,
      child: SizedBox(
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
                  const FlLine(color: VizColors.baseline, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 44,
                  getTitlesWidget: (valor, meta) {
                    final i = valor.toInt();
                    if (i < 0 || i >= linhas.length) return const SizedBox();
                    final materia = materiasPorId[linhas[i].materiaId];
                    // Rótulo direto: nome + valor, identidade nunca só pela cor.
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        children: [
                          Text(
                            _abreviar(materia?.nome ?? '—'),
                            style: const TextStyle(
                              color: VizColors.inkSecondary,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            formatarMinutos(linhas[i].minutos),
                            style: const TextStyle(
                              color: VizColors.muted,
                              fontSize: 10,
                            ),
                          ),
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
                      toY: linhas[i].minutos.toDouble(),
                      width: 18,
                      color: corDaSerie(
                        materiasPorId[linhas[i].materiaId]?.corSlot ?? 0,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class LinhaEvolucao extends ConsumerWidget {
  const LinhaEvolucao({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serie = ref.watch(serieEvolucaoProvider);
    final horas = serie.map((p) => p.minutos / 60.0).toList();
    final maxHoras = horas.reduce((a, b) => a > b ? a : b);
    final tetoY = maxHoras < 1 ? 1.0 : maxHoras * 1.2;
    final totalMinutos = serie.fold(0, (s, p) => s + p.minutos);

    return Semantics(
      container: true,
      label:
          'Evolução dos últimos 14 dias: '
          '${formatarMinutos(totalMinutos)} no total, '
          'pico de ${formatarDecimal(maxHoras)} horas num dia',
      // Idem BarrasSemana: sem isto os rótulos do eixo ("dd/MM", "Nh") e o
      // tooltip de toque do fl_chart viram ruído solto atrás do resumo.
      excludeSemantics: true,
      child: SizedBox(
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
                  const FlLine(color: VizColors.baseline, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: (tetoY / 3).clamp(0.5, double.infinity),
                  getTitlesWidget: (v, meta) => Text(
                    '${v.toStringAsFixed(v < 2 ? 1 : 0)}h',
                    style: const TextStyle(
                      color: VizColors.muted,
                      fontSize: 10,
                    ),
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
                      child: Text(
                        formatarDiaMes(serie[i].dia),
                        style: const TextStyle(
                          color: VizColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => VizColors.surface,
                tooltipBorder: const BorderSide(color: VizColors.bordaSutil),
                getTooltipItems: (spots) => [
                  for (final s in spots)
                    LineTooltipItem(
                      '${formatarDecimal(s.y)}h',
                      const TextStyle(
                        color: VizColors.inkPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < serie.length; i++)
                    FlSpot(i.toDouble(), horas[i]),
                ],
                color: LuminaColors.safiraClara,
                barWidth: 2,
                isCurved: false,
                dotData: const FlDotData(show: false),
                // Área com gradiente safira→transparente: reforça a leitura
                // de magnitude acumulada sob a linha.
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      LuminaColors.safiraClara.withValues(alpha: 0.28),
                      LuminaColors.safiraClara.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acima deste nº de fatias a rosca fica ilegível (fatia fina, cor difícil
/// de distinguir) — [DonutDistribuicao] troca para barras horizontais.
const maxFatiasDonut = 5;

/// Acima deste total (100h) o rótulo "NNNNh MMmin" de [formatarMinutos] fica
/// longo demais para caber no miolo da rosca — troca pro formato compacto.
const _limiteMinutosCompacto = 6000;

String _formatarDuracao(int minutos) => minutos >= _limiteMinutosCompacto
    ? formatarHorasCompacto(minutos)
    : formatarMinutos(minutos);

class DonutDistribuicao extends ConsumerWidget {
  const DonutDistribuicao({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linhas = ref.watch(donutProvider);
    final materiasPorId = {
      for (final m in ref.watch(materiasDoAmbienteProvider)) m.id: m,
    };
    final total = linhas.fold(0, (soma, e) => soma + e.minutos);

    if (total == 0) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: Text('Sem dados', style: TextStyle(color: VizColors.muted)),
        ),
      );
    }

    final resumoA11y = linhas
        .map(
          (e) =>
              '${materiasPorId[e.materiaId]?.nome ?? '—'} '
              '${(e.minutos * 100 / total).toStringAsFixed(0)}%',
        )
        .join(', ');
    // Rótulo idêntico nos dois caminhos visuais (rosca ou barras) — só o
    // desenho muda conforme a quantidade de fatias.
    final rotuloA11y =
        'Distribuição total por matéria, '
        '${formatarMinutos(total)}: $resumoA11y';
    final usarBarras = linhas.length > maxFatiasDonut;

    return Column(
      children: [
        Semantics(
          container: true,
          label: rotuloA11y,
          // Some com a leitura da rosca (PieChart) OU das barras/legenda por
          // baixo — o resumo com todos os nomes+percentuais já está no
          // label acima, ler os dois é duplicar a mesma informação 2x.
          excludeSemantics: true,
          child: usarBarras
              ? _BarrasDistribuicao(
                  linhas: linhas,
                  materiasPorId: materiasPorId,
                  total: total,
                )
              : SizedBox(
                  height: 180,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          centerSpaceRadius: 52,
                          sectionsSpace: 2,
                          sections: [
                            for (final e in linhas)
                              PieChartSectionData(
                                value: e.minutos.toDouble(),
                                color: corDaSerie(
                                  materiasPorId[e.materiaId]?.corSlot ?? 0,
                                ),
                                radius: 22,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      // Furo de 104px (centerSpaceRadius 52); com total
                      // >=100h o texto vira compacto (_formatarDuracao) e,
                      // mesmo assim, o FittedBox encolhe em vez de estourar.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatarDuracao(total),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: VizColors.inkPrimary),
                            ),
                            const Text(
                              'total',
                              style: TextStyle(
                                color: VizColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        // Legenda separada só faz sentido junto da rosca (cor -> matéria);
        // a lista de barras já embute nome + valor + percentual por linha.
        if (!usarBarras) ...[
          const SizedBox(height: 12),
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
                        color: corDaSerie(
                          materiasPorId[e.materiaId]?.corSlot ?? 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${materiasPorId[e.materiaId]?.nome ?? '—'} · '
                      '${(e.minutos * 100 / total).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: VizColors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Substituto da rosca acima de [maxFatiasDonut] fatias: uma barra
/// horizontal por matéria (maior primeiro — `donutProvider` já ordena
/// desc), sempre com nome + valor + percentual em texto, nunca só cor.
class _BarrasDistribuicao extends StatelessWidget {
  final MinutosPorMateria linhas;
  final Map<String, Materia> materiasPorId;
  final int total;

  const _BarrasDistribuicao({
    required this.linhas,
    required this.materiasPorId,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final maxMinutos = linhas.first.minutos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total: ${_formatarDuracao(total)}',
          style: const TextStyle(color: VizColors.muted, fontSize: 11),
        ),
        const SizedBox(height: Spacing.sm),
        for (final e in linhas)
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: _BarraDistribuicao(
              nome: materiasPorId[e.materiaId]?.nome ?? '—',
              cor: corDaSerie(materiasPorId[e.materiaId]?.corSlot ?? 0),
              valor: _formatarDuracao(e.minutos),
              fracao: maxMinutos == 0 ? 0 : e.minutos / maxMinutos,
              percentual: total == 0 ? 0 : e.minutos * 100 / total,
            ),
          ),
      ],
    );
  }
}

class _BarraDistribuicao extends StatelessWidget {
  final String nome;
  final Color cor;
  final String valor;
  final double fracao;
  final double percentual;

  const _BarraDistribuicao({
    required this.nome,
    required this.cor,
    required this.valor,
    required this.fracao,
    required this.percentual,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: VizColors.inkSecondary,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Text(
              '$valor · ${percentual.toStringAsFixed(0)}%',
              style: const TextStyle(
                color: VizColors.inkPrimary,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fracao,
            minHeight: 8,
            backgroundColor: VizColors.gridline,
            color: cor,
          ),
        ),
      ],
    );
  }
}
