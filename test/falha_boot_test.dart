import 'package:app_estudos/core/boot/falha_boot.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Prova da superfície de falha de boot.
///
/// O defeito que isto fecha: `main()` era uma sequência de `await` sem
/// `try`/`catch`, então qualquer falha ao abrir o Hive (box corrompido,
/// IndexedDB bloqueado em aba anônima, cota estourada) impedia `runApp()` de
/// ser chamado e o usuário via um retângulo branco permanente — sem mensagem,
/// sem botão, sem pista. Num app local-first isso é pior que um crash: a
/// reação natural de quem vê tela branca é limpar os dados do site, que é
/// exatamente o único gesto irreversível disponível.
///
/// Limite honesto deste arquivo: ele prova a TELA, não a ligação dela com o
/// `main()`. `HiveBoxes.openAll()` é estático e injetar falha nele exigiria
/// mudar arquitetura. A ligação fecha no `integration_test` (item 8 do plano).
void main() {
  Widget montar({
    PassoBoot passo = PassoBoot.armazenamento,
    Object erro = 'HiveError: box já aberto por outra aba',
    Future<void> Function()? aoTentarNovamente,
  }) {
    return FalhaBootApp(
      passo: passo,
      erro: erro,
      pilha: StackTrace.current,
      aoTentarNovamente: aoTentarNovamente ?? () async {},
    );
  }

  testWidgets('falha de armazenamento mostra tela, nunca área em branco', (
    tester,
  ) async {
    await tester.pumpWidget(montar());

    expect(find.text(PassoBoot.armazenamento.titulo), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
    // Se isto falhar, a tela voltou a ser um retângulo vazio.
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets('cada passo do boot tem texto próprio', (tester) async {
    await tester.pumpWidget(montar(passo: PassoBoot.migracao));
    expect(find.text(PassoBoot.migracao.titulo), findsOneWidget);
    expect(find.text(PassoBoot.armazenamento.titulo), findsNothing);
  });

  testWidgets('a tela desaconselha limpar os dados em vez de sugerir', (
    tester,
  ) async {
    await tester.pumpWidget(montar());

    // O texto exato importa: é a única defesa contra o usuário resolver a tela
    // branca apagando o próprio histórico.
    expect(find.textContaining('Não limpe os dados'), findsOneWidget);
    expect(find.textContaining('não tem volta'), findsOneWidget);

    // E não pode existir nenhum convite ao gesto destrutivo.
    expect(find.textContaining('Limpar dados'), findsNothing);
    expect(find.textContaining('Reinstalar'), findsNothing);
  });

  testWidgets('"Tentar de novo" reexecuta o boot', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
addTearDown(() => tester.binding.setSurfaceSize(null));
int tentativas = 0;
        await tester.pumpWidget(
      montar(aoTentarNovamente: () async => tentativas++),
    );

    await tester.tap(find.text('Tentar de novo'));
    // `pump` e não `pumpAndSettle`: o botão troca para um
    // CircularProgressIndicator enquanto tenta, e animação infinita faria
    // `pumpAndSettle` girar para sempre.
    await tester.pump();
    await tester.pump();

    expect(tentativas, 1);
  });

  testWidgets('detalhe técnico fica escondido até ser pedido', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      montar(erro: 'FormatException: schemaVersion inválida'),
    );

    expect(find.byType(SelectableText), findsNothing);

    await tester.tap(find.text('Ver detalhes técnicos'));
    await tester.pump();

    expect(find.byType(SelectableText), findsOneWidget);
    expect(
      find.textContaining('FormatException: schemaVersion inválida'),
      findsOneWidget,
    );
  });

  testWidgets('widget de erro de UI se vira sem Directionality herdada', (
    tester,
  ) async {
    // Contraprova do motivo do `Directionality` interno: um widget comum
    // lança sem ela, e a falha pode acontecer ACIMA do MaterialApp — onde não
    // existe nenhuma no contexto. Por isso o widget é montado aqui cru, sem
    // nenhum wrapper.
    await tester.pumpWidget(
      construirWidgetDeErro(
        FlutterErrorDetails(
          exception: Exception('RenderFlex overflowed'),
          library: 'teste',
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('não pôde ser exibida'), findsOneWidget);
    expect(find.textContaining('RenderFlex overflowed'), findsOneWidget);
  });
}
