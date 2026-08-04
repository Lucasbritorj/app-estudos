import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/stats_service.dart' show StatsService;
import '../dashboard_providers.dart';

/// Heatmap de constância estilo calendário de contribuições: colunas =
/// semanas (seg-dom), células = dias, intensidade sequencial de um só tom
/// (safira) pela carga de minutos. Dia protegido pelo congelamento do
/// streak ganha contorno na cor da chama + entrada na legenda (nunca só
/// cor). Largura decide quantas semanas cabem — sem scroll interno.
class CardHeatmapConstancia extends ConsumerWidget {
  const CardHeatmapConstancia({super.key});

  /// Nível sequencial 0-4 por carga do dia. Faixas fixas e documentadas:
  /// 0 = sem estudo real (< piso), 1 = <30min, 2 = <1h, 3 = <2h, 4 = 2h+.
  ///
  /// M-08 — o corte do nível 0 é o MESMO piso do streak
  /// ([StatsService.pisoMinutosStreak]), não `> 0`. Antes, um dia de 5 min
  /// acendia o quadradinho enquanto a chama zerava logo acima, no mesmo
  /// scroll: o card se chama "Constância" e precisa contar constância pela
  /// régua que o app usa para constância. Os minutos abaixo do piso não somem
  /// — seguem no total e no rótulo de acessibilidade, só não pintam o dia
  /// como cumprido.
  static int nivelPara(int minutos) {
    if (minutos < StatsService.pisoMinutosStreak) return 0;
    if (minutos < 30) return 1;
    if (minutos < 60) return 2;
    if (minutos < 120) return 3;
    return 4;
  }

  /// Tom sequencial sobre o fundo escuro: um só matiz (safira clara),
  /// opacidade crescente — magnitude, não identidade.
  static Color corDoNivel(int nivel) => switch (nivel) {
    0 => const Color(0x0FFFFFFF),
    1 => LuminaColors.safiraClara.withValues(alpha: 0.28),
    2 => LuminaColors.safiraClara.withValues(alpha: 0.50),
    3 => LuminaColors.safiraClara.withValues(alpha: 0.75),
    _ => LuminaColors.safiraClara,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(heatmapDadosProvider);
    if (dados.minutosPorDia.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final semanas =
                ((constraints.maxWidth - _HeatmapPainter.gutterEsquerda) /
                        _HeatmapPainter.passo)
                    .floor()
                    .clamp(4, 52);
            final inicio = DateTime(
              dados.hoje.year,
              dados.hoje.month,
              dados.hoje.day - (dados.hoje.weekday - 1) - 7 * (semanas - 1),
            );
            var total = 0;
            var diasEstudados = 0;
            for (final e in dados.minutosPorDia.entries) {
              if (!e.key.isBefore(inicio)) {
                // Total soma TUDO (minuto estudado é minuto estudado), mas a
                // contagem de dias usa o piso — senão o rótulo dizia "12 dias
                // de estudo" com a chama em 4. Mesma régua do nivelPara.
                total += e.value;
                if (e.value >= StatsService.pisoMinutosStreak) {
                  diasEstudados++;
                }
              }
            }
            final protegidos = dados.diasCongelados
                .where((d) => !d.isBefore(inicio))
                .length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Constância',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: VizColors.inkPrimary,
                  ),
                ),
                Text(
                  '$diasEstudados dias de estudo · '
                  '${formatarMinutos(total)} nas últimas $semanas semanas',
                  style: const TextStyle(color: VizColors.muted, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Semantics(
                  container: true,
                  label:
                      'Constância: $diasEstudados dias estudados nas últimas '
                      '$semanas semanas, total de ${formatarMinutos(total)}'
                      '${protegidos > 0 ? ', $protegidos dias protegidos pelo congelamento' : ''}.',
                  // CustomPaint não produz nó nenhum sozinho, mas sem isto um
                  // leitor de tela ainda tentaria varrer o Canvas em busca de
                  // texto — trava a leitura no resumo já falado acima.
                  excludeSemantics: true,
                  child: SizedBox(
                    height: _HeatmapPainter.alturaTotal,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _HeatmapPainter(
                        minutosPorDia: dados.minutosPorDia,
                        diasCongelados: dados.diasCongelados,
                        hoje: dados.hoje,
                        semanas: semanas,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'menos',
                      style: TextStyle(color: VizColors.muted, fontSize: 10),
                    ),
                    const SizedBox(width: 4),
                    for (var nivel = 0; nivel <= 4; nivel++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: _Quadradinho(cor: corDoNivel(nivel)),
                      ),
                    const SizedBox(width: 4),
                    const Text(
                      'mais',
                      style: TextStyle(color: VizColors.muted, fontSize: 10),
                    ),
                    if (protegidos > 0) ...[
                      const Spacer(),
                      _Quadradinho(
                        cor: corDoNivel(0),
                        borda: LuminaColors.chama,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'protegido',
                        style: TextStyle(color: VizColors.muted, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Quadradinho extends StatelessWidget {
  final Color cor;
  final Color? borda;

  const _Quadradinho({required this.cor, this.borda});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: cor,
        borderRadius: BorderRadius.circular(2),
        border: borda == null ? null : Border.all(color: borda!, width: 1.5),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  static const celula = 11.0;
  static const espaco = 2.0;
  static const passo = celula + espaco;
  static const gutterEsquerda = 22.0;
  static const gutterTopo = 14.0;
  static const alturaTotal = gutterTopo + 7 * passo;

  static const _meses = [
    'jan', 'fev', 'mar', 'abr', 'mai', 'jun', //
    'jul', 'ago', 'set', 'out', 'nov', 'dez',
  ];

  final Map<DateTime, int> minutosPorDia;
  final Set<DateTime> diasCongelados;
  final DateTime hoje;
  final int semanas;

  _HeatmapPainter({
    required this.minutosPorDia,
    required this.diasCongelados,
    required this.hoje,
    required this.semanas,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final pincel = Paint();
    final contorno = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = LuminaColors.chama;

    // Coluna mais à direita = semana de hoje; segunda-feira é a linha 0.
    final inicioSemanaAtual = DateTime(
      hoje.year,
      hoje.month,
      hoje.day - (hoje.weekday - 1),
    );

    void rotulo(String texto, Offset posicao) {
      final tp = TextPainter(
        text: TextSpan(
          text: texto,
          style: const TextStyle(color: VizColors.muted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, posicao);
    }

    // seg/qua/sex no gutter esquerdo, como âncora de leitura.
    for (final (linha, letra) in const [(0, 'seg'), (2, 'qua'), (4, 'sex')]) {
      rotulo(letra, Offset(0, gutterTopo + linha * passo + 1));
    }

    int? ultimoMes;
    for (var coluna = 0; coluna < semanas; coluna++) {
      final inicioSemana = DateTime(
        inicioSemanaAtual.year,
        inicioSemanaAtual.month,
        inicioSemanaAtual.day - 7 * (semanas - 1 - coluna),
      );
      final x = gutterEsquerda + coluna * passo;

      // Rótulo do mês na coluna em que ele começa (sem colidir na borda).
      if (ultimoMes != inicioSemana.month && coluna <= semanas - 3) {
        if (ultimoMes != null) {
          rotulo(_meses[inicioSemana.month - 1], Offset(x, 0));
        }
        ultimoMes = inicioSemana.month;
      }

      for (var linha = 0; linha < 7; linha++) {
        final dia = DateTime(
          inicioSemana.year,
          inicioSemana.month,
          inicioSemana.day + linha,
        );
        if (dia.isAfter(hoje)) continue;
        final nivel = CardHeatmapConstancia.nivelPara(minutosPorDia[dia] ?? 0);
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, gutterTopo + linha * passo, celula, celula),
          const Radius.circular(2),
        );
        pincel.color = CardHeatmapConstancia.corDoNivel(nivel);
        canvas.drawRRect(r, pincel);
        if (diasCongelados.contains(dia)) {
          canvas.drawRRect(r.deflate(0.75), contorno);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter anterior) =>
      anterior.minutosPorDia != minutosPorDia ||
      anterior.diasCongelados != diasCongelados ||
      anterior.hoje != hoje ||
      anterior.semanas != semanas;
}
