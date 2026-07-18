import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:app_estudos/features/dashboard/widgets/heatmap_constancia.dart';
import 'package:flutter_test/flutter_test.dart';

/// Heatmap de constância (2a do plano de melhorias): base de dados pura
/// (minutos por dia + datas congeladas do streak) e faixas de intensidade.
void main() {
  RegistroHora registro(String id, DateTime data, int minutos) =>
      RegistroHora(id: id, data: data, materiaId: 'm1', minutos: minutos);

  group('faixas de intensidade', () {
    test('níveis fixos por carga do dia', () {
      expect(CardHeatmapConstancia.nivelPara(0), 0);
      expect(CardHeatmapConstancia.nivelPara(1), 1);
      expect(CardHeatmapConstancia.nivelPara(29), 1);
      expect(CardHeatmapConstancia.nivelPara(30), 2);
      expect(CardHeatmapConstancia.nivelPara(59), 2);
      expect(CardHeatmapConstancia.nivelPara(60), 3);
      expect(CardHeatmapConstancia.nivelPara(119), 3);
      expect(CardHeatmapConstancia.nivelPara(120), 4);
      expect(CardHeatmapConstancia.nivelPara(600), 4);
    });

    test('cores monotônicas: um só matiz, opacidade crescente', () {
      for (var nivel = 1; nivel <= 4; nivel++) {
        final anterior = CardHeatmapConstancia.corDoNivel(nivel - 1);
        final atual = CardHeatmapConstancia.corDoNivel(nivel);
        expect(
          atual.a,
          greaterThan(anterior.a),
          reason: 'nível $nivel deve ser mais intenso que ${nivel - 1}',
        );
      }
    });
  });

  group('minutosPorDia', () {
    test('agrupa por dia truncado somando sessões', () {
      final porDia = StatsService.minutosPorDia([
        registro('a', DateTime(2026, 7, 10, 8), 30),
        registro('b', DateTime(2026, 7, 10, 21), 45),
        registro('c', DateTime(2026, 7, 11), 60),
      ]);
      expect(porDia[DateTime(2026, 7, 10)], 75);
      expect(porDia[DateTime(2026, 7, 11)], 60);
      expect(porDia.length, 2);
    });
  });

  group('diasCongeladosDoStreak', () {
    // Semana cheia (seg 6/jul a dom 12/jul de 2026) ganha direito a 1
    // congelamento na semana seguinte.
    List<RegistroHora> semanaForte() => [
      for (var d = 6; d <= 12; d++) registro('s$d', DateTime(2026, 7, d), 60),
    ];

    test('expõe a data exata do dia protegido', () {
      // Estudou seg 13 e qua 15; ter 14 ficou vazia — protegida.
      final registros = [
        ...semanaForte(),
        registro('x', DateTime(2026, 7, 13), 60),
        registro('y', DateTime(2026, 7, 15), 60),
      ];
      final congelados = StatsService.diasCongeladosDoStreak(
        registros,
        DateTime(2026, 7, 15),
      );
      expect(congelados, {DateTime(2026, 7, 14)});
    });

    test('consistente com o contador do streakDetalhado', () {
      final registros = [
        ...semanaForte(),
        registro('x', DateTime(2026, 7, 13), 60),
        registro('y', DateTime(2026, 7, 15), 60),
      ];
      final hoje = DateTime(2026, 7, 15);
      expect(
        StatsService.diasCongeladosDoStreak(registros, hoje).length,
        StatsService.streakDetalhado(registros, hoje).congelados,
      );
    });

    test('sem semana forte anterior, nada é congelado', () {
      final registros = [
        registro('x', DateTime(2026, 7, 13), 60),
        registro('y', DateTime(2026, 7, 15), 60),
      ];
      expect(
        StatsService.diasCongeladosDoStreak(registros, DateTime(2026, 7, 15)),
        isEmpty,
      );
    });
  });
}
