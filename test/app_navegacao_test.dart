import 'dart:io';

import 'package:app_estudos/app.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/features/caderno/caderno_screen.dart';
import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:app_estudos/features/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// App inteiro de pé: shell -> troca de aba -> `Navigator.push` -> voltar.
///
/// Por que vale: o resto de `test/` monta TELA ISOLADA
/// (`MaterialApp(home: CadernoScreen())`). Nada provava que o caminho real do
/// usuário — `AppEstudos` -> `_HomeShell` -> aba "Mais" -> push -> pop —
/// sobrevive. É a classe de defeito que produziu `b5199c6` e `bd11b38`: peças
/// corretas isoladamente, quebradas no encontro.
///
/// Por que NÃO fica em `integration_test/`: `flutter_tools` decide o modo pelo
/// DIRETÓRIO (`_shouldRunAsIntegrationTests`, test.dart:888) e, sendo
/// integration test, exige `findTargetDevice()` — sem device, `throwToolExit`.
/// Não existe caminho headless. Como o valor aqui é montar o app inteiro, e
/// não dirigir um device, isto é um widget test — e de quebra já entra no
/// `flutter test` do CI que existe hoje.
///
/// Setup copiado de `test/sidebar_test.dart`. O override de `hojeProvider` não
/// é preciosismo: o provider real agenda um `Timer` até a próxima meia-noite e
/// a suíte falha com "A Timer is still pending".
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_app_nav_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
    // Sem isto o shell abre no OnboardingScreen e não existe aba nenhuma.
    await Hive.box<Map>(HiveBoxes.config).put(
      'config',
      const Configuracoes(onboardingConcluido: true).toJson(),
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  /// 800x1200: abaixo do breakpoint de 1080 (`_larguraSidebar`, app.dart:76),
  /// então o shell usa a bottom bar — o caminho de celular, alvo real do
  /// produto. A sidebar já tem cobertura em `test/sidebar_test.dart`.
  Future<ProviderContainer> abrirApp(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final container = ProviderContainer(
      overrides: [hojeProvider.overrideWithValue(DateTime(2026, 8, 3))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AppEstudos(),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('app sobe no Dashboard, com base vazia e sem exceção', (
    tester,
  ) async {
    final container = await abrirApp(tester);

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(container.read(abaProvider), Abas.dashboard);
    // Estado degenerado (zero matéria, zero registro) não pode derrubar o
    // dashboard: é a primeira coisa que o usuário novo vê.
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dashboard -> Mais -> Caderno de Erros -> voltar', (
    tester,
  ) async {
    final container = await abrirApp(tester);

    // `find.text('Mais')` casaria DOIS widgets: o rótulo da NavigationBar e o
    // título do AppBar de MaisScreen. O IndexedStack (app.dart:95) constrói as
    // 5 abas de uma vez, então a tela "Mais" já está na árvore desde o boot,
    // mesmo sem estar selecionada. Escopo obrigatório.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Mais'),
      ),
    );
    await tester.pumpAndSettle();

    // Pelo mesmo motivo do IndexedStack, `find.byType(DashboardScreen)`
    // continua achando o widget aqui — ele existe, só não é pintado. A troca
    // de aba se prova pelo estado, não pela ausência na árvore.
    expect(container.read(abaProvider), Abas.mais);

    final itemCaderno = find.widgetWithText(ListTile, 'Caderno de Erros');
    expect(itemCaderno, findsOneWidget);
    await tester.ensureVisible(itemCaderno);
    await tester.pumpAndSettle();
    await tester.tap(itemCaderno);
    await tester.pumpAndSettle();

    expect(find.byType(CadernoScreen), findsOneWidget);
    // Com o caderno vazio, `CadernoScreen` esconde a TabBar e mostra o
    // EstadoVazio (caderno_screen.dart:64-71) — asserção casada com o setup,
    // que não semeia questão nenhuma. Provar o estado vazio pelo caminho real
    // de navegação é o ponto; as abas têm cobertura em caderno_screen_test.
    expect(find.text('Caderno de erros vazio'), findsOneWidget);
    expect(find.byTooltip('Nova questão errada'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Voltar pelo TIPO do widget, não por tooltip nem por `pageBack()`.
    //
    // `pageBack()` parecia a opção robusta e é o oposto disso: ele procura
    // `find.byTooltip('Back')` — literal em inglês, cravado no código
    // (widget_tester.dart:1171) — e, não achando, cai para
    // `CupertinoNavigationBarBackButton`. Este app roda em pt-BR com
    // `GlobalMaterialLocalizations`, então o tooltip é "Voltar", o primeiro
    // finder vem vazio e o segundo não existe num app Material: "Found 0".
    //
    // `find.byType(BackButton)` não depende de idioma. O leading automático do
    // AppBar é literalmente `const BackButton()` (app_bar.dart:1014), e só
    // aparece em rota empilhada (`parentRoute.impliesAppBarDismissal`) — as
    // telas do shell são a rota raiz e não têm nenhum. Daí a unicidade.
    final voltar = find.byType(BackButton);
    expect(voltar, findsOneWidget);
    await tester.tap(voltar);
    await tester.pumpAndSettle();

    expect(find.byType(CadernoScreen), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    // O shell preserva a aba: voltar do push não reseta para o Dashboard.
    expect(container.read(abaProvider), Abas.mais);
    expect(tester.takeException(), isNull);
  });
}
