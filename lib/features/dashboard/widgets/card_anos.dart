import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/registro_hora.dart';
import '../../../domain/stats_service.dart';

/// Horas acumuladas por ano + projeção do ano corrente (abas "Visão Geral"
/// e "Cálculos" da planilha).
class CardAnos extends StatelessWidget {
  final List<RegistroHora> registros;
  final DateTime hoje;

  const CardAnos({super.key, required this.registros, required this.hoje});

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
