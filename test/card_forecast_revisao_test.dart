import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:app_estudos/features/dashboard/widgets/card_forecast_revisao.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regressão do M-18 (parte widget): o FractionallySizedBox da barra definia
/// heightFactor sem widthFactor — o DecoratedBox (sem child próprio) recebia
/// constraints de largura *loose* e colapsava para 0px. Resultado: "pico: N
/// em hoje" correto no rodapé, faixa do gráfico inteiramente vazia acima.
void main() {
  testWidgets('barra do dia de pico renderiza com largura > 0', (
    tester,
  ) async {
    final hoje = DateTime(2026, 7, 24);
    final dados = [
      (dia: hoje, quantidade: 8),
      for (var i = 1; i < 30; i++) (dia: hoje.add(Duration(days: i)), quantidade: 0),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [forecastRevisaoProvider.overrideWithValue(dados)],
        child: const MaterialApp(
          home: Scaffold(body: CardForecastRevisao()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('pico: 8 em hoje'), findsOneWidget);

    final caixas = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .toList();
    expect(caixas, isNotEmpty);

    final larguras = tester
        .elementList(find.byType(DecoratedBox))
        .map((e) => (e.renderObject as RenderBox).size.width)
        .toList();

    // Antes da correção TODAS as barras saíam com 0px de largura — o bug
    // não distinguia dia de pico dos demais, colapsava a faixa inteira.
    expect(
      larguras.any((w) => w > 0),
      isTrue,
      reason:
          'nenhuma barra tem largura > 0 — widthFactor ausente no '
          'FractionallySizedBox voltou a colapsar a barra para 0px',
    );
  });
}
