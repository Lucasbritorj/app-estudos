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


  testWidgets('a11y: 30 barras mudas viram um resumo falado', (tester) async {
    final handle = tester.ensureSemantics();
    final hoje = DateTime(2026, 7, 24);
    final dados = [
      (dia: hoje, quantidade: 2),
      (dia: hoje.add(const Duration(days: 1)), quantidade: 0),
      (dia: hoje.add(const Duration(days: 2)), quantidade: 0),
      (dia: hoje.add(const Duration(days: 3)), quantidade: 9),
      for (var i = 4; i < 30; i++)
        (dia: hoje.add(Duration(days: i)), quantidade: 0),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [forecastRevisaoProvider.overrideWithValue(dados)],
        child: const MaterialApp(home: Scaffold(body: CardForecastRevisao())),
      ),
    );
    await tester.pump();

    // O card inteiro era um InkWell anônimo com 30 DecoratedBox sem texto: o
    // leitor não tinha o que anunciar. "D+3" também não se fala — vira
    // "em 3 dias".
    expect(
      find.bySemanticsLabel(
        'Carga de revisões dos próximos 30 dias: 11 revisões no total, '
        'pico de 9 em 3 dias. Abrir revisões',
      ),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('a11y: pico hoje fala "hoje", não "em 0 dias"', (tester) async {
    final handle = tester.ensureSemantics();
    final hoje = DateTime(2026, 7, 24);
    final dados = [
      (dia: hoje, quantidade: 1),
      for (var i = 1; i < 30; i++)
        (dia: hoje.add(Duration(days: i)), quantidade: 0),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [forecastRevisaoProvider.overrideWithValue(dados)],
        child: const MaterialApp(home: Scaffold(body: CardForecastRevisao())),
      ),
    );
    await tester.pump();

    // Singular também precisa concordar: "1 revisão", não "1 revisões".
    expect(
      find.bySemanticsLabel(
        'Carga de revisões dos próximos 30 dias: 1 revisão no total, '
        'pico de 1 hoje. Abrir revisões',
      ),
      findsOneWidget,
    );

    handle.dispose();
  });

  testWidgets('a11y: o nome NÃO colide com o de CardRevisoesHoje', (
    tester,
  ) async {
    // Os dois cards levam para Abas.revisoes. Se soassem igual, o usuário de
    // leitor de tela não saberia qual está focando.
    final handle = tester.ensureSemantics();
    final hoje = DateTime(2026, 7, 24);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          forecastRevisaoProvider.overrideWithValue([
            (dia: hoje, quantidade: 3),
            for (var i = 1; i < 30; i++)
              (dia: hoje.add(Duration(days: i)), quantidade: 0),
          ]),
        ],
        child: const MaterialApp(home: Scaffold(body: CardForecastRevisao())),
      ),
    );
    await tester.pump();

    expect(find.bySemanticsLabel(RegExp('^Ver todas as revisões')), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('^Carga de revisões dos próximos 30 dias')),
      findsOneWidget,
    );

    handle.dispose();
  });
}
