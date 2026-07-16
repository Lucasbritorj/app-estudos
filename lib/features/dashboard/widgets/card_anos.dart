import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../dashboard_providers.dart';

/// Horas acumuladas por ano + projeção do ano corrente (abas "Visão Geral"
/// e "Cálculos" da planilha).
class CardAnos extends ConsumerWidget {
  const CardAnos({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(anosProvider);
    final porAno = dados.porAno;
    if (porAno.isEmpty) return const SizedBox.shrink();
    final total = dados.total;
    final projecao = dados.projecao;

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
            if (projecao > (porAno[dados.ano] ?? 0))
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Projeção ${dados.ano} no ritmo atual: ~${formatarMinutos(projecao)}',
                    style: const TextStyle(
                        color: VizColors.muted, fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }
}
