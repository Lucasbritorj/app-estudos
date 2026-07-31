import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/edital_service.dart';
import '../../edital/edital_providers.dart';
import '../../edital/edital_screen.dart';

/// Resumo do edital verticalizado no dashboard: cobertura geral, tópicos
/// intocados e o buraco mais caro (maior peso matéria × peso tópico).
/// Toca para abrir a tela cheia (mesmo padrão de CardSimulados). Some
/// (SizedBox.shrink) sem tópico cadastrado no ambiente ativo — nada a
/// resumir, e um card com "0%" acusaria um atraso que não existe (mesma
/// regra do topo da tela do edital).
class CardEdital extends ConsumerWidget {
  const CardEdital({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cobertura = ref.watch(coberturaGeralEditalProvider);
    if (cobertura == null) return const SizedBox.shrink();

    final distribuicao = ref.watch(distribuicaoEditalProvider);
    final intocados = distribuicao[SituacaoTopico.intocado] ?? 0;
    // Denominador SEMPRE visível: "100% cobertos" com 1 tópico cadastrado de
    // um edital de centenas é a leitura mais perigosa que este card pode
    // produzir — o número sozinho vira falsa segurança. A base cadastrada
    // qualifica o percentual.
    final totalTopicos = distribuicao.values.fold(0, (a, b) => a + b);
    final piorBuraco = ref.watch(buracosEditalProvider).firstOrNull;
    final cor = StatusColors.porTaxa(cobertura);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.lg),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EditalScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edital verticalizado',
                      style: LuminaText.cardTitle,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: VizColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              // Percentual (cor de status) e a base "de N tópicos" viviam em
              // Text irmãos — o denominador é obrigatório aqui (ver
              // comentário da classe), então precisa continuar no MESMO nó
              // do percentual, não sumir. Mesma receita de card_prontidao.dart.
              Semantics(
                container: true,
                excludeSemantics: true,
                label:
                    '${(cobertura * 100).toStringAsFixed(0)}% de $totalTopicos '
                    'tópico${totalTopicos == 1 ? '' : 's'} do edital',
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${(cobertura * 100).toStringAsFixed(0)}%',
                      style: LuminaText.numeroHero.copyWith(
                        color: cor,
                        fontSize: 32,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 6),
                      child: Text(
                        'de $totalTopicos tópico'
                        '${totalTopicos == 1 ? '' : 's'} do edital',
                        style: const TextStyle(
                          color: VizColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (intocados > 0) ...[
                const SizedBox(height: Spacing.sm),
                Row(
                  children: [
                    const Icon(
                      Icons.radio_button_unchecked,
                      size: 14,
                      color: VizColors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$intocados tópico${intocados == 1 ? '' : 's'} '
                      'intocado${intocados == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: VizColors.inkSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
              if (piorBuraco != null) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.priority_high,
                        size: 14,
                        color: StatusColors.critico,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Buraco mais caro: ${piorBuraco.materia.nome} — '
                        '${piorBuraco.linha.topico.nome}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: StatusColors.critico,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
