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
import 'widgets/card_rankings.dart';
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
              maxWidth: 1280,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Tela larga: cards em 2 colunas — usa o monitor em vez
                  // de empilhar tudo numa coluna com sobra dos lados.
                  final duasColunas = constraints.maxWidth >= 980;
                  final topo = <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
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
                    // Geralzão: tudo de relance, clicável, sem rolar.
                    const HeroGeral(),
                    const SizedBox(height: 10),
                    const CardProntidao(),
                    const CardAlertas(),
                    const CardMelhorarHoje(),
                    const SizedBox(height: 10),
                  ];
                  final colunaA = <Widget>[
                    const CardRankings(),
                    const SizedBox(height: 10),
                    const CardPlano(),
                    const SizedBox(height: 10),
                    const CardDesempenho(),
                    const SizedBox(height: 10),
                    const CardGrafico(
                      titulo: 'Horas da semana por matéria',
                      child: BarrasSemana(),
                    ),
                    const SizedBox(height: 10),
                    const TilesResumo(),
                    const SizedBox(height: 10),
                  ];
                  final colunaB = <Widget>[
                    if (ambienteAtivo == null) ...[
                      const CardAmbientes(),
                      const SizedBox(height: 10),
                    ],
                    const CardQuests(),
                    const SizedBox(height: 10),
                    const CardSimulados(),
                    const SizedBox(height: 10),
                    const CardGrafico(
                      titulo: 'Evolução — últimos 14 dias',
                      child: LinhaEvolucao(),
                    ),
                    const SizedBox(height: 10),
                    const CardGrafico(
                      titulo: 'Distribuição total por matéria',
                      child: DonutDistribuicao(),
                    ),
                    const SizedBox(height: 10),
                    const CardGamificacao(),
                    const SizedBox(height: 10),
                    const CardAnos(),
                  ];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                    children: [
                      ...topo,
                      if (duasColunas)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Column(children: colunaA)),
                            const SizedBox(width: 10),
                            Expanded(child: Column(children: colunaB)),
                          ],
                        )
                      else ...[
                        ...colunaA,
                        ...colunaB,
                      ],
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
