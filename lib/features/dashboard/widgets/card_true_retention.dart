import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../dashboard_providers.dart';

/// True retention (à la Anki): taxa de acerto NAS REVISÕES no vencimento, por
/// matéria — mede se o intervalo de spaced repetition está calibrado. Só
/// aparece quando há revisão concluída com desempenho registrado.
class CardTrueRetention extends ConsumerWidget {
  const CardTrueRetention({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(trueRetentionProvider);
    if (dados.geral == null || dados.porMateria.isEmpty) {
      return const SizedBox.shrink();
    }
    final materiasPorId = {
      for (final m in ref.watch(materiasDoAmbienteProvider)) m.id: m,
    };
    final linhas = dados.porMateria.entries.toList()
      ..sort((a, b) => a.value.taxa.compareTo(b.value.taxa));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Retenção nas revisões',
                      style: LuminaText.cardTitle),
                ),
                Text(
                  '${(dados.geral! * 100).toStringAsFixed(0)}% geral',
                  style: LuminaText.numeroHero.copyWith(
                    fontSize: 15,
                    color: StatusColors.porTaxa(dados.geral!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.xs),
            const Text(
              'Acerto no vencimento — abaixo de 85% sugere revisar mais cedo.',
              style: TextStyle(color: VizColors.muted, fontSize: 11),
            ),
            const SizedBox(height: Spacing.md),
            for (final e in linhas)
              _LinhaRetencao(
                nome: materiasPorId[e.key]?.nome ?? '—',
                corSlot: materiasPorId[e.key]?.corSlot ?? 0,
                taxa: e.value.taxa,
                questoes: e.value.questoes,
              ),
          ],
        ),
      ),
    );
  }
}

class _LinhaRetencao extends StatelessWidget {
  final String nome;
  final int corSlot;
  final double taxa;
  final int questoes;

  const _LinhaRetencao({
    required this.nome,
    required this.corSlot,
    required this.taxa,
    required this.questoes,
  });

  @override
  Widget build(BuildContext context) {
    final cor = StatusColors.porTaxa(taxa);
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: corDaSerie(corSlot),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(nome)),
              Text(
                '${(taxa * 100).toStringAsFixed(0)}% · $questoes q',
                style: TextStyle(color: cor, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: Spacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(
              value: taxa,
              minHeight: 6,
              backgroundColor: VizColors.gridline,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}
