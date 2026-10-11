import 'package:app_estudos/app.dart';
import 'package:app_estudos/core/notificacoes/notificacoes_service.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';

/// Q9: registrar sessão teórica que completa a aula persiste 1 registro,
/// cria a primeira revisão com aulaId/intervalo 7 e a mostra na aba Revisões.
///
/// Pré-condição local: matéria e aula de 4 páginas. A ação passa pela UI de
/// registro e por [SessaoEstudoUseCase]. Hive do browser de teste é apagado
/// no fim. Concursos e lembretes ficam desligados — sem rede.
/// Conclusão da revisão fica fora deste caso: o diálogo agrega exceções
/// não discriminadas no runner web e não faz parte do cruzamento pedido.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const materiaId = 'q9-materia';
  const aulaId = 'q9-aula';
  const nomeMateria = 'Q9 Direito';
  const nomeAula = 'Aula 00';

  setUp(() async {
    NotificacoesService.habilitadas = false;
    await Hive.initFlutter('q9');
    await Hive.deleteFromDisk();
    await Hive.initFlutter('q9');
    await HiveBoxes.openAll();
    await HiveBoxes.migrar();
    await Hive.box<Map>(HiveBoxes.config).put(
      'config',
      const Configuracoes(onboardingConcluido: true).toJson(),
    );
    final criada = DateTime(2026, 10, 1);
    await Hive.box<Map>(HiveBoxes.materias).put(
      materiaId,
      Materia(
        id: materiaId,
        nome: nomeMateria,
        ambienteId: Ambiente.geralId,
        corSlot: 0,
        criadaEm: criada,
      ).toJson(),
    );
    await Hive.box<Map>(HiveBoxes.aulas).put(
      aulaId,
      Aula(
        id: aulaId,
        materiaId: materiaId,
        nome: nomeAula,
        paginasTotais: 4,
      ).toJson(),
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    NotificacoesService.habilitadas = true;
  });

  testWidgets(
    'registrar sessão teórica que completa a aula persiste 1 registro, '
    'cria a primeira revisão com aulaId/intervalo 7 e a mostra na aba Revisões',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [hojeProvider.overrideWithValue(DateTime(2026, 10, 7))],
          child: const AppEstudos(consultarConcursos: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(Hive.box<Map>(HiveBoxes.revisoes).isEmpty, isTrue);
      await tester.tap(find.text('Registrar primeira sessão'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Matéria *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(nomeMateria).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Aula (opcional)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('$nomeAula · 0/4 pág').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Minutos *'),
        '25',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Páginas lidas nesta sessão'),
        '4',
      );
      await tester.ensureVisible(find.text('Salvar registro'));
      await tester.tap(find.text('Salvar registro'));
      await tester.pumpAndSettle();

      final geradas = Hive.box<Map>(HiveBoxes.revisoes).values.toList();
      expect(geradas, hasLength(1));
      expect(geradas.single['aulaId'], aulaId);
      expect(geradas.single['feita'], isNot(true));
      expect(geradas.single['intervaloDias'], 7);
      expect(Hive.box<Map>(HiveBoxes.registros).length, 1);

      await tester.tap(find.widgetWithText(NavigationDestination, 'Revisões'));
      await tester.pumpAndSettle();
      expect(find.text('$nomeMateria — $nomeAula (7d)'), findsOneWidget);
    },
  );
}
