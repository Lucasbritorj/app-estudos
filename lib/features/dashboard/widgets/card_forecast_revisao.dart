import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
import '../dashboard_providers.dart';

/// Forecast de carga de revisão dos próximos 30 dias — barras por dia, para
/// antecipar picos de backlog antes de afundar neles. Só aparece quando há
/// alguma revisão pendente na janela.
class CardForecastRevisao extends ConsumerWidget {
  const CardForecastRevisao({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(forecastRevisaoProvider);
    final total = dados.fold(0, (s, d) => s + d.quantidade);
    if (total == 0) return const SizedBox.shrink();
    final maxQtd = dados.fold(0, (m, d) => d.quantidade > m ? d.quantidade : m);
    final pico = dados.reduce((a, b) => b.quantidade > a.quantidade ? b : a);

    return Card(
      child: InkWell(
        onTap: () => ref.read(abaProvider.notifier).ir(Abas.revisoes),
        borderRadius: BorderRadius.circular(Radii.lg),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Revisões — próximos 30 dias',
                        style: LuminaText.cardTitle),
                  ),
                  Text(
                    '$total no total',
                    style: const TextStyle(color: VizColors.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: Spacing.md),
              SizedBox(
                height: 64,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < dados.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0.8),
                          child: _Barra(
                            fracao: maxQtd == 0
                                ? 0
                                : dados[i].quantidade / maxQtd,
                            // Hoje (dia 0) é a fila que já venceu — realça.
                            cor: i == 0
                                ? LuminaColors.chama
                                : LuminaColors.safiraClara,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.xs),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('hoje',
                      style: TextStyle(color: VizColors.muted, fontSize: 10)),
                  Text(
                    'pico: ${pico.quantidade} em ${_rotuloDia(dados.first.dia, pico.dia)}',
                    style: const TextStyle(color: VizColors.muted, fontSize: 10),
                  ),
                  const Text('+30d',
                      style: TextStyle(color: VizColors.muted, fontSize: 10)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _rotuloDia(DateTime hoje, DateTime dia) {
    final delta = dia.difference(hoje).inDays;
    return delta == 0 ? 'hoje' : 'D+$delta';
  }
}

class _Barra extends StatelessWidget {
  final double fracao;
  final Color cor;

  const _Barra({required this.fracao, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: FractionallySizedBox(
            alignment: Alignment.bottomCenter,
            // Mínimo visível para dias com carga; zero fica rente à base.
            heightFactor: fracao == 0 ? 0.02 : (0.1 + 0.9 * fracao),
            // BUG (M-18): sem widthFactor, o DecoratedBox (sem child próprio)
            // recebe constraints de largura *loose* e colapsa para 0px —
            // altura certa, largura zero, barra inteiramente invisível.
            // É por isso que "Revisões — próximos 30 dias" sempre renderizou
            // com a faixa do gráfico vazia, mesmo com "pico: N em hoje"
            // correto no rodapé (o dado estava certo; só a barra não pintava).
            widthFactor: 1.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fracao == 0 ? VizColors.gridline : cor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
