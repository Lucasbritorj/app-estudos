import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/diagnostico_service.dart';
import '../dashboard_providers.dart';

/// Veredito do dia: um card só, honesto e acionável — o "espelho" do
/// dashboard. Vive no topo (abaixo dos alertas) porque a primeira pergunta
/// de quem abre o app é "como eu realmente estou?", não "quantas horas fiz".
/// Some no estado semDados (o EstadoVazio do dashboard já cobre o onboarding).
class CardDiagnostico extends ConsumerWidget {
  const CardDiagnostico({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(diagnosticoProvider);
    if (d.nivel == NivelDiagnostico.semDados) return const SizedBox.shrink();

    final (cor, icone) = switch (d.nivel) {
      NivelDiagnostico.critico => (StatusColors.critico, Icons.crisis_alert),
      NivelDiagnostico.atencao => (StatusColors.atencao, Icons.error_outline),
      NivelDiagnostico.constante => (
        LuminaColors.safiraClara,
        Icons.trending_up,
      ),
      NivelDiagnostico.forte => (StatusColors.bom, Icons.verified_outlined),
      NivelDiagnostico.semDados => (VizColors.muted, Icons.hourglass_empty),
    };

    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Semantics(
        label: 'Diagnóstico de hoje: ${d.titulo}',
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icone, size: 18, color: cor),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        d.titulo,
                        style: LuminaText.cardTitle.copyWith(color: cor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  d.mensagem,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VizColors.inkPrimary,
                    height: 1.45,
                  ),
                ),
                if (d.evidencias.isNotEmpty) ...[
                  const SizedBox(height: Spacing.md),
                  for (final e in d.evidencias)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 5),
                            child: Icon(
                              Icons.circle,
                              size: 5,
                              color: VizColors.muted,
                            ),
                          ),
                          const SizedBox(width: Spacing.sm),
                          Expanded(
                            child: Text(
                              e,
                              style: const TextStyle(
                                fontSize: 12,
                                color: VizColors.inkSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: Spacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.arrow_forward, size: 16, color: cor),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      child: Text(
                        d.acao,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
