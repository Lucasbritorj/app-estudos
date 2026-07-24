import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/estado_vazio.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../ambientes/ambiente_selector.dart';
import '../registro/registro_form.dart';
import 'dashboard_providers.dart';
import 'frases_do_dia.dart';
import 'widgets/card_alertas.dart';
import 'widgets/card_ambientes.dart';
import 'widgets/card_anos.dart';
import 'widgets/card_desempenho.dart';
import 'widgets/card_diagnostico.dart';
import 'widgets/card_gamificacao.dart';
import 'widgets/card_melhorar_hoje.dart';
import 'widgets/card_plano.dart';
import 'widgets/card_prontidao.dart';
import 'widgets/card_quests.dart';
import 'widgets/card_forecast_revisao.dart';
import 'widgets/card_rankings.dart';
import 'widgets/card_true_retention.dart';
import 'widgets/heatmap_constancia.dart';
import 'widgets/card_simulados.dart';
import 'widgets/graficos.dart';
import 'widgets/hero_geral.dart';
import 'widgets/hero_missao_hoje.dart';
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
        actions: const [AmbienteSelector(), SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Registro manual',
        onPressed: () => mostrarFormularioRegistro(context),
        child: const Icon(Icons.add),
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
                  final temMissao =
                      ref.watch(sugestaoHojeProvider) != null;
                  final alertas = ref.watch(alertasProvider);
                  final temAlertas = alertas.atrasadasPorMateria.isNotEmpty ||
                      alertas.falsoDominio.isNotEmpty;
                  final temProntidao =
                      ref.watch(prontidaoProvider) != null;
                  final temQuests =
                      ref.watch(questsDoDiaProvider).isNotEmpty;
                  final temDesempenho =
                      ref.watch(desempenhoPorMateriaProvider).isNotEmpty;
                  final temRetencao =
                      ref.watch(trueRetentionProvider).geral != null;
                  final temForecast = ref
                      .watch(forecastRevisaoProvider)
                      .any((d) => d.quantidade > 0);

                  // Cards que fluem na grade, em ordem de prioridade de leitura
                  // (ação → progresso/gráficos → contexto). A masonry usa a
                  // ordem só para decidir quem entra primeiro; a ALTURA ela
                  // equilibra sozinha.
                  final cards = <Widget>[
                    const CardMelhorarHoje(),
                    if (temProntidao) const CardProntidao(),
                    if (temQuests) const CardQuests(),
                    const CardPlano(),
                    if (temDesempenho) const CardDesempenho(),
                    const CardGrafico(
                      titulo: 'Horas da semana por matéria',
                      child: BarrasSemana(),
                    ),
                    const CardHeatmapConstancia(),
                    if (temForecast) const CardForecastRevisao(),
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
                    const CardGamificacao(),
                    const CardAnos(),
                    const TilesResumo(),
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
                              if (temMissao) const HeroMissaoHoje(),
                              // Geralzão: faixa de KPIs, tudo de relance.
                              const HeroGeral(),
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
