import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/avatar_cor.dart';
import '../../../domain/insights_service.dart';
// `QuestDia` é nomeado nos campos de `_Quests`; `dashboard_providers` só
// expõe o provider, não reexporta o tipo.
import '../../../domain/quests_service.dart';
import '../../cronometro/cronometro_controller.dart';
import '../../registro/registro_form.dart';
import '../confete_leve.dart';
import '../dashboard_providers.dart';

const _iconesQuest = <String, IconData>{
  'estudar-deficit': Icons.menu_book_outlined,
  'estudar-hoje': Icons.menu_book_outlined,
  'revisoes-do-dia': Icons.event_repeat_outlined,
  'topico-mapa': Icons.account_tree_outlined,
};

/// Plano de hoje — resposta única para "o que eu faço agora?".
///
/// Funde três superfícies que disputavam a mesma pergunta no mesmo scroll:
/// `HeroMissaoHoje` (o próximo passo, com o botão de começar),
/// `CardQuests` (checklist do dia) e `CardMelhorarHoje` (recomendações do
/// `InsightsService`). Eram três caixas dizendo variações de "estude X" — o
/// usuário lia três vezes e decidia zero.
///
/// `CardPlano` NÃO entrou na fusão: apesar do nome, ele responde outra
/// pergunta (planejado vs feito em semana/mês/ano). Foi renomeado para
/// `CardPlanejadoVsFeito` para a colisão semântica sumir.
///
/// Ordem interna deliberada: AÇÃO (missão + botão) antes de PROGRESSO
/// (quests) antes de CONTEXTO (o que melhorar). A regra dos 3 segundos do
/// herói original continua valendo — "Estudar agora" segue sendo a primeira
/// coisa tocável do dashboard.
class CardPlanoDeHoje extends ConsumerWidget {
  const CardPlanoDeHoje({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sugestao = ref.watch(sugestaoHojeProvider);
    final quests = ref.watch(questsDoDiaProvider);
    final acoes = ref.watch(insightsProvider);

    // Some inteiro só quando as TRÊS seções estão vazias — cada uma tem
    // condição própria e o card não pode virar moldura vazia.
    if (sugestao == null && quests.isEmpty && acoes.isEmpty) {
      return const SizedBox.shrink();
    }

    final hoje = ref.watch(hojeProvider);
    final concluidas = quests.where((q) => q.concluida).length;
    // `quests.isNotEmpty` é obrigatório: sem ele, lista vazia daria
    // `0 == 0` e o confete dispararia num dia sem quest nenhuma. O card
    // antigo se protegia com early return, que aqui não existe mais.
    final todasQuests = quests.isNotEmpty && concluidas == quests.length;

    final secoes = <Widget>[
      if (sugestao != null) _Missao(sugestao: sugestao),
      if (quests.isNotEmpty) _Quests(quests: quests),
      if (acoes.isNotEmpty) _Melhorar(acoes: acoes),
    ];

    return ConfeteLeve(
      disparar: todasQuests,
      chave: 'plano-de-hoje-${hoje.toIso8601String()}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            boxShadow: LuminaElevation.glow(
              LuminaColors.safiraClara,
              alpha: 0.22,
            ),
          ),
          child: Card(
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(14)),
              side: BorderSide(
                color: LuminaColors.safiraClara.withValues(alpha: 0.45),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('PLANO DE HOJE', style: LuminaText.rotuloUppercase),
                      const Spacer(),
                      if (quests.isNotEmpty)
                        Text(
                          '$concluidas/${quests.length}',
                          style: TextStyle(
                            color: todasQuests
                                ? LuminaColors.ouro
                                : VizColors.muted,
                            fontWeight: todasQuests
                                ? FontWeight.w600
                                : FontWeight.w400,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                    ],
                  ),
                  for (var i = 0; i < secoes.length; i++) ...[
                    // Separador só ENTRE seções: uma linha antes da primeira
                    // ou depois da última seria régua solta.
                    if (i > 0)
                      const Divider(height: 24, color: Color(0x14FFFFFF)),
                    if (i == 0) const SizedBox(height: 8),
                    secoes[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bloco de ação: matéria do ciclo, déficit, próximo tópico e os dois
/// caminhos de registro. Vindo de `HeroMissaoHoje` sem mudança de
/// comportamento — 1 tap leva ao cronômetro já configurado e rodando.
class _Missao extends ConsumerWidget {
  const _Missao({required this.sugestao});

  final SugestaoHoje sugestao;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materia = sugestao.materia;
    final proximoTopico = sugestao.proximoTopico;

    void estudarAgora() {
      ref
          .read(preSelecaoCronometroProvider.notifier)
          .definir(materiaId: materia.id, topicoId: proximoTopico?.id);
      // Só inicia se parado: nunca atropela uma sessão pausada existente.
      if (ref.read(cronometroProvider).status == CronometroStatus.parado) {
        ref.read(cronometroProvider.notifier).iniciar();
      }
      ref.read(abaProvider.notifier).ir(Abas.cronometro);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AvatarCor(slot: materia.corSlot, raio: 7),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                materia.nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: VizColors.inkPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Faltam ${formatarMinutos(sugestao.deficitMinutos)} no '
          'ciclo desta semana'
          '${proximoTopico == null ? '' : ' · próximo tópico: '
                    '"${proximoTopico.nome}"'}',
          style: const TextStyle(color: VizColors.inkSecondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: estudarAgora,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Estudar agora'),
            ),
            TextButton(
              onPressed: () => mostrarFormularioRegistro(
                context,
                materiaInicial: materia.id,
                topicoInicial: proximoTopico?.id,
              ),
              child: const Text('Registrar manualmente'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Checklist do dia, vindo de `CardQuests`. O contador migrou para o
/// cabeçalho do card unificado; o resto é idêntico.
class _Quests extends StatelessWidget {
  const _Quests({required this.quests});

  final List<QuestDia> quests;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                        : (_iconesQuest[q.id] ?? Icons.radio_button_unchecked),
                    key: ValueKey(q.concluida),
                    size: 20,
                    color: q.concluida ? StatusColors.bom : VizColors.muted,
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
    );
  }
}

/// Recomendações do `InsightsService`, vindas de `CardMelhorarHoje`. O
/// título virou subtítulo interno: o card já se chama "Plano de hoje", e um
/// segundo "O que melhorar hoje" em titleMedium recriava a competição de
/// hierarquia que a fusão veio resolver.
class _Melhorar extends StatelessWidget {
  const _Melhorar({required this.acoes});

  final List<InsightAcao> acoes;

  static (IconData, Color) _visual(TipoInsight tipo) => switch (tipo) {
    TipoInsight.revisao => (Icons.event_repeat, StatusColors.critico),
    TipoInsight.desempenho => (Icons.trending_down, StatusColors.atencao),
    TipoInsight.streak => (Icons.local_fire_department, LuminaColors.ouro),
    TipoInsight.ritmo => (Icons.speed, VizColors.inkSecondary),
    TipoInsight.positivo => (Icons.check_circle_outline, StatusColors.bom),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'O que melhorar hoje',
          style: TextStyle(
            color: VizColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        for (final acao in acoes)
          InkWell(
            onTap: acao.materiaId == null
                ? null
                : () => mostrarFormularioRegistro(
                    context,
                    materiaInicial: acao.materiaId,
                  ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_visual(acao.tipo).$1, size: 16, color: _visual(acao.tipo).$2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      acao.mensagem,
                      style: const TextStyle(
                        color: VizColors.inkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (acao.materiaId != null)
                    const Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: VizColors.muted,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
