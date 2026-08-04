import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar_cor.dart';
import '../../../data/models/revisao.dart';
import '../../../data/repositories/repositorios.dart';
import '../../revisoes/conclusao_revisao.dart';
import '../dashboard_providers.dart';

/// Revisões de hoje, concluíveis SEM sair do dashboard.
///
/// Antes, o dashboard só sabia navegar: `CardForecastRevisao` e `HeroGeral`
/// faziam `ir(Abas.revisoes)`. Ver "3 revisões atrasadas" e ter de trocar de
/// aba para fechá-las é atrito num app cuja proposta é revisão espaçada em
/// dia — a revisão adiada por preguiça de navegar é retenção perdida.
///
/// Conclui pelo fluxo compartilhado (`concluirRevisaoComFeedback`), o MESMO
/// que a tela de Revisões usa: FSRS, sessão prática, lembrete cancelado e
/// próxima agendada saem idênticos pelos dois caminhos.
class CardRevisoesHoje extends ConsumerWidget {
  const CardRevisoesHoje({super.key});

  /// Teto de linhas desenhadas. Backlog de 20 atrasadas viraria um card
  /// rolável do tamanho da tela; o contador continua dizendo o total real e
  /// "Ver todas" leva para a lista completa.
  static const maxVisiveis = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final revisoes = ref.watch(revisoesDeHojeProvider);
    if (revisoes.isEmpty) return const SizedBox.shrink();

    final hoje = ref.watch(hojeProvider);
    final materias = {for (final m in ref.watch(materiasProvider)) m.id: m};
    final visiveis = revisoes.take(maxVisiveis).toList();
    final restantes = revisoes.length - visiveis.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Revisões de hoje',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: VizColors.inkPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  plural(revisoes.length, 'pendente', 'pendentes'),
                  style: const TextStyle(
                    color: VizColors.muted,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final r in visiveis)
              _Linha(
                revisao: r,
                corSlot: materias[r.materiaId]?.corSlot,
                nomeMateria: materias[r.materiaId]?.nome,
                diasDeAtraso: hoje.difference(_soData(r.dataAgendada)).inDays,
              ),
            if (restantes > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => ref.read(abaProvider.notifier).ir(
                    Abas.revisoes,
                  ),
                  child: Text('Ver todas (+$restantes)'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static DateTime _soData(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _Linha extends ConsumerWidget {
  const _Linha({
    required this.revisao,
    required this.corSlot,
    required this.nomeMateria,
    required this.diasDeAtraso,
  });

  final Revisao revisao;
  final int? corSlot;
  final String? nomeMateria;
  final int diasDeAtraso;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Atraso é o dado que decide a ordem de ataque — vale texto próprio, não
    // só a cor (que sozinha não passa em WCAG).
    final atrasada = diasDeAtraso > 0;
    final situacao = atrasada
        ? 'atrasada ${plural(diasDeAtraso, 'dia', 'dias')}'
        : 'vence hoje';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          AvatarCor(slot: corSlot ?? 0, raio: 6),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  revisao.titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: VizColors.inkPrimary),
                ),
                Text(
                  '${nomeMateria ?? '—'} · $situacao',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: atrasada ? StatusColors.atencao : VizColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            // Rótulo com o título junto: numa lista de 4 botões iguais, o
            // leitor de tela anunciaria "concluir revisão" quatro vezes sem
            // dizer QUAL.
            tooltip: 'Concluir: ${revisao.titulo}',
            icon: const Icon(Icons.check_circle_outline),
            color: StatusColors.bom,
            onPressed: () =>
                concluirRevisaoComFeedback(context, ref, revisao),
          ),
        ],
      ),
    );
  }
}
