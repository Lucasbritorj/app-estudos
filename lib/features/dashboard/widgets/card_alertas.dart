import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/revisao.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../../../domain/planejamento_service.dart';
import '../../../domain/stats_service.dart';

/// Alertas dinâmicos: revisões atrasadas por matéria + falso domínio
/// (intimidade alta × acerto baixo). Some quando não há nada a alertar.
class CardAlertas extends ConsumerWidget {
  final DateTime hoje;

  const CardAlertas({super.key, required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revisoes = ref.watch(revisoesDoAmbienteProvider);
    final registros = ref.watch(registrosDoAmbienteProvider);
    final materias = ref
        .watch(materiasDoAmbienteProvider)
        .where((m) => !m.arquivada)
        .toList();
    final materiasPorId = {for (final m in materias) m.id: m};

    final atrasadasPorMateria = <String, int>{};
    for (final r in revisoes) {
      if (r.statusEm(hoje) == RevisaoStatus.atrasada) {
        atrasadasPorMateria[r.materiaId] =
            (atrasadasPorMateria[r.materiaId] ?? 0) + 1;
      }
    }

    final desempenho = StatsService.desempenhoPorMateria(registros);
    final falsoDominio = materias.where((m) {
      final d = desempenho[m.id];
      final taxa =
          d == null || d.questoes == 0 ? null : d.acertos / d.questoes;
      return PlanejamentoService.diagnostico(m.intimidade, taxa) ==
          DiagnosticoMateria.falsoDominio;
    }).toList();

    if (atrasadasPorMateria.isEmpty && falsoDominio.isEmpty) {
      return const SizedBox.shrink();
    }

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
