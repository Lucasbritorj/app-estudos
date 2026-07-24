import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/simulado.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../../../data/repositories/repositorios.dart';
import '../../simulados/simulados_screen.dart';

/// Desempenho em simulados/provas — ISOLADO do estudo diário de propósito:
/// mesmas métricas (taxa, erros), mas prova não se mistura com sessão de
/// estudo em nenhum somatório. Some quando não há simulados.
class CardSimulados extends ConsumerWidget {
  const CardSimulados({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ativo = ref.watch(ambienteAtivoProvider);
    final simulados = ref
        .watch(simuladosProvider)
        .where((s) => ativo == null || s.ambienteId == ativo.id)
        .toList();
    if (simulados.isEmpty) return const SizedBox.shrink();

    // Repo já ordena por data desc; delta = último vs anterior.
    final ultimos = simulados.take(3).toList();
    final taxaAtual = simulados.first.taxaGeral;
    final taxaAnterior = simulados.length > 1 ? simulados[1].taxaGeral : null;
    final delta = (taxaAtual != null && taxaAnterior != null)
        ? (taxaAtual - taxaAnterior) * 100
        : null;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SimuladosScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Simulados & Provas',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: VizColors.inkSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (delta != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          delta >= 0 ? Icons.trending_up : Icons.trending_down,
                          size: 16,
                          color: delta >= 0
                              ? StatusColors.bom
                              : StatusColors.critico,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(0)} pp',
                          style: TextStyle(
                            fontSize: 12,
                            color: delta >= 0
                                ? StatusColors.bom
                                : StatusColors.critico,
                          ),
                        ),
                      ],
                    ),
                  const Spacer(),
                  const Text(
                    'ver todos',
                    style: TextStyle(color: VizColors.muted, fontSize: 12),
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: VizColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Métricas de prova — não somam no estudo diário',
                style: TextStyle(color: VizColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              for (final s in ultimos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(
                        s.tipo == TipoSimulado.prova
                            ? Icons.workspace_premium_outlined
                            : Icons.fact_check_outlined,
                        size: 15,
                        color: s.tipo == TipoSimulado.prova
                            ? LuminaColors.ouro
                            : LuminaColors.safiraClara,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.nome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: VizColors.inkSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        '${formatarDiaMes(s.data)} · '
                        '${s.totalAcertos}/${s.totalQuestoes}'
                        '${s.taxaGeral == null ? '' : ' · ${(s.taxaGeral! * 100).toStringAsFixed(0)}%'}'
                        '${s.minutosPorQuestao == null ? '' : ' · ${formatarDecimal(s.minutosPorQuestao!)} min/q'}',
                        style: const TextStyle(
                          color: VizColors.muted,
                          fontSize: 12,
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
