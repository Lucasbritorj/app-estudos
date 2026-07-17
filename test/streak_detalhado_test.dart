import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora reg(DateTime data, [int minutos = 30]) => RegistroHora(
      id: '${data.toIso8601String()}-$minutos',
      data: data,
      materiaId: 'm1',
      minutos: minutos,
    );

void main() {
  // Quarta-feira; a semana de estudo começa na segunda (13/07).
  final hoje = DateTime(2026, 7, 15);

  group('streakDetalhado', () {
    test('vazio: tudo zero, sem risco', () {
      final s = StatsService.streakDetalhado([], hoje);
      expect(s.dias, 0);
      expect(s.congelados, 0);
      expect(s.recuperados, 0);
      expect(s.emRisco, false);
    });

    test('run contínuo sem buraco = streakAtual, sem congelamento', () {
      final registros = [
        for (var i = 0; i < 4; i++) reg(DateTime(2026, 7, 15 - i)),
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      expect(s.dias, 4);
      expect(s.congelados, 0);
      expect(s.recuperados, 0);
      expect(s.emRisco, false);
    });

    test('semana anterior com 5+ dias ganha 1 congelamento: buraco não quebra',
        () {
      final registros = [
        reg(hoje), // qua 15
        reg(DateTime(2026, 7, 13)), // seg 13 (ter 14 = buraco congelado)
        for (var d = 6; d <= 12; d++) reg(DateTime(2026, 7, d)), // semana cheia
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      expect(s.dias, 9); // 15, 13, e 6..12 — o dia congelado não soma
      expect(s.congelados, 1);
      expect(s.recuperados, 0);
    });

    test('máximo 1 congelamento por semana: segundo buraco quebra', () {
      final registros = [
        reg(hoje), // qua 15; seg 13 e ter 14 = dois buracos
        for (var d = 6; d <= 12; d++) reg(DateTime(2026, 7, d)),
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      expect(s.dias, 1);
      expect(s.congelados, 1);
      // Quebra de 1 dia (seg 13) com run anterior de 7 → metade recuperada.
      expect(s.recuperados, 3);
    });

    test('sem meta na semana anterior não congela; recuperação 24h vale '
        'metade do run perdido', () {
      final registros = [
        reg(hoje), // voltou hoje; ter 14 = buraco sem proteção
        for (var d = 10; d <= 13; d++) reg(DateTime(2026, 7, d)), // run de 4
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      expect(s.dias, 1);
      expect(s.congelados, 0);
      expect(s.recuperados, 2); // 4 ~/ 2
    });

    test('buraco de 2+ dias não recupera nada', () {
      final registros = [
        reg(hoje),
        for (var d = 9; d <= 12; d++) reg(DateTime(2026, 7, d)),
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      expect(s.dias, 1);
      expect(s.recuperados, 0);
    });

    test('hoje ainda sem registro: streak vivo, mas em risco', () {
      final registros = [
        reg(DateTime(2026, 7, 14)),
        reg(DateTime(2026, 7, 13)),
      ];
      final s = StatsService.streakDetalhado(registros, hoje);
      expect(s.dias, 2);
      expect(s.emRisco, true);
    });
  });
}
