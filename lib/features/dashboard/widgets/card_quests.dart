import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../confete_leve.dart';
import '../dashboard_providers.dart';

const _iconesQuest = <String, IconData>{
  'estudar-deficit': Icons.menu_book_outlined,
  'estudar-hoje': Icons.menu_book_outlined,
  'revisoes-do-dia': Icons.event_repeat_outlined,
  'topico-mapa': Icons.account_tree_outlined,
};

/// Quests de hoje: checklist derivado do planejador. A recompensa é o
/// próprio progresso (+ confete ao fechar o dia) — sem XP, ver
/// QuestsService para o porquê.
class CardQuests extends ConsumerWidget {
  const CardQuests({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(questsDoDiaProvider);
    if (quests.isEmpty) return const SizedBox.shrink();
    final hoje = ref.watch(hojeProvider);
    final concluidas = quests.where((q) => q.concluida).length;
    final todas = concluidas == quests.length;

    return ConfeteLeve(
      disparar: todas,
      chave: 'quests-${hoje.toIso8601String()}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Quests de hoje',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: VizColors.inkPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$concluidas/${quests.length}',
                    style: TextStyle(
                      color: todas ? LuminaColors.ouro : VizColors.muted,
                      fontWeight: todas ? FontWeight.w600 : FontWeight.w400,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final q in quests)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      // Troca de estado com fade: concluir "acende" o check.
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        child: Icon(
                          q.concluida
                              ? Icons.check_circle
                              : (_iconesQuest[q.id] ??
                                    Icons.radio_button_unchecked),
                          key: ValueKey(q.concluida),
                          size: 20,
                          color: q.concluida
                              ? StatusColors.bom
                              : VizColors.muted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.titulo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: q.concluida
                                    ? VizColors.muted
                                    : VizColors.inkPrimary,
                                decoration: q.concluida
                                    ? TextDecoration.lineThrough
                                    : null,
                                decorationColor: VizColors.muted,
                              ),
                            ),
                            Text(
                              q.descricao,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: VizColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (q.alvo > 1) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${q.atual}/${q.alvo}',
                          style: const TextStyle(
                            color: VizColors.muted,
                            fontSize: 12,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
