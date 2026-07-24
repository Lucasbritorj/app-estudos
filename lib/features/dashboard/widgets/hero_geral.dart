import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../registro/registro_form.dart';
import '../dashboard_providers.dart';
import 'chama_streak.dart';

/// "Geralzão": a faixa de KPIs do topo — o dia inteiro de relance, em números
/// grandes na voz tipográfica de marca (Display tabular). Cada tile é
/// clicável e navega pela aba correspondente.
class HeroGeral extends ConsumerWidget {
  const HeroGeral({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumo = ref.watch(resumoGeralProvider);
    final progressoMeta = resumo.progressoMeta;

    void irPara(int aba) => ref.read(abaProvider.notifier).ir(aba);

    final corRevisoes = resumo.atrasadas > 0
        ? StatusColors.critico
        : (resumo.pendentes > 0 ? StatusColors.atencao : StatusColors.bom);

    final tiles = <Widget>[
      _Kpi(
        rotulo: 'Hoje',
        valor: formatarMinutos(resumo.minutosHoje),
        tinta: LuminaColors.safiraClara,
        onTap: () => irPara(Abas.cronometro),
      ),
      _Kpi(
        rotulo: 'Semana',
        valor: formatarMinutos(resumo.minutosSemana),
        tinta: seriesColors[1],
        onTap: () => irPara(Abas.cronometro),
      ),
      _Kpi(
        rotulo: resumo.streakEmRisco
            ? 'Streak · estude hoje'
            : (resumo.streakCongelados > 0
                  ? 'Streak · ${resumo.streakCongelados} protegido'
                        '${resumo.streakCongelados == 1 ? '' : 's'}'
                  : 'Streak'),
        valor: '${resumo.streak}',
        sufixo: resumo.streak == 1 ? 'dia' : 'dias',
        tinta: LuminaColors.chama,
        icone: ChamaAnimada(emRisco: resumo.streakEmRisco),
      ),
      _Kpi(
        rotulo: 'Total',
        valor: formatarMinutos(resumo.total),
        tinta: seriesColors[4],
      ),
      _Kpi(
        rotulo: 'Revisões',
        valor: resumo.pendentes == 0 ? 'em dia' : '${resumo.pendentes}',
        sufixo: resumo.pendentes > 0 && resumo.atrasadas > 0
            ? '${resumo.atrasadas} atrasadas'
            : null,
        tinta: corRevisoes,
        icone: Icon(Icons.event_repeat, size: 13, color: corRevisoes),
        onTap: () => irPara(Abas.revisoes),
      ),
      _Kpi(
        rotulo: 'Matérias',
        valor: '${resumo.qtdMaterias}',
        tinta: seriesColors[6],
        onTap: () => irPara(Abas.materias),
      ),
    ];

    // Sombra em camadas só no hero: é a superfície principal e a única que
    // "flutua" — nos demais cards viraria ruído.
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        boxShadow: LuminaElevation.cardEmCamadas,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, c) {
                  // Grade fluida de KPIs: largura mínima por tile, quebra
                  // sozinha — sem "dança" de largura (números tabulares).
                  final cols = (c.maxWidth / 150).floor().clamp(2, 6);
                  final larguraTile =
                      (c.maxWidth - (cols - 1) * Spacing.sm) / cols;
                  return Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.sm,
                    children: [
                      for (final t in tiles)
                        SizedBox(width: larguraTile, child: t),
                    ],
                  );
                },
              ),
              const SizedBox(height: Spacing.lg),
              _BarraMeta(
                progresso: progressoMeta,
                progressoReal: resumo.progressoMetaReal,
                minutosSemana: resumo.minutosSemana,
                metaSemana: resumo.metaSemana,
              ),
              const SizedBox(height: Spacing.md),
              Wrap(
                spacing: Spacing.sm,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('Registrar sessão'),
                    onPressed: () => mostrarFormularioRegistro(context),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.timer_outlined, size: 16),
                    label: const Text('Cronômetro'),
                    onPressed: () => irPara(Abas.cronometro),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tile de KPI: rótulo pequeno + número grande na fonte Display tabular.
/// Cor identifica a métrica; o número fica branco por contraste.
class _Kpi extends StatelessWidget {
  final String rotulo;
  final String valor;
  final String? sufixo;
  final Color tinta;
  final Widget? icone;
  final VoidCallback? onTap;

  const _Kpi({
    required this.rotulo,
    required this.valor,
    required this.tinta,
    this.sufixo,
    this.icone,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tinta.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(Radii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: tinta.withValues(alpha: 0.28)),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm + 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icone != null) ...[icone!, const SizedBox(width: 4)],
                  Flexible(
                    child: Text(
                      rotulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: VizColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.arrow_outward,
                      size: 11,
                      color: VizColors.muted,
                    ),
                ],
              ),
              const SizedBox(height: Spacing.xs),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: Row(
                  key: ValueKey('$valor$sufixo'),
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        valor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: LuminaText.numeroHero.copyWith(
                          fontSize: 24,
                          color: VizColors.inkPrimary,
                        ),
                      ),
                    ),
                    if (sufixo != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        sufixo!,
                        style: const TextStyle(
                          color: VizColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
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

/// Barra de progresso da meta semanal — dourada com glow quando batida
/// (mesmo canal de celebração do streak/XP).
class _BarraMeta extends StatelessWidget {
  final double progresso;
  final double progressoReal;
  final int minutosSemana;
  final int metaSemana;

  const _BarraMeta({
    required this.progresso,
    required this.progressoReal,
    required this.minutosSemana,
    required this.metaSemana,
  });

  @override
  Widget build(BuildContext context) {
    final batida = progresso >= 1.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            boxShadow: batida
                ? LuminaElevation.glow(LuminaColors.ouro, alpha: 0.30)
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicator(
              value: progresso,
              minHeight: 8,
              backgroundColor: VizColors.gridline,
              color: batida ? LuminaColors.ouro : LuminaColors.safiraClara,
            ),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Text(
          'Meta da semana: ${formatarMinutos(minutosSemana)} de '
          '${formatarMinutos(metaSemana)} '
          // Percentual SEM teto — a barra visual clampa em 100% (não dá pra
          // desenhar 186% de largura), mas o texto teria que mentir junto.
          '(${(progressoReal * 100).toStringAsFixed(0)}%)',
          style: const TextStyle(color: VizColors.muted, fontSize: 11),
        ),
      ],
    );
  }
}
