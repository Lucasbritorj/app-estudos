import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/registro_hora.dart';
import '../../../domain/stats_service.dart';

/// Tiles de números complementares. Hoje/Semana/Streak/Total moram no
/// HeroGeral — aqui entra só o que NÃO está no hero, sem duplicar métrica.
class TilesResumo extends StatelessWidget {
  final List<RegistroHora> registros;
  final DateTime hoje;

  const TilesResumo({super.key, required this.registros, required this.hoje});

  @override
  Widget build(BuildContext context) {
    final ontem = DateTime(hoje.year, hoje.month, hoje.day - 1);
    final resumo = StatsService.resumoDiario(registros);
    final ritmo = StatsService.paginasPorHoraGeral(registros);

    final tiles = <(String, String)>[
      ('Mês', formatarMinutos(StatsService.minutosNoMes(registros, hoje))),
      (
        'Ano',
        formatarMinutos(StatsService.minutosNoAno(registros, hoje.year)),
      ),
      ('Ontem', formatarMinutos(StatsService.minutosNoDia(registros, ontem))),
      ('Média/dia', formatarMinutos(resumo.media)),
      ('Melhor dia', formatarMinutos(resumo.maximo)),
      if (ritmo != null) ('Ritmo', '${ritmo.toStringAsFixed(1)} pág/h'),
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
        for (final (rotulo, valor) in tiles)
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
                  // Troca de valor com fade curto — vida sem exagero.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(valor,
                        key: ValueKey(valor),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: VizColors.inkPrimary,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
