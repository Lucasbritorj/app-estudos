import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../dashboard_providers.dart';

const _iconesBadge = <String, IconData>{
  'primeira-sessao': Icons.flag,
  'dez-sessoes': Icons.repeat,
  'streak-7': Icons.local_fire_department,
  'streak-30': Icons.whatshot,
  'horas-50': Icons.timelapse,
  'horas-100': Icons.military_tech,
  'primeira-revisao': Icons.fact_check,
  'revisoes-em-dia': Icons.verified,
};

class CardGamificacao extends ConsumerWidget {
  const CardGamificacao({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // XP/nível/badges são do USUÁRIO, não do ambiente — sempre globais,
    // senão trocar de ambiente "rebaixaria" o nível.
    final dados = ref.watch(gamificacaoProvider);
    final xp = dados.xp;
    final progresso = dados.progresso;
    final badges = dados.badges;
    const corConquista = LuminaColors.ouro;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Nível ${progresso.nivel}',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(color: VizColors.inkPrimary)),
                const Spacer(),
                Text('${xp.total} XP',
                    style: const TextStyle(color: VizColors.muted)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progresso.xpParaProximo == 0
                    ? 0
                    : progresso.xpNoNivel / progresso.xpParaProximo,
                minHeight: 6,
                backgroundColor: VizColors.gridline,
                color: LuminaColors.ouro,
              ),
            ),
            const SizedBox(height: 4),
            Text(
                'Faltam ${progresso.xpParaProximo - progresso.xpNoNivel} XP para o nível ${progresso.nivel + 1} · '
                'estudo ${xp.base} + revisões ${xp.bonusRevisoes} + streak ${xp.bonusStreak}',
                style:
                    const TextStyle(color: VizColors.muted, fontSize: 11)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final badge in badges)
                  Tooltip(
                    message: badge.descricao,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          badge.conquistada
                              ? (_iconesBadge[badge.id] ?? Icons.star)
                              : Icons.lock_outline,
                          size: 16,
                          color: badge.conquistada
                              ? corConquista
                              : VizColors.muted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          badge.titulo,
                          style: TextStyle(
                            fontSize: 12,
                            color: badge.conquistada
                                ? VizColors.inkSecondary
                                : VizColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
