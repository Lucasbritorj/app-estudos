import 'package:app_estudos/features/cronometro/cronometro_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CronometroState.restaurar', () {
    test('sem registro persistido: parado do zero', () {
      final e = CronometroState.restaurar(null);
      expect(e.status, CronometroStatus.parado);
      expect(e.decorrido, Duration.zero);
    });

    test('elapsed zero é tratado como parado (nada a retomar)', () {
      final e =
          CronometroState.restaurar({'elapsedMs': 0, 'rodando': true});
      expect(e.status, CronometroStatus.parado);
    });

    test('sessão que estava rodando volta PAUSADA no último tempo salvo', () {
      // Não perde o estudo nem conta o tempo de app fechado — o usuário
      // decide retomar.
      final e = CronometroState.restaurar(
          {'elapsedMs': 1500000, 'rodando': true});
      expect(e.status, CronometroStatus.pausado);
      expect(e.decorrido, const Duration(minutes: 25));
    });

    test('sessão pausada é restaurada como pausada', () {
      final e = CronometroState.restaurar(
          {'elapsedMs': 600000, 'rodando': false});
      expect(e.status, CronometroStatus.pausado);
      expect(e.decorrido, const Duration(minutes: 10));
    });
  });
}
