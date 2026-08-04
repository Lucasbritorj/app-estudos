import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/estado_vazio.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../ambientes/ambiente_selector.dart';
import '../busca/busca_screen.dart';
import '../caderno/caderno_providers.dart';
import '../registro/registro_form.dart';
import 'bancas_providers.dart';
import 'dashboard_providers.dart';
import 'frases_do_dia.dart';
import 'widgets/card_alertas.dart';
import 'widgets/card_ambientes.dart';
import 'widgets/card_anos.dart';
import 'widgets/card_bancas.dart';
import 'widgets/card_caderno_erros.dart';
import 'widgets/card_desempenho.dart';
import 'widgets/card_edital.dart';
import 'widgets/card_diagnostico.dart';
import 'widgets/card_gamificacao.dart';
import 'widgets/card_plano_de_hoje.dart';
import 'widgets/card_planejado_vs_feito.dart';
import 'widgets/card_prontidao.dart';
import 'widgets/card_forecast_revisao.dart';
import 'widgets/card_rankings.dart';
import 'widgets/card_revisoes_hoje.dart';
import 'widgets/card_true_retention.dart';
import 'widgets/heatmap_constancia.dart';
import 'widgets/card_simulados.dart';
import 'widgets/graficos.dart';
import 'widgets/hero_geral.dart';
import 'widgets/tiles_resumo.dart';

/// Tela-índice do dashboard: só composição e layout — cada card mora em
/// widgets/, um arquivo por responsabilidade.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vazio = ref.watch(registrosDoAmbienteProvider).isEmpty;
    final ambienteAtivo = ref.watch(ambienteAtivoProvider);
    final hoje = ref.watch(hojeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(ambienteAtivo?.nome ?? 'Visão Geral'),
        actions: [
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BuscaScreen()),
            ),
          ),
          const AmbienteSelector(),
          const SizedBox(width: 8),
        ],
      ),
      // O FAB já embrulha em MergeSemantics + Tooltip por padrão, mas
      // Tooltip expõe a mensagem como propriedade "tooltip" (dica
      // secundária), não como "label" — o nome primário que o leitor de
      // tela anuncia. Ícone sozinho (Icons.add) não fala nada: sem o label
      // explícito, TalkBack/VoiceOver anunciava só "botão", sem nome.
      floatingActionButton: Semantics(
        label: 'Registro manual',
        button: true,
        excludeSemantics: true,
        onTap: () => mostrarFormularioRegistro(context),
        child: FloatingActionButton(
          // Todo FAB sem `heroTag` compartilha a MESMA tag padrão. O
          // `IndexedStack` do shell (app.dart:95) constrói as 5 abas de uma
          // vez, então os FABs de Dashboard, Matérias e Revisões coexistem na
          // árvore o tempo todo. Na primeira transição de rota o Hero tenta
          // parear três origens para um destino e dispara "multiple heroes
          // that share the same tag" — assert de debug, comportamento
          // indefinido em release. Convenção: 'fab-<tela>', literal estável,
          // nunca derivado de dado em runtime.
          heroTag: 'fab-dashboard',
          tooltip: 'Registro manual',
          onPressed: () => mostrarFormularioRegistro(context),
          child: const Icon(Icons.add),
        ),
      ),
      body: vazio
          ? const _EstadoVazio()
          : ConteudoCentral(
              // 1560 abre espaço para o modo 3 colunas em monitor largo;
              // até 1359 de conteúdo o layout segue em 2 colunas.
              maxWidth: 1560,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Nº de colunas pela largura (o cap de 1560 já foi aplicado
                  // pelo ConteudoCentral acima). A grade masonry equilibra a
                  // altura sozinha — cada card entra na coluna mais CURTA no
                  // momento — então os rodapés alinham e a grade reflui ao
                  // ganhar/perder cards. Fim do vazio embaixo da coluna curta.
                  final colunas = constraints.maxWidth >= 1360
                      ? 3
                      : constraints.maxWidth >= 980
                          ? 2
                          : 1;

                  // Cards que se auto-escondem virariam "célula fantasma" na
                  // masonry (slot de altura zero deslocando o balanço), então
                  // entram na lista SÓ quando têm conteúdo — decidido AQUI via
                  // providers.
                  // "Plano de hoje" funde missão + quests + o que melhorar:
                  // aparece quando QUALQUER uma das três tem conteúdo, e o
                  // card decide internamente quais seções desenhar.
                  final temPlanoDeHoje =
                      ref.watch(sugestaoHojeProvider) != null ||
                      ref.watch(questsDoDiaProvider).isNotEmpty ||
                      ref.watch(insightsProvider).isNotEmpty;
                  final alertas = ref.watch(alertasProvider);
                  final temAlertas = alertas.atrasadasPorMateria.isNotEmpty ||
                      alertas.falsoDominio.isNotEmpty;
                  final temProntidao =
                      ref.watch(prontidaoProvider) != null;
                  final temRevisoesHoje =
                      ref.watch(revisoesDeHojeProvider).isNotEmpty;
                  final temDesempenho =
                      ref.watch(desempenhoPorMateriaProvider).isNotEmpty;
                  final temRetencao =
                      ref.watch(trueRetentionProvider).geral != null;
                  final caderno = ref.watch(resumoCadernoProvider);
                  final temCaderno =
                      caderno.totalAtivas > 0 || caderno.totalDominadas > 0;
                  final temBancas = ref.watch(bancasUsadasProvider).isNotEmpty;
                  final temForecast = ref
                      .watch(forecastRevisaoProvider)
                      .any((d) => d.quantidade > 0);

                  // Cards que fluem na grade, em ordem de prioridade de leitura
                  // (ação → progresso/gráficos → contexto). A masonry usa a
                  // ordem só para decidir quem entra primeiro; a ALTURA ela
                  // equilibra sozinha.
                  final cards = <Widget>[
                    // Ação pura primeiro: fechar revisão vencida é a coisa
                    // mais útil que o usuário faz a partir daqui.
                    if (temRevisoesHoje) const CardRevisoesHoje(),
                    if (temProntidao) const CardProntidao(),
                    const CardPlanejadoVsFeito(),
                    if (temDesempenho) const CardDesempenho(),
                    const CardEdital(),
                    const CardGrafico(
                      titulo: 'Horas da semana por matéria',
                      child: BarrasSemana(),
                    ),
                    const CardHeatmapConstancia(),
                    if (temForecast) const CardForecastRevisao(),
                    if (temCaderno) const CardCadernoErros(),
                    const CardGrafico(
                      titulo: 'Evolução — últimos 14 dias',
                      child: LinhaEvolucao(),
                    ),
                    if (temRetencao) const CardTrueRetention(),
                    const CardGrafico(
                      titulo: 'Distribuição total por matéria',
                      child: DonutDistribuicao(),
                    ),
                    if (ambienteAtivo == null) const CardAmbientes(),
                    const CardRankings(),
                    const CardSimulados(),
                    if (temBancas) const CardBancas(),
                    // Cards de "status fechado" (consulta, não ação): ficam
                    // juntos no rodapé da grade, lado a lado.
                    const CardGamificacao(),
                    const CardAnos(),
                  ];

                  return CustomScrollView(
                    slivers: [
                      // Topo enxuto e em largura total: frase + próximo passo
                      // (missão) + faixa de KPIs + alertas. Curto de propósito
                      // — sobe a grade e mantém a visão de relance acima da
                      // dobra. Missão/alertas se auto-escondem: só entram (com
                      // seu vão) quando há conteúdo, sem gap fantasma.
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.lg,
                          Spacing.xs,
                          Spacing.lg,
                          Spacing.md,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Spacing.md,
                                ),
                                child: Text(
                                  _mensagemDoDia(hoje),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: VizColors.inkSecondary,
                                        fontStyle: FontStyle.italic,
                                      ),
                                ),
                              ),
                              // Próximo passo primeiro: "o que estudar agora"
                              // antes de qualquer estatística. Tem vão próprio.
                              // Fica em largura total, fora da masonry, porque
                              // é o elemento da regra dos 3 segundos — enfiado
                              // na grade, "Estudar agora" viraria mais um card.
                              if (temPlanoDeHoje) const CardPlanoDeHoje(),
                              // Geralzão: faixa de KPIs, tudo de relance.
                              const HeroGeral(),
                              // Tiles complementares (mês/ano/ontem/média/
                              // melhor dia/ritmo): vieram do rodapé da grade
                              // pra área nobre — lá embaixo ficavam
                              // desalinhados e sem hierarquia com o resto.
                              const SizedBox(height: Spacing.md),
                              const TilesResumo(),
                              // Alertas ficam no topo (urgência tem de ser
                              // vista sem rolar); somem quando não há nada.
                              if (temAlertas) ...[
                                const SizedBox(height: Spacing.md),
                                const CardAlertas(),
                              ],
                              // Diagnóstico do dia: o veredito honesto vem
                              // antes da grade de estatísticas. Traz o próprio
                              // vão e some no estado semDados.
                              const CardDiagnostico(),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          Spacing.lg,
                          0,
                          Spacing.lg,
                          88,
                        ),
                        sliver: SliverMasonryGrid.count(
                          crossAxisCount: colunas,
                          mainAxisSpacing: Spacing.md,
                          crossAxisSpacing: Spacing.md,
                          childCount: cards.length,
                          itemBuilder: (context, i) => cards[i],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

/// Frase do dia: 366 frases em frases_do_dia.dart, indexadas pelo
/// dia-do-ano — cada dia do ano tem a SUA frase, sem repetir no ano.
String _mensagemDoDia(DateTime d) {
  final diaDoAno = d.difference(DateTime(d.year, 1, 1)).inDays;
  return frasesDoDia[diaDoAno % frasesDoDia.length];
}

/// Primeira visita: em vez de tela em branco, ensina de onde o dashboard
/// nasce e oferece os dois caminhos de entrada (registro manual/cronômetro).
class _EstadoVazio extends ConsumerWidget {
  const _EstadoVazio();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EstadoVazio(
      icone: Icons.auto_stories,
      titulo: 'Seu dashboard nasce do primeiro registro',
      descricao:
          'Cada sessão de estudo vira horas, gráficos, streak e '
          'sugestões do dia — tudo calculado automaticamente.',
      cta: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: () => mostrarFormularioRegistro(context),
            icon: const Icon(Icons.add),
            label: const Text('Registrar primeira sessão'),
          ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () =>
                ref.read(abaProvider.notifier).ir(Abas.cronometro),
            icon: const Icon(Icons.timer_outlined, size: 18),
            label: const Text('Ou estude agora com o cronômetro'),
          ),
        ],
      ),
    );
  }
}
