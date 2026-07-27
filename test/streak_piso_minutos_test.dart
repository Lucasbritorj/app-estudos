import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora reg(DateTime data, int minutos) => RegistroHora(
      id: '${data.toIso8601String()}-$minutos',
      data: data,
      materiaId: 'm1',
      minutos: minutos,
    );

// M-08: streakDetalhado/streakPico contavam qualquer dia com minutos > 0.
// Uma sessão-token de 1 min sustentava o streak indefinidamente — gaming
// trivial. StatsService.pisoMinutosStreak (15, mesmo valor de
// DiagnosticoService.pisoMinutosDia) exige minutos reais no dia.
void main() {
  final hoje = DateTime(2026, 7, 15);

  group('piso de minutos no streak (M-08)', () {
    test('dia com sessão abaixo do piso (5 min) não conta para o streak', () {
      final s = StatsService.streakDetalhado([reg(hoje, 5)], hoje);
      expect(s.dias, 0); // sem o piso: contaria 1 (código antigo)
    });

    test('exatamente no piso (15 min) conta; 1 min abaixo (14) não conta', () {
      final noPiso = StatsService.streakDetalhado([reg(hoje, 15)], hoje);
      expect(noPiso.dias, 1);

      final abaixo = StatsService.streakDetalhado([reg(hoje, 14)], hoje);
      expect(abaixo.dias, 0);
    });

    test('várias sessões-token no mesmo dia somadas batem o piso', () {
      final registros = [
        reg(DateTime(2026, 7, 15, 8), 5),
        reg(DateTime(2026, 7, 15, 12), 5),
        reg(DateTime(2026, 7, 15, 20), 5),
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      expect(s.dias, 1); // soma do dia = 15 = piso
    });

    test('run de dias-token (10 min) não sustenta streak nem recorde', () {
      final registros = [
        for (var d = 11; d <= 15; d++) reg(DateTime(2026, 7, d), 10),
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      expect(s.dias, 0); // código antigo: 5

      expect(StatsService.streakPico(registros), 0); // código antigo: 5
    });

    test('dia-token intercalado quebra o run de dias reais', () {
      // 13 e 14 reais (30 min); 15 (hoje) é só um clique de 2 min.
      final registros = [
        reg(hoje, 2),
        reg(DateTime(2026, 7, 14), 30),
        reg(DateTime(2026, 7, 13), 30),
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      // Hoje (2 min) não conta como estudado: a contagem parte de ontem (14
      // e 13) — código antigo contaria hoje também e daria dias=3.
      expect(s.dias, 2);
      // Hoje não tem estudo REAL, então o streak (vivo, construído com
      // 13/14) fica em risco — código antigo daria emRisco=false (contava
      // o clique de hoje como "estudou hoje").
      expect(s.emRisco, true);
    });

    test('streakPico: recorde real (5 dias de 30 min) ignora ruído de 1 min', () {
      final registros = [
        for (var d = 1; d <= 5; d++) reg(DateTime(2026, 7, d), 30),
        reg(DateTime(2026, 7, 20), 1), // ruído isolado, não forma run
      ];
      expect(StatsService.streakPico(registros), 5);
    });
  });
}
