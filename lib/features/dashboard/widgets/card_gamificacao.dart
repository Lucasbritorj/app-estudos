import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../confete_leve.dart';
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

    // Badge NOVA (conquistada agora, não ao abrir o app) = confete dourado.
    // O snapshot inicial só registra; depois, cada diferença dispara uma vez
    // (ConfeteLeve deduplica pela chave).
    final conquistadas = {
      for (final b in badges)
        if (b.conquistada) b.id,
    };
    final vistas = ref.watch(badgesVistasProvider);
    final novas =
        vistas == null ? const <String>{} : conquistadas.difference(vistas);
    if (vistas == null || novas.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(badgesVistasProvider.notifier).registrar(conquistadas);
      });
    }

    return ConfeteLeve(
      disparar: novas.isNotEmpty,
      chave: 'badge-${(novas.toList()..sort()).join('-')}',
      cores: ConfeteLeve.coresOuro,
      child: Card(
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
                  // XP troca com fade e dígitos tabulares — conta, não salta.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    child: Text(
                      '${xp.total} XP',
                      key: ValueKey(xp.total),
                      style: const TextStyle(
                        color: VizColors.muted,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
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
                      child: DecoratedBox(
                        // Glow dourado só na badge recém-conquistada.
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: novas.contains(badge.id)
                              ? LuminaElevation.glow(corConquista)
                              : null,
                        ),
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
