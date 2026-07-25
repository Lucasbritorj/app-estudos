import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora reg(DateTime data, int minutos, {String materia = 'm1'}) =>
    RegistroHora(
      id: '${data.toIso8601String()}-$minutos-$materia',
      data: data,
      materiaId: materia,
      minutos: minutos,
    );

void main() {
  group('comparativoMensal', () {
    test(
      'parcial-vs-parcial: mesmo recorte de dias evita queda falsa',
      () {
        final hoje = DateTime(2026, 7, 24);
        final registros = [
          reg(DateTime(2026, 7, 5), 60), // atual: dentro de 1-24/jul
          reg(DateTime(2026, 7, 24), 40), // atual: borda incluída
          reg(DateTime(2026, 7, 28), 999), // fora (depois de hoje)
          reg(DateTime(2026, 6, 10), 50), // anterior: dentro de 1-24/jun
          reg(DateTime(2026, 6, 24), 30), // anterior: borda incluída
          reg(DateTime(2026, 6, 25), 777), // fora do corte (depois do dia 24)
        ];

        final r = StatsService.comparativoMensal(registros, hoje);

        expect(r.atual, 100);
        expect(r.anterior, 80);
        expect(r.variacao, closeTo(0.25, 1e-9));
      },
    );

    test('mês corrente cheio (último dia) compara mês anterior inteiro', () {
      final hoje = DateTime(2026, 7, 31);
      final registros = [
        reg(DateTime(2026, 7, 1), 10),
        reg(DateTime(2026, 7, 31), 20), // julho inteiro: 30
        reg(DateTime(2026, 6, 1), 5),
        reg(DateTime(2026, 6, 30), 15), // junho (30 dias) inteiro: 20
      ];

      final r = StatsService.comparativoMensal(registros, hoje);

      expect(r.atual, 30);
      expect(r.anterior, 20);
      expect(r.variacao, closeTo(0.5, 1e-9));
    });

    test('virada de ano: janeiro compara com dezembro do ano anterior', () {
      final hoje = DateTime(2026, 1, 15);
      final registros = [
        reg(DateTime(2026, 1, 10), 25), // atual (jan/2026, 1-15)
        reg(DateTime(2025, 12, 10), 45), // anterior (dez/2025, 1-15)
        reg(DateTime(2025, 12, 20), 999), // fora do corte (depois do dia 15)
      ];

      final r = StatsService.comparativoMensal(registros, hoje);

      expect(r.atual, 25);
      expect(r.anterior, 45);
      expect(r.variacao, closeTo((25 - 45) / 45, 1e-9));
    });

    test('clamp: 31/03 vs fevereiro de 28 dias (ano não-bissexto)', () {
      final hoje = DateTime(2026, 3, 31); // 2026 não é bissexto
      final registros = [
        reg(DateTime(2026, 3, 31), 70), // atual: março inteiro
        reg(DateTime(2026, 2, 28), 40), // anterior: clamp no último dia
        reg(DateTime(2026, 2, 27), 10),
      ];

      final r = StatsService.comparativoMensal(registros, hoje);

      // Sem o clamp, DateTime(2026, 2, 31) normalizaria para 03/03/2026,
      // vazando pro mês seguinte e corrompendo a soma.
      expect(r.atual, 70);
      expect(r.anterior, 50);
      expect(r.variacao, closeTo(0.4, 1e-9));
    });

    test('clamp: 31/03 vs fevereiro de 29 dias (ano bissexto)', () {
      final hoje = DateTime(2024, 3, 31); // 2024 é bissexto
      final registros = [
        reg(DateTime(2024, 2, 29), 33), // anterior: dia bissexto incluído
      ];

      final r = StatsService.comparativoMensal(registros, hoje);

      expect(r.atual, 0);
      expect(r.anterior, 33);
      expect(r.variacao, closeTo(-1.0, 1e-9));
    });

    test('base zero no mês anterior => variacao null (nunca infinito)', () {
      final hoje = DateTime(2026, 5, 10);
      final registros = [reg(DateTime(2026, 5, 5), 100)];

      final r = StatsService.comparativoMensal(registros, hoje);

      expect(r.atual, 100);
      expect(r.anterior, 0);
      expect(r.variacao, isNull);
    });

    test('sem registros: tudo zero e variacao null', () {
      final r = StatsService.comparativoMensal([], DateTime(2026, 7, 24));
      expect(r.atual, 0);
      expect(r.anterior, 0);
      expect(r.variacao, isNull);
    });
  });

  group('comparativoAnual', () {
    test('parcial-vs-parcial: mesmo recorte até a mesma data', () {
      final hoje = DateTime(2026, 7, 24);
      final registros = [
        reg(DateTime(2026, 3, 1), 100), // atual (2026, até 24/jul)
        reg(DateTime(2026, 7, 24), 50), // atual: borda incluída
        reg(DateTime(2026, 8, 1), 999), // fora (depois de hoje)
        reg(DateTime(2025, 3, 1), 80), // anterior (2025, até 24/jul)
        reg(DateTime(2025, 7, 24), 20), // anterior: borda incluída
        reg(DateTime(2025, 7, 25), 999), // fora do corte
      ];

      final r = StatsService.comparativoAnual(registros, hoje);

      expect(r.atual, 150);
      expect(r.anterior, 100);
      expect(r.variacao, closeTo(0.5, 1e-9));
    });

    test('ano corrente cheio (31/12) compara ano anterior inteiro', () {
      final hoje = DateTime(2026, 12, 31);
      final registros = [
        reg(DateTime(2026, 1, 1), 10),
        reg(DateTime(2026, 12, 31), 20), // 2026 inteiro: 30
        reg(DateTime(2025, 1, 1), 5),
        reg(DateTime(2025, 12, 31), 15), // 2025 inteiro: 20
      ];

      final r = StatsService.comparativoAnual(registros, hoje);

      expect(r.atual, 30);
      expect(r.anterior, 20);
      expect(r.variacao, closeTo(0.5, 1e-9));
    });

    test('clamp: 29/02 bissexto vs ano anterior não-bissexto', () {
      final hoje = DateTime(2028, 2, 29); // 2028 é bissexto
      final registros = [
        reg(DateTime(2028, 2, 29), 44), // atual: dia bissexto incluído
        reg(DateTime(2027, 2, 28), 22), // anterior: clamp em 28/02/2027
      ];

      final r = StatsService.comparativoAnual(registros, hoje);

      expect(r.atual, 44);
      expect(r.anterior, 22);
      expect(r.variacao, closeTo(1.0, 1e-9));
    });

    test('base zero no ano anterior => variacao null', () {
      final hoje = DateTime(2026, 6, 1);
      final registros = [reg(DateTime(2026, 3, 1), 60)];

      final r = StatsService.comparativoAnual(registros, hoje);

      expect(r.atual, 60);
      expect(r.anterior, 0);
      expect(r.variacao, isNull);
    });
  });
}
