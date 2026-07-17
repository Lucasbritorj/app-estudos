import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../registro/registro_form.dart';
import '../dashboard_providers.dart';
import 'chama_streak.dart';

/// "Geralzão": o dia inteiro de relance no topo — números, meta da semana
/// e atalhos. Tudo clicável (navega pelas abas via abaProvider).
class HeroGeral extends ConsumerWidget {
  const HeroGeral({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumo = ref.watch(resumoGeralProvider);
    final minutosHoje = resumo.minutosHoje;
    final minutosSemana = resumo.minutosSemana;
    final streak = resumo.streak;
    final total = resumo.total;
    final metaSemana = resumo.metaSemana;
    final progressoMeta = resumo.progressoMeta;
    final pendentes = resumo.pendentes;
    final atrasadas = resumo.atrasadas;

    void irPara(int aba) => ref.read(abaProvider.notifier).ir(aba);

    final corRevisoes = atrasadas > 0
        ? StatusColors.critico
        : (pendentes > 0 ? StatusColors.atencao : StatusColors.bom);

    // Tile tintado (pastel adaptado ao escuro): cor identifica a métrica,
    // texto continua branco por contraste.
    Widget stat(
      String rotulo,
      String valor,
      Color tinta, {
      Widget? icone,
      VoidCallback? onTap,
    }) {
      return Material(
        color: tinta.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tinta.withValues(alpha: 0.28)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icone != null) ...[
                      icone,
                      const SizedBox(width: 4),
                    ],
                    Text(
                      rotulo,
                      style: const TextStyle(
                        color: VizColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    if (onTap != null) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_outward,
                        size: 11,
                        color: VizColors.muted,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                // Troca de valor com fade curto — vida sem exagero.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(
                    valor,
                    key: ValueKey(valor),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: VizColors.inkPrimary,
                      fontWeight: FontWeight.w600,
                      // Dígitos de largura fixa: valor troca sem o tile
                      // "dançar" de largura.
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Sombra em camadas só no hero: é a superfície principal da tela e a
    // única que "flutua" — nos demais cards viraria ruído.
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        boxShadow: LuminaElevation.cardEmCamadas,
      ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  stat(
                    'Hoje',
                    formatarMinutos(minutosHoje),
                    LuminaColors.safiraClara,
                    onTap: () => irPara(Abas.cronometro),
                  ),
                  stat(
                    'Semana',
                    formatarMinutos(minutosSemana),
                    seriesColors[1],
                    onTap: () => irPara(Abas.cronometro),
                  ),
                  stat(
                    // Em risco fala primeiro; congelamento informa depois.
                    resumo.streakEmRisco
                        ? 'Streak — estude hoje'
                        : (resumo.streakCongelados > 0
                            ? 'Streak · ${resumo.streakCongelados} '
                                'protegido${resumo.streakCongelados == 1 ? '' : 's'}'
                            : 'Streak'),
                    '$streak ${streak == 1 ? 'dia' : 'dias'}',
                    LuminaColors.chama,
                    icone: ChamaAnimada(emRisco: resumo.streakEmRisco),
                  ),
                  stat('Total', formatarMinutos(total), seriesColors[4]),
                  stat(
                    'Revisões',
                    pendentes == 0
                        ? 'em dia'
                        : '$pendentes${atrasadas > 0 ? ' ($atrasadas atrasadas)' : ''}',
                    corRevisoes,
                    icone: Icon(Icons.event_repeat,
                        size: 13, color: corRevisoes),
                    onTap: () => irPara(Abas.revisoes),
                  ),
                  stat(
                    'Matérias',
                    '${resumo.qtdMaterias}',
                    seriesColors[6],
                    onTap: () => irPara(Abas.materias),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Meta batida = barra dourada com glow (celebração sutil,
                    // mesmo canal do streak/XP).
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: progressoMeta >= 1.0
                            ? LuminaElevation.glow(
                                LuminaColors.ouro,
                                alpha: 0.30,
                              )
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progressoMeta,
                          minHeight: 8,
                          backgroundColor: VizColors.gridline,
                          color: progressoMeta >= 1.0
                              ? LuminaColors.ouro
                              : LuminaColors.safiraClara,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Meta da semana: ${formatarMinutos(minutosSemana)} de '
                      '${formatarMinutos(metaSemana)} '
                      '(${(progressoMeta * 100).toStringAsFixed(0)}%)',
                      style: const TextStyle(
                        color: VizColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Wrap(
                  spacing: 8,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
