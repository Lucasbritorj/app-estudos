import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../../../domain/banca_service.dart';
import '../bancas_providers.dart';

/// Desempenho por banca organizadora: ranking de taxa de acerto
/// (melhor→pior) com questões e nº de simulados, mais o destaque do par
/// banca×matéria mais fraco. Cada banca cobra de um jeito diferente
/// (CEBRASPE certo/errado com pegadinha de literalidade, FGV com raciocínio
/// longo, FCC com letra de lei) — 80% na FCC e 55% na CEBRASPE não é
/// "problema de conteúdo", é problema de banca, e é essa leitura que a taxa
/// geral do dashboard esconde.
///
/// Some (SizedBox.shrink) quando o usuário nunca informou banca em sessão
/// nem simulado nenhum — evita célula fantasma na masonry do dashboard,
/// mesmo padrão de CardSimulados/CardCadernoErros.
class CardBancas extends ConsumerWidget {
  const CardBancas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usadas = ref.watch(bancasUsadasProvider);
    if (usadas.isEmpty) return const SizedBox.shrink();

    final ranking = ref.watch(rankingBancasProvider);
    final pontoFraco = ref.watch(pontoFracoBancaProvider);
    final materiasPorId = {
      for (final m in ref.watch(materiasDoAmbienteProvider)) m.id: m,
    };

    // Banca com dado mas abaixo da amostra mínima entra em `usadas` (o
    // agregado bruto conta todo mundo) e some do `ranking` (que já filtra
    // — ver BancaService.ranking). Sem avisar isso, a lista do ranking com
    // menos linhas que bancas registradas parece bug ("cadê minha 3ª
    // banca?"), não filtro proposital.
    final ocultasPorAmostra = usadas.length - ranking.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Desempenho por banca', style: LuminaText.cardTitle),
            const SizedBox(height: Spacing.md),
            if (pontoFraco != null) ...[
              _DestaquePontoFraco(
                pontoFraco: pontoFraco,
                nomeMateria:
                    materiasPorId[pontoFraco.materiaId]?.nome ??
                    'matéria removida',
              ),
              const SizedBox(height: Spacing.md),
            ],
            if (ranking.isEmpty)
              const Text(
                'Nenhuma banca com questões suficientes para ranking ainda.',
                style: TextStyle(color: VizColors.muted, fontSize: 12),
              )
            else
              for (final d in ranking) _LinhaBanca(dado: d),
            if (ocultasPorAmostra > 0)
              Padding(
                padding: const EdgeInsets.only(top: Spacing.xs),
                child: Text(
                  '$ocultasPorAmostra banca${ocultasPorAmostra == 1 ? '' : 's'} '
                  'com menos de ${BancaService.amostraMinima} questões '
                  '${ocultasPorAmostra == 1 ? 'ficou' : 'ficaram'} fora do '
                  'ranking.',
                  style: const TextStyle(
                    color: VizColors.muted,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Uma linha do ranking: banca, questões/simulados e taxa em destaque.
class _LinhaBanca extends StatelessWidget {
  final DesempenhoBanca dado;

  const _LinhaBanca({required this.dado});

  @override
  Widget build(BuildContext context) {
    // StatusColors.porTaxa em texto pequeno passa WCAG AA sobre
    // VizColors.surface nos três estados (bom 4,79:1 / atencao 8,76:1 /
    // critico 4,91:1 — medido, ver app_theme.dart) — dispensa o truque de
    // "fonte grande" que simulados_screen.dart precisou para outro contexto.
    final cor = StatusColors.porTaxa(dado.taxa);
    final taxaPct = (dado.taxa * 100).toStringAsFixed(0);
    // Banca, amostra e taxa viviam em Text irmãos (mesmo problema resolvido
    // em card_desempenho.dart): "/" seria lido como "barra" e a cor de
    // status não fala nada sozinha. Nó único, por extenso.
    final rotuloA11y =
        '${dado.banca}, ${dado.acertos} de ${dado.questoes} questões'
        '${dado.simulados > 0 ? ', ${dado.simulados} ${dado.simulados == 1 ? 'simulado' : 'simulados'}' : ''}'
        ', $taxaPct%';
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: rotuloA11y,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dado.banca,
                    style: const TextStyle(
                      color: VizColors.inkSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${dado.acertos}/${dado.questoes} questões'
                    '${dado.simulados > 0 ? ' · ${dado.simulados} ${dado.simulados == 1 ? 'simulado' : 'simulados'}' : ''}',
                    style: const TextStyle(
                      color: VizColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '$taxaPct%',
              style: TextStyle(
                color: cor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Destaque do pior par banca×matéria — a recomendação mais acionável do
/// card ("é AQUI que treinar rende mais"), em caixa tintada tipo alerta.
class _DestaquePontoFraco extends StatelessWidget {
  final ({String banca, String materiaId, double taxa, int questoes})
  pontoFraco;
  final String nomeMateria;

  const _DestaquePontoFraco({
    required this.pontoFraco,
    required this.nomeMateria,
  });

  @override
  Widget build(BuildContext context) {
    final cor = StatusColors.porTaxa(pontoFraco.taxa);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: cor.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gps_fixed, size: 16, color: cor),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              'Você acerta ${(pontoFraco.taxa * 100).toStringAsFixed(0)}% em '
              '$nomeMateria na ${pontoFraco.banca} — '
              '${pontoFraco.questoes} questões',
              style: TextStyle(
                color: cor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
