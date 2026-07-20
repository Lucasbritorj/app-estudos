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
  // Quinta-feira fixa para testes determinísticos.
  final hoje = DateTime(2026, 7, 9, 21, 30);

  group('minutosNoDia', () {
    test('soma registros do mesmo dia em horários diferentes', () {
      final registros = [
        reg(DateTime(2026, 7, 9, 8), 30),
        reg(DateTime(2026, 7, 9, 22), 45),
        reg(DateTime(2026, 7, 8, 10), 60),
      ];
      expect(StatsService.minutosNoDia(registros, hoje), 75);
    });

    test('dia sem registros = 0', () {
      expect(StatsService.minutosNoDia([], hoje), 0);
    });
  });

  group('minutosNaSemana', () {
    test('semana começa na segunda; domingo anterior fica fora', () {
      final registros = [
        reg(DateTime(2026, 7, 6, 9), 60), // segunda desta semana
        reg(DateTime(2026, 7, 5, 9), 120), // domingo — semana passada
        reg(DateTime(2026, 7, 9, 9), 30), // hoje (quinta)
      ];
      expect(StatsService.minutosNaSemana(registros, hoje), 90);
    });
  });

  group('streakAtual', () {
    test('hoje + 2 dias anteriores = 3', () {
      final registros = [
        reg(DateTime(2026, 7, 9, 8), 30),
        reg(DateTime(2026, 7, 8, 8), 30),
        reg(DateTime(2026, 7, 7, 8), 30),
      ];
      expect(StatsService.streakAtual(registros, hoje), 3);
    });

    test('hoje ainda sem registro não zera: conta a partir de ontem', () {
      final registros = [
        reg(DateTime(2026, 7, 8, 8), 30),
        reg(DateTime(2026, 7, 7, 8), 30),
      ];
      expect(StatsService.streakAtual(registros, hoje), 2);
    });

    test('buraco quebra o streak', () {
      final registros = [
        reg(DateTime(2026, 7, 9, 8), 30),
        reg(DateTime(2026, 7, 7, 8), 30), // 8/7 faltou
      ];
      expect(StatsService.streakAtual(registros, hoje), 1);
    });

    test('sem registros = 0', () {
      expect(StatsService.streakAtual([], hoje), 0);
    });
  });

  group('resumoDiario', () {
    test('média/máx/mín sobre dias COM registro', () {
      final registros = [
        reg(DateTime(2026, 7, 9, 8), 60),
        reg(DateTime(2026, 7, 9, 20), 60), // dia 9: 120
        reg(DateTime(2026, 7, 7, 8), 30), // dia 7: 30
      ];
      final resumo = StatsService.resumoDiario(registros);
      expect(resumo.media, 75);
      expect(resumo.maximo, 120);
      expect(resumo.minimo, 30);
    });

    test('vazio retorna zeros', () {
      final resumo = StatsService.resumoDiario([]);
      expect(resumo.media, 0);
      expect(resumo.maximo, 0);
      expect(resumo.minimo, 0);
    });
  });

  group('serieDiaria', () {
    test('14 pontos, cronológica, termina hoje, dias vazios = 0', () {
      final registros = [reg(DateTime(2026, 7, 9, 8), 45)];
      final serie = StatsService.serieDiaria(registros, hoje, 14);
      expect(serie.length, 14);
      expect(serie.last.dia, DateTime(2026, 7, 9));
      expect(serie.first.dia, DateTime(2026, 6, 26));
      expect(serie.last.minutos, 45);
      expect(serie.first.minutos, 0);
    });
  });

  group('minutosPorMateria', () {
    test('agrupa e respeita intervalo', () {
      final registros = [
        reg(DateTime(2026, 7, 9, 8), 30, materia: 'afo'),
        reg(DateTime(2026, 7, 9, 9), 30, materia: 'afo'),
        reg(DateTime(2026, 7, 1, 9), 60, materia: 'sql'),
      ];
      final tudo = StatsService.minutosPorMateria(registros);
      expect(tudo['afo'], 60);
      expect(tudo['sql'], 60);

      final soHoje = StatsService.minutosPorMateria(registros,
          de: DateTime(2026, 7, 9), ate: DateTime(2026, 7, 9));
      expect(soHoje['afo'], 60);
      expect(soHoje.containsKey('sql'), false);
    });
  });

  group('paginasPorHoraGeral', () {
    test('média ponderada: 30 pág em 60min = 30 pág/h', () {
      final registros = [
        RegistroHora(
          id: 'a',
          data: hoje,
          materiaId: 'm1',
          minutos: 60,
          paginaInicial: 1,
          paginaFinal: 30,
        ),
      ];
      expect(StatsService.paginasPorHoraGeral(registros), 30.0);
    });

    test('sem páginas informadas retorna null (nunca inventa valor)', () {
      expect(StatsService.paginasPorHoraGeral([reg(hoje, 60)]), isNull);
    });
  });

  group('minutosNoMes / minutosNoAno', () {
    test('inclui primeiro e último dia do mês; mês vizinho fica fora', () {
      final registros = [
        reg(DateTime(2026, 7, 1, 8), 30),
        reg(DateTime(2026, 7, 31, 23), 45),
        reg(DateTime(2026, 6, 30, 12), 60),
        reg(DateTime(2026, 8, 1, 0), 90),
      ];
      expect(StatsService.minutosNoMes(registros, hoje), 75);
    });

    test('minutosNoAno separa anos', () {
      final registros = [
        reg(DateTime(2025, 12, 31, 23), 60),
        reg(DateTime(2026, 1, 1, 0), 30),
      ];
      expect(StatsService.minutosNoAno(registros, 2025), 60);
      expect(StatsService.minutosNoAno(registros, 2026), 30);
    });
  });

  group('minutosPorAno', () {
    test('agrega por ano em ordem crescente, só anos com registro', () {
      final registros = [
        reg(DateTime(2026, 7, 9), 30),
        reg(DateTime(2024, 3, 1), 120),
        reg(DateTime(2026, 1, 2), 60),
      ];
      final porAno = StatsService.minutosPorAno(registros);
      expect(porAno.keys.toList(), [2024, 2026]);
      expect(porAno[2024], 120);
      expect(porAno[2026], 90);
    });

    test('sem registros retorna mapa vazio', () {
      expect(StatsService.minutosPorAno([]), isEmpty);
    });
  });

  group('projecaoAno', () {
    test('ritmo constante projeta o mesmo ritmo até 31/12', () {
      // 28 dias seguidos de 60min terminando hoje: ritmo = 60 min/dia.
      final registros = [
        for (var i = 0; i < 28; i++)
          reg(DateTime(2026, 7, 9 - i, 8), 60),
      ];
      final totalAno = registros.fold(0, (s, r) => s + r.minutos);
      final diasRestantes =
          DateTime(2026, 12, 31).difference(DateTime(2026, 7, 9)).inDays;
      expect(StatsService.projecaoAno(registros, hoje),
          totalAno + 60 * diasRestantes);
    });

    test('sem estudo recente: projeção = total já feito no ano', () {
      final registros = [reg(DateTime(2026, 1, 10), 300)];
      expect(StatsService.projecaoAno(registros, hoje), 300);
    });
  });

  group('streakPico', () {
    test('sem registros: 0', () {
      expect(StatsService.streakPico([]), 0);
    });

    test('recorde é o maior run consecutivo, não o mais recente', () {
      // Run de 5 dias (jan) e run de 2 dias (jul): pico = 5.
      final registros = [
        for (var d = 1; d <= 5; d++) reg(DateTime(2026, 1, d), 30),
        for (var d = 8; d <= 9; d++) reg(DateTime(2026, 7, d), 30),
      ];
      expect(StatsService.streakPico(registros), 5);
    });

    test('múltiplos registros no mesmo dia contam como 1 dia', () {
      final registros = [
        reg(DateTime(2026, 7, 1, 8), 30),
        reg(DateTime(2026, 7, 1, 20), 30),
        reg(DateTime(2026, 7, 2, 9), 30),
      ];
      expect(StatsService.streakPico(registros), 2);
    });
  });
}
