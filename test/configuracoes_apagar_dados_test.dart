import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:app_estudos/features/configuracoes/configuracoes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Trava dupla do wipe (F6): o botão destrutivo só habilita quando o texto
/// digitado bate com "APAGAR" (trim + upper), e a confirmação de fato chama
/// ApagarDadosUseCase.apagarTudo() (mesmo setUp de apagar_dados_test.dart).
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_wipe_ui_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> semear() async {
    await container.read(ambientesProvider.notifier).salvar(
          Ambiente(id: 'amb1', nome: 'SEFAZ', criadoEm: DateTime(2026, 1, 1)),
        );
    await container.read(materiasProvider.notifier).salvar(
          Materia(
            id: 'm1',
            nome: 'AFO',
            corSlot: 0,
            ambienteId: 'amb1',
            criadaEm: DateTime(2026, 1, 1),
          ),
        );
    await container.read(registrosProvider.notifier).salvar(
          RegistroHora(
            id: 'r1',
            data: DateTime(2026, 1, 2),
            materiaId: 'm1',
            minutos: 60,
          ),
        );
    await container.read(revisoesProvider.notifier).salvar(
          Revisao(
            id: 'rev1',
            materiaId: 'm1',
            titulo: 'Revisão AFO',
            dataAgendada: DateTime(2026, 1, 9),
            intervaloDias: 7,
          ),
        );
  }

  Future<void> abrirDialogo(WidgetTester tester) async {
    // Viewport padrão (800x600) é baixa demais: o ListTile da zona de perigo
    // fica no fim do ListView e scrollUntilVisible só garante uma fração
    // visível, não o suficiente para o tap acertar o centro do widget.
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ConfiguracoesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Apagar todos os dados'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Apagar todos os dados'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'botão fica desabilitado sem "APAGAR" e habilita com o texto exato',
      (tester) async {
    await tester.runAsync(semear);
    await abrirDialogo(tester);

    // Contagem exata do que será destruído, no corpo do diálogo.
    expect(
      find.textContaining('1 registros, 1 matérias'),
      findsOneWidget,
    );

    final botao = find.widgetWithText(FilledButton, 'Apagar tudo');
    expect(botao, findsOneWidget);
    expect(tester.widget<FilledButton>(botao).onPressed, isNull);

    // Escopado ao diálogo: a ConfiguracoesScreen por trás tem outros 2
    // TextField (Intervalos, Meta semanal) que continuam na árvore sob o
    // modal — find.byType(TextField) cru seria ambíguo.
    final campo = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(campo, 'apagartudo');
    await tester.pump();
    expect(tester.widget<FilledButton>(botao).onPressed, isNull);

    // trim().toUpperCase(): minúsculo com espaço em volta também confirma.
    await tester.enterText(campo, '  apagar  ');
    await tester.pump();
    expect(tester.widget<FilledButton>(botao).onPressed, isNotNull);
  });

  testWidgets('confirmar apaga tudo, fecha o diálogo e mostra snackbar',
      (tester) async {
    await tester.runAsync(semear);
    await abrirDialogo(tester);

    final campo = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(campo, 'APAGAR');
    await tester.pump();

    final botao = find.widgetWithText(FilledButton, 'Apagar tudo');
    // apagarTudo() faz várias escritas reais no Hive em sequência — precisa
    // de runAsync (fake-async do testWidgets nunca entrega esses awaits).
    await tester.runAsync(() async {
      await tester.tap(botao);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();

    expect(container.read(materiasProvider), isEmpty);
    expect(container.read(registrosProvider), isEmpty);
    expect(container.read(revisoesProvider), isEmpty);
    expect(container.read(ambientesProvider), isEmpty);
    // "Apagar todos os dados" também é o texto do ListTile por trás (mesmo
    // rótulo do título do diálogo) — a prova inequívoca do fechamento é o
    // AlertDialog ter saído da árvore (os outros 2 TextField da tela de
    // Configurações — Intervalos, Meta semanal — continuam lá normalmente).
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Todos os dados foram apagados.'), findsOneWidget);
  });
}
