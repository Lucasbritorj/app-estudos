import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_cor.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../dashboard_providers.dart';

const _nomesDiaSemana = [
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
  'domingo',
];

/// Rankings inteligentes: mais estudada, melhor/pior taxa, dia forte e
/// ranking de acertos por matéria (amostra mínima de 10 questões).
class CardRankings extends ConsumerWidget {
  const CardRankings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materias = ref.watch(materiasDoAmbienteProvider);
    final dados = ref.watch(rankingsProvider);
    final nomes = {for (final m in materias) m.id: m};
    final maisEstudada = dados.maisEstudada;
    final ranking = dados.ranking;
    final melhorDia = dados.melhorDia;

    String nomeDe(String materiaId) => nomes[materiaId]?.nome ?? '—';

    final linhas = <(IconData, Color, String, String)>[
      if (maisEstudada != null && nomes.containsKey(maisEstudada.materiaId))
        (
          Icons.emoji_events,
          LuminaColors.ouro,
          'Mais estudada',
          '${nomeDe(maisEstudada.materiaId)} · '
              '${formatarMinutos(maisEstudada.minutos)}',
        ),
      if (ranking.isNotEmpty && nomes.containsKey(ranking.first.materiaId))
        (
          Icons.military_tech,
          StatusColors.bom,
          'Maior taxa de acerto',
          '${nomeDe(ranking.first.materiaId)} · '
              '${(ranking.first.taxa * 100).toStringAsFixed(0)}%',
        ),
      if (ranking.length > 1 && nomes.containsKey(ranking.last.materiaId))
        (
          Icons.priority_high,
          StatusColors.atencao,
          'Menor taxa (foco sugerido)',
          '${nomeDe(ranking.last.materiaId)} · '
              '${(ranking.last.taxa * 100).toStringAsFixed(0)}%',
        ),
      if (melhorDia != null)
        (
          Icons.calendar_today,
          LuminaColors.safiraClara,
          'Dia em que você mais estuda',
          '${_nomesDiaSemana[melhorDia.diaSemana - 1]} · '
              '${formatarMinutos(melhorDia.minutos)}',
        ),
    ];
    if (linhas.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rankings',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: VizColors.inkSecondary),
            ),
            const SizedBox(height: 10),
            for (final (icone, cor, rotulo, valor) in linhas)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(icone, size: 16, color: cor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rotulo,
                        style: const TextStyle(
                          color: VizColors.inkSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      valor,
                      style: const TextStyle(
                        color: VizColors.inkPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            if (ranking.isNotEmpty) ...[
              const Divider(color: VizColors.gridline),
              const SizedBox(height: 4),
              const Text(
                'Acertos por matéria (mín. 10 questões)',
                style: TextStyle(color: VizColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 6),
              for (final linha in ranking)
                if (nomes.containsKey(linha.materiaId))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        AvatarCor(
                          slot: nomes[linha.materiaId]!.corSlot,
                          raio: 5,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            nomeDe(linha.materiaId),
                            style: const TextStyle(
                              color: VizColors.inkSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          '${linha.acertos}✓ ${linha.questoes - linha.acertos}✗ · '
                          '${(linha.taxa * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: VizColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
