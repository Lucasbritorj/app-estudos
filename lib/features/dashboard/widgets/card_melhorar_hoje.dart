import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/insights_service.dart';
import '../../registro/registro_form.dart';
import '../dashboard_providers.dart';

/// "O que melhorar hoje": recomendações acionáveis do InsightsService,
/// no escopo ativo. Insight com matéria vira atalho de registro.
class CardMelhorarHoje extends ConsumerWidget {
  const CardMelhorarHoje({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acoes = ref.watch(insightsProvider);

    (IconData, Color) visual(TipoInsight tipo) => switch (tipo) {
          TipoInsight.revisao => (Icons.event_repeat, StatusColors.critico),
          TipoInsight.desempenho =>
            (Icons.trending_down, StatusColors.atencao),
          TipoInsight.streak =>
            (Icons.local_fire_department, LuminaColors.ouro),
          TipoInsight.ritmo => (Icons.speed, VizColors.inkSecondary),
          TipoInsight.positivo =>
            (Icons.check_circle_outline, StatusColors.bom),
        };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('O que melhorar hoje',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: VizColors.inkSecondary)),
            const SizedBox(height: 8),
            for (final acao in acoes)
              InkWell(
                onTap: acao.materiaId == null
                    ? null
                    : () => mostrarFormularioRegistro(context,
                        materiaInicial: acao.materiaId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(visual(acao.tipo).$1,
                          size: 16, color: visual(acao.tipo).$2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(acao.mensagem,
                            style: const TextStyle(
                                color: VizColors.inkSecondary,
                                fontSize: 13)),
                      ),
                      if (acao.materiaId != null)
                        const Icon(Icons.arrow_forward,
                            size: 14, color: VizColors.muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
