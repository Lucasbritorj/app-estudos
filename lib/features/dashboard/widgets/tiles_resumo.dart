import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../dashboard_providers.dart';

/// Tiles de números complementares. Hoje/Semana/Streak/Total moram no
/// HeroGeral — aqui entra só o que NÃO está no hero, sem duplicar métrica.
class TilesResumo extends ConsumerWidget {
  const TilesResumo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(tilesResumoProvider);
    final ritmo = dados.ritmo;

    final tiles = <(String, String)>[
      ('Mês', formatarMinutos(dados.mes)),
      ('Ano', formatarMinutos(dados.ano)),
      ('Ontem', formatarMinutos(dados.ontem)),
      ('Média/dia', formatarMinutos(dados.media)),
      ('Melhor dia', formatarMinutos(dados.maximo)),
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
                  Text(
                    rotulo,
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: VizColors.muted),
                  ),
                  // Troca de valor com fade curto — vida sem exagero.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(
                      valor,
                      key: ValueKey(valor),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: VizColors.inkPrimary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
