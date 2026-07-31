import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../caderno/caderno_providers.dart';
import '../../caderno/caderno_screen.dart';

/// Atalho do caderno de erros: quantas questões vencem hoje + taxa de
/// recuperação (% já dominado). Some quando o caderno está vazio — mesmo
/// padrão dos outros cards que dependem de dado ainda inexistente
/// (CardSimulados, CardForecastRevisao etc.).
class CardCadernoErros extends ConsumerWidget {
  const CardCadernoErros({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumo = ref.watch(resumoCadernoProvider);
    if (resumo.totalAtivas == 0 && resumo.totalDominadas == 0) {
      return const SizedBox.shrink();
    }
    final taxa = resumo.taxaRecuperacao;
    // Mesma receita do HeroGeral (_Kpi): a cor de status vira tinta de
    // fundo/borda do tile, nunca preenchimento do texto do número (que fica
    // sempre em inkPrimary — é o texto grande, precisa do contraste maior).
    final corFila = resumo.venceHoje > 0
        ? StatusColors.atencao
        : LuminaColors.safiraClara;
    final corTaxa = taxa == null ? LuminaColors.safiraClara : StatusColors.porTaxa(taxa);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CadernoScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Caderno de Erros', style: LuminaText.cardTitle),
                  ),
                  const Icon(Icons.arrow_forward, size: 14, color: VizColors.muted),
                ],
              ),
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      tinta: corFila,
                      rotulo: resumo.venceHoje == 1 ? 'vence hoje' : 'vencem hoje',
                      valor: '${resumo.venceHoje}',
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: _Tile(
                      tinta: corTaxa,
                      rotulo: 'recuperação',
                      valor: taxa == null ? '—' : '${(taxa * 100).toStringAsFixed(0)}%',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Color tinta;
  final String rotulo;
  final String valor;

  const _Tile({required this.tinta, required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      // Valor e rótulo viviam em Text irmãos (mesmo problema de _Percentual
      // em card_prontidao.dart) — a tinta de fundo/borda carrega o status
      // mas não fala nada sozinha pro leitor de tela.
      label: '$rotulo: $valor',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        decoration: BoxDecoration(
          color: tinta.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: tinta.withValues(alpha: 0.28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              valor,
              style: LuminaText.numeroHero.copyWith(
                fontSize: 22,
                color: VizColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(rotulo, style: const TextStyle(color: VizColors.muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
