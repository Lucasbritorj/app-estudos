import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
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
            Text(
              titulo,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: VizColors.inkSecondary),
            ),
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
                  const FlLine(color: VizColors.gridline, strokeWidth: 1),
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
          'pico de ${maxHoras.toStringAsFixed(1)} horas num dia',
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
                  const FlLine(color: VizColors.gridline, strokeWidth: 1),
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
      ),
    );
  }
}

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

    return Column(
      children: [
        Semantics(
          container: true,
          label:
              'Distribuição total por matéria, '
              '${formatarMinutos(total)}: $resumoA11y',
          child: SizedBox(
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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formatarMinutos(total),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: VizColors.inkPrimary,
                      ),
                    ),
                    const Text(
                      'total',
                      style: TextStyle(color: VizColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
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
    );
  }
}
