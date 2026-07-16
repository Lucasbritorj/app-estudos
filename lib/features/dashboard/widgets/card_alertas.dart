import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../dashboard_providers.dart';

/// Alertas dinâmicos: revisões atrasadas por matéria + falso domínio
/// (intimidade alta × acerto baixo). Some quando não há nada a alertar.
class CardAlertas extends ConsumerWidget {
  const CardAlertas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(alertasProvider);
    final atrasadasPorMateria = dados.atrasadasPorMateria;
    final falsoDominio = dados.falsoDominio;
    if (atrasadasPorMateria.isEmpty && falsoDominio.isEmpty) {
      return const SizedBox.shrink();
    }
    final materiasPorId = {
      for (final m in ref.watch(materiasDoAmbienteProvider)) m.id: m
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in atrasadasPorMateria.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          size: 16, color: StatusColors.critico),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Você tem ${e.value} '
                          '${e.value == 1 ? 'revisão atrasada' : 'revisões atrasadas'} '
                          'de ${materiasPorId[e.key]?.nome ?? 'matéria removida'}',
                          style: const TextStyle(
                              color: StatusColors.critico, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final m in falsoDominio)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber,
                          size: 16, color: StatusColors.atencao),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Falso domínio em ${m.nome}: intimidade alta, '
                          'acerto abaixo de 75% — reforce questões e revisão',
                          style: const TextStyle(
                              color: StatusColors.atencao, fontSize: 13),
                        ),
                      ),
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
