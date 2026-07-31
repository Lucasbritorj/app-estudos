import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/stats_service.dart' show Comparativo;
import '../dashboard_providers.dart';
import 'rotulos_a11y.dart';

/// Tiles de números complementares. Hoje/Semana/Streak/Total moram no
/// HeroGeral — aqui entra só o que NÃO está no hero, sem duplicar métrica.
/// Vive na área nobre (topo, logo abaixo do HeroGeral) — por isso os tiles
/// são compactos: densidade alta, sem competir com o hero.
class TilesResumo extends ConsumerWidget {
  const TilesResumo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(tilesResumoProvider);
    final ritmo = dados.ritmo;
    final comparativoMes = ref.watch(comparativoMensalProvider);
    final comparativoAno = ref.watch(comparativoAnualProvider);

    // (rótulo, valor, valor por extenso p/ leitor de tela, comparativo
    // MoM/YoY, período do texto de apoio) — só Mês/Ano têm comparativo; os
    // demais tiles ficam com null (sem seta).
    final tiles = <(String, String, String, Comparativo?, String?)>[
      (
        'Mês',
        formatarMinutos(dados.mes),
        minutosPorExtenso(dados.mes),
        comparativoMes,
        'mês',
      ),
      (
        'Ano',
        formatarMinutos(dados.ano),
        minutosPorExtenso(dados.ano),
        comparativoAno,
        'ano',
      ),
      ('Ontem', formatarMinutos(dados.ontem), minutosPorExtenso(dados.ontem), null, null),
      (
        'Média/dia',
        formatarMinutos(dados.media),
        minutosPorExtenso(dados.media),
        null,
        null,
      ),
      (
        'Melhor dia',
        formatarMinutos(dados.maximo),
        minutosPorExtenso(dados.maximo),
        null,
        null,
      ),
      if (ritmo != null)
        (
          'Ritmo',
          '${formatarDecimal(ritmo)} pág/h',
          ritmoPorExtenso(ritmo),
          null,
          null,
        ),
    ];

    // Extent máximo fixo: em tela larga entram 3-4 por linha COMPACTOS —
    // crossAxisCount fixo virava "quadros enormes" em 1900px (feedback).
    // Mais compacto que a versão de rodapé (era 210/66): agora vive na área
    // nobre, junto do hero, e precisa ceder espaço vertical a ele.
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 62,
        mainAxisSpacing: Spacing.sm,
        crossAxisSpacing: Spacing.sm,
      ),
      children: [
        for (final (rotulo, valor, valorA11y, comparativo, periodo) in tiles)
          // Sem isto, o leitor de tela lia "Mês" e "2h 15min" como dois nós
          // soltos (rótulo e AnimatedSwitcher são widgets irmãos). Um nó só,
          // com o valor por extenso — excludeSemantics apaga os textos
          // visuais abreviados por baixo para não duplicar a leitura.
          Semantics(
            container: true,
            excludeSemantics: true,
            label: _rotuloTileA11y(rotulo, valorA11y, comparativo, periodo),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            rotulo,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.labelMedium?.copyWith(
                              color: VizColors.muted,
                            ),
                          ),
                        ),
                        if (comparativo != null &&
                            comparativo.variacao != null) ...[
                          const SizedBox(width: 4),
                          _Variacao(comparativo: comparativo, periodo: periodo!),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Troca de valor com fade curto — vida sem exagero.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: Text(
                        valor,
                        key: ValueKey(valor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // numeroHero: Display tabular com height 1.0 (controla a
                        // altura no tile fixo, não estoura como o titleLarge).
                        style: LuminaText.numeroHero.copyWith(
                          fontSize: 18,
                          color: VizColors.inkPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Rótulo por extenso de um tile: "Mês: 2 horas e 15 minutos, subiu 12% em
/// relação ao mesmo ponto do mês passado" — a variação só entra quando existe
/// (Mês/Ano com comparativo calculado).
String _rotuloTileA11y(
  String rotulo,
  String valorA11y,
  Comparativo? comparativo,
  String? periodo,
) {
  final variacao = comparativo?.variacao;
  final fraseVariacao = variacao == null
      ? ''
      : variacaoPorExtenso(variacao, periodo!);
  return '$rotulo: $valorA11y$fraseVariacao';
}

/// Seta + percentual de variação MoM/YoY, ao lado do rótulo. Tooltip carrega
/// o texto de apoio (não cabe escrito por extenso no tile compacto) —
/// "parcial-vs-parcial" honesto: não diz "mês passado" cheio, diz até o
/// mesmo ponto do período anterior (ver StatsService.comparativoMensal).
class _Variacao extends StatelessWidget {
  const _Variacao({required this.comparativo, required this.periodo});

  final Comparativo comparativo;
  final String periodo;

  @override
  Widget build(BuildContext context) {
    final variacao = comparativo.variacao!;
    final subiu = variacao > 0;
    final estavel = variacao == 0;
    final cor = estavel
        ? VizColors.muted
        : (subiu ? StatusColors.bom : StatusColors.critico);
    final icone = estavel
        ? Icons.remove
        : (subiu ? Icons.arrow_upward : Icons.arrow_downward);

    return Tooltip(
      message: 'vs. mesmo ponto do $periodo passado',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 10, color: cor),
          Text(
            '${(variacao.abs() * 100).toStringAsFixed(0)}%',
            maxLines: 1,
            style: TextStyle(color: cor, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
