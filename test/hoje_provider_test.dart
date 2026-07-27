import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// M-06: hojeProvider era um Provider comum que só recalculava DateTime.now()
// quando ALGO MAIS o reconstruía (reabertura do app). Um app aberto às 23:59
// e nunca fechado ficava preso no dia anterior indefinidamente — "Hoje",
// streak e quests mentindo. O fix agenda um Timer até a meia-noite seguinte
// (ref.invalidateSelf ao disparar) e cancela em ref.onDispose.
//
// fake_async (transitivo via flutter_test) dá acesso direto à fila de Timers
// pendentes — mais preciso que observar rebuild de widget, que depende de
// DateTime.now() (não é zone-interceptável sem o pacote `clock`, que este
// projeto não usa) e da checagem de igualdade do Riverpod (o valor recomputado
// no mesmo instante real é `==` ao anterior e não notificaria um watcher).
void main() {
  test('hojeProvider agenda um Timer real ao ser lido (sem isso, M-06 volta)', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      container.read(hojeProvider);

      // Código antigo (sem Timer) deixaria isto em 0 — é o próprio bug M-06.
      expect(async.pendingTimers.length, 1);

      container.dispose();
    });
  });

  test('ref.onDispose cancela o Timer — dispor o container não deixa Timer pendente', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      container.read(hojeProvider);
      expect(async.pendingTimers.length, 1);

      container.dispose();

      expect(async.pendingTimers.length, 0);
    });
  });

  test('o Timer dispara e reconstrói o provider (invalidateSelf) sem erro', () {
    fakeAsync((async) {
      final container = ProviderContainer();
      final antes = container.read(hojeProvider);

      // Avança até depois da meia-noite: o Timer dispara sozinho.
      async.elapse(const Duration(hours: 25));

      // Não relança — hojeProvider continua legível (recomputado, ainda que
      // com o mesmo valor de calendário real dentro do teste) e agendou o
      // PRÓXIMO Timer da meia-noite seguinte (autossustentável).
      expect(() => container.read(hojeProvider), returnsNormally);
      expect(container.read(hojeProvider), antes); // mesmo dia real do teste
      expect(async.pendingTimers.length, 1); // já reagendado sozinho

      container.dispose();
    });
  });
}
