import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../confete_leve.dart';
import '../dashboard_providers.dart';

/// Planejado vs feito vs restante em semana, mês e ano (aba "Visão Geral").
/// Planejado vem do cronograma por dia da semana; sem cronograma, cai na
/// meta semanal das configurações (30h padrão) escalada pelo período.
class CardPlano extends ConsumerWidget {
  const CardPlano({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(planoProvider);
    final temCronograma = dados.temCronograma;
    final linhas = dados.linhas;
    if (linhas.every((l) => l.planejado == 0)) {
      return const SizedBox.shrink();
    }

    final metaSemanaBatida = dados.metaSemanaBatida;

    return ConfeteLeve(
      disparar: metaSemanaBatida,
      chave: 'meta-semana-${dados.inicioSemana.toIso8601String()}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Plano de estudo',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: VizColors.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  if (!temCronograma)
                    Text(
                      'meta ${formatarMinutos(dados.metaSemanalMinutos)}/sem',
                      style: const TextStyle(
                        color: VizColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  if (metaSemanaBatida) ...[
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.celebration,
                      size: 16,
                      color: LuminaColors.ouro,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              for (final linha in linhas) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(
                        linha.rotulo,
                        style: const TextStyle(color: VizColors.inkSecondary),
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: linha.planejado == 0
                              ? 0
                              : (linha.feito / linha.planejado).clamp(0.0, 1.0),
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
                      color: VizColors.muted,
                      fontSize: 11,
                    ),
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
