import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../../../data/repositories/configuracoes_repositorio.dart';
import '../../../data/repositories/planejamento_repositorio.dart';
import '../../../domain/planejamento_service.dart';
import '../../../domain/stats_service.dart';
import '../confete_leve.dart';

/// Planejado vs feito vs restante em semana, mês e ano (aba "Visão Geral").
/// Planejado vem do cronograma por dia da semana; sem cronograma, cai na
/// meta semanal das configurações (30h padrão) escalada pelo período.
class CardPlano extends ConsumerWidget {
  final DateTime hoje;

  const CardPlano({super.key, required this.hoje});

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
