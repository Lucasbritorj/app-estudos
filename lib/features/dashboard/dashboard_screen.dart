import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../ambientes/ambiente_selector.dart';
import '../registro/registro_form.dart';
import 'dashboard_providers.dart';
import 'frases_do_dia.dart';
import 'widgets/card_alertas.dart';
import 'widgets/card_ambientes.dart';
import 'widgets/card_anos.dart';
import 'widgets/card_desempenho.dart';
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
                  // Descompressão por hierarquia: topo fixo (missão, hero,
                  // avisos) e três grupos por prioridade — ação de hoje,
                  // progresso/gráficos, contexto longitudinal. A largura
                  // decide 1, 2 ou 3 colunas; no mobile a ordem de rolagem
                  // segue a mesma prioridade.
                  final tresColunas = constraints.maxWidth >= 1360;
                  final duasColunas = constraints.maxWidth >= 980;

                  // Visibilidade dos cards que se auto-escondem — decidida
                  // AQUI (via providers) para não deixar "gaps fantasma" nas
                  // colunas quando um card vira SizedBox.shrink.
                  final temQuests =
                      ref.watch(questsDoDiaProvider).isNotEmpty;
                  final temDesempenho =
                      ref.watch(desempenhoPorMateriaProvider).isNotEmpty;
                  final temRetencao =
                      ref.watch(trueRetentionProvider).geral != null;
                  final temForecast = ref
                      .watch(forecastRevisaoProvider)
                      .any((d) => d.quantidade > 0);

                  final topo = <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.md),
                      child: Text(
                        _mensagemDoDia(hoje),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: VizColors.inkSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    // Próximo passo primeiro: a missão responde "o que
                    // estudar agora" antes de qualquer estatística.
                    const HeroMissaoHoje(),
                    const SizedBox(height: Spacing.md),
                    // Geralzão: faixa de KPIs, tudo de relance e clicável.
                    const HeroGeral(),
                    const SizedBox(height: Spacing.md),
                    const CardProntidao(),
                    const CardAlertas(),
                    const CardMelhorarHoje(),
                    const SizedBox(height: Spacing.md),
                  ];
                  final acao = <Widget>[
                    if (temQuests) const CardQuests(),
                    const CardPlano(),
                    if (temDesempenho) const CardDesempenho(),
                  ];
                  final progresso = <Widget>[
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
                  ];
                  final contexto = <Widget>[
                    if (ambienteAtivo == null) const CardAmbientes(),
                    const CardRankings(),
                    const CardSimulados(),
                    const CardGamificacao(),
                    const CardAnos(),
                    const TilesResumo(),
                  ];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.lg,
                      Spacing.xs,
                      Spacing.lg,
                      88,
                    ),
                    children: [
                      ...topo,
                      if (tresColunas)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _coluna(acao)),
                            const SizedBox(width: Spacing.md),
                            Expanded(child: _coluna(progresso)),
                            const SizedBox(width: Spacing.md),
                            Expanded(child: _coluna(contexto)),
                          ],
                        )
                      else if (duasColunas)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _coluna([...acao, ...progresso])),
                            const SizedBox(width: Spacing.md),
                            Expanded(child: _coluna(contexto)),
                          ],
                        )
                      else
                        _coluna([...acao, ...progresso, ...contexto]),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

/// Coluna de cards com o vão padrão entre eles (token Spacing.md). Os cards
/// já chegam FILTRADOS (só os visíveis), então não há espaçador antes de um
/// card ausente — fim do "gap fantasma" das colunas.
Widget _coluna(List<Widget> cards) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < cards.length; i++) ...[
      if (i > 0) const SizedBox(height: Spacing.md),
      cards[i],
    ],
  ],
);

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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.auto_stories,
                size: 44,
                color: LuminaColors.safiraClara,
              ),
              const SizedBox(height: 14),
              Text(
                'Seu dashboard nasce do primeiro registro',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: VizColors.inkPrimary),
              ),
              const SizedBox(height: 6),
              const Text(
                'Cada sessão de estudo vira horas, gráficos, streak e '
                'sugestões do dia — tudo calculado automaticamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: VizColors.inkSecondary, fontSize: 13),
              ),
              const SizedBox(height: 18),
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
        ),
      ),
    );
  }
}
