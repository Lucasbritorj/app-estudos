import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/materia.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../dashboard_providers.dart';

/// Desempenho acumulado em questões por matéria, com barra e status
/// (regra Nexus: <75% reforçar, 75-84% evoluindo, >=85% dominado).
class CardDesempenho extends ConsumerWidget {
  const CardDesempenho({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desempenho = ref.watch(desempenhoPorMateriaProvider);
    if (desempenho.isEmpty) return const SizedBox.shrink();
    final materias = ref.watch(materiasDoAmbienteProvider);
    final materiasPorId = {for (final m in materias) m.id: m};
    final geral = ref.watch(taxaAcertoGeralProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Desempenho em questões', style: LuminaText.cardTitle),
                const Spacer(),
                if (geral != null)
                  Text(
                    '${(geral * 100).toStringAsFixed(0)}% geral',
                    style: const TextStyle(color: VizColors.muted),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final e in desempenho.entries)
              _LinhaDesempenho(
                materia: materiasPorId[e.key],
                questoes: e.value.questoes,
                acertos: e.value.acertos,
              ),
          ],
        ),
      ),
    );
  }
}

class _LinhaDesempenho extends StatelessWidget {
  final Materia? materia;
  final int questoes;
  final int acertos;

  const _LinhaDesempenho({
    required this.materia,
    required this.questoes,
    required this.acertos,
  });

  @override
  Widget build(BuildContext context) {
    final taxa = questoes == 0 ? 0.0 : acertos / questoes;
    // Regra do alerta (protocolo Nexus): < 75% em disciplina = alerta vermelho.
    final (corStatus, icone, rotulo) = taxa < 0.75
        ? (StatusColors.critico, Icons.error_outline, 'reforçar')
        : taxa < 0.85
        ? (StatusColors.atencao, Icons.trending_up, 'evoluindo')
        : (StatusColors.bom, Icons.check_circle_outline, 'dominado');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
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
                  color: corDaSerie(materia?.corSlot ?? 0),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(materia?.nome ?? '—')),
              Icon(icone, size: 14, color: corStatus),
              const SizedBox(width: 4),
              Text(
                '$acertos/$questoes · ${(taxa * 100).toStringAsFixed(0)}% $rotulo',
                style: TextStyle(color: corStatus, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: taxa,
              minHeight: 6,
              backgroundColor: VizColors.gridline,
              color: corStatus,
            ),
          ),
        ],
      ),
    );
  }
}
