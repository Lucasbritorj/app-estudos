import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/repositories/repositorios.dart';
import '../../../domain/insights_service.dart';
import '../../../domain/stats_service.dart';

/// Resumo por Ambiente (só na visão consolidada): tempo da semana em cada
/// ambiente, com participação relativa.
class CardAmbientes extends ConsumerWidget {
  final DateTime hoje;

  const CardAmbientes({super.key, required this.hoje});

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
