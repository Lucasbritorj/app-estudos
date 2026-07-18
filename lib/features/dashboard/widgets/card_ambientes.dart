import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_cor.dart';
import '../../../core/utils/formatters.dart';
import '../dashboard_providers.dart';

/// Resumo por Ambiente (só na visão consolidada): tempo da semana em cada
/// ambiente, com participação relativa.
class CardAmbientes extends ConsumerWidget {
  const CardAmbientes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(ambientesSemanaProvider);
    final ambientes = dados.ambientes;
    if (ambientes.length < 2) return const SizedBox.shrink();
    final porAmbiente = dados.porAmbiente;
    final total = dados.total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ambientes nesta semana',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: VizColors.inkSecondary),
            ),
            const SizedBox(height: 10),
            if (total == 0)
              const Text(
                'Sem estudo nesta semana',
                style: TextStyle(color: VizColors.muted, fontSize: 12),
              )
            else
              for (final ambiente in ambientes)
                if ((porAmbiente[ambiente.id] ?? 0) > 0) ...[
                  Row(
                    children: [
                      AvatarCor(slot: ambiente.corSlot, raio: 5),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ambiente.nome,
                          style: const TextStyle(
                            color: VizColors.inkSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '${formatarMinutos(porAmbiente[ambiente.id]!)} · '
                        '${(porAmbiente[ambiente.id]! * 100 / total).toStringAsFixed(0)}%',
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
