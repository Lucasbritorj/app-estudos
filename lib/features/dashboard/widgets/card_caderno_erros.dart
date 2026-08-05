import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
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

    // "0" + "vencem hoje" é leitura de tela, não fala: por extenso vira
    // "nada vence hoje". Concordância pelo `plural` de formatters.dart, em vez
    // de um helper novo — `rotulos_a11y.dart` cobre minutos, ritmo e variação
    // MoM, nada que este card exiba.
    final filaFalada = resumo.venceHoje == 0
        ? 'nada vence hoje'
        : '${plural(resumo.venceHoje, 'questão vence', 'questões vencem')} hoje';
    // Ramo nulo espelha o "—" do tile. Inalcançável enquanto o card está
    // visível (taxaRecuperacao só é nula com a lista vazia, e lista vazia já
    // devolveu SizedBox.shrink lá em cima), mas o tipo é `double?` e repetir a
    // defesa do tile custa menos que confiar na invariante à distância.
    final taxaFalada = taxa == null
        ? 'recuperação ainda sem dados'
        : '${(taxa * 100).toStringAsFixed(0)}% de recuperação';

    // SEM `excludeSemantics`, mesma decisão de CardSimulados: os dois `_Tile`
    // do interior carregam os únicos números do card e excluí-los seria
    // regressão pior que o bug (lição B18). O defeito que se fecha aqui é a
    // AUSÊNCIA de ponto de entrada nomeado — o `InkWell` de baixo é um nó
    // acionável sem rótulo (ink_well.dart emite `Semantics(onTap:)` puro, sem
    // label e sem `button`).
    //
    // Esse nó anônimo não funde no de cima: duas configs com a ação `tap` são
    // incompatíveis (`SemanticsConfiguration.isCompatibleWith` rejeita quando
    // `_actionsAsBits` se cruzam). Por isso o `InkWell` abaixo vai com
    // `excludeFromSemantics: true`, que zera só as ações semânticas do
    // InkResponse (`ink_well.dart:1402`) e não emite nó nenhum. O
    // GestureDetector interno segue recebendo ponteiro; para leitor de tela,
    // quem carrega a tocabilidade é o `onTap` daqui.
    return Semantics(
      container: true,
      button: true,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CadernoScreen()),
      ),
      label: 'Caderno de erros: $filaFalada, $taxaFalada. Abrir caderno',
      child: Card(
      child: InkWell(
        excludeFromSemantics: true,
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
