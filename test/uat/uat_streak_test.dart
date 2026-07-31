// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import '_massa_fake.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:app_estudos/domain/gamificacao_service.dart';

RegistroHora dia(int offset, {int minutos = 60, String id = ''}) => RegistroHora(
      id: id.isEmpty ? 'r$offset' : id,
      data: DateTime(hoje.year, hoje.month, hoje.day + offset, 20, 0),
      materiaId: 'mat-x',
      minutos: minutos,
    );

void main() {
  test('UAT-D1 piso de 15 min por DIA (soma, nao por sessao)', () {
    final curto = [dia(0, minutos: 14)];
    final somado = [dia(0, minutos: 8, id: 'a'), dia(0, minutos: 7, id: 'b')];
    print('[D1] 14min=${StatsService.streakDetalhado(curto, hoje).dias} '
        'pico14=${StatsService.streakPico(curto)} '
        '8+7min=${StatsService.streakDetalhado(somado, hoje).dias}');
    expect(StatsService.streakPico(curto), 0, reason: 'gaming de 1 min nao vale');
    expect(StatsService.streakDetalhado(somado, hoje).dias, 1, reason: 'piso e por dia somado');
  });

  test('UAT-D2 streakAtual: hoje sem registro nao zera (conta de ontem)', () {
    final ateOntem = [for (var i = 1; i <= 5; i++) dia(-i)];
    final s = StatsService.streakDetalhado(ateOntem, hoje);
    print('[D2] dias=${s.dias} emRisco=${s.emRisco} streakAtual=${StatsService.streakAtual(ateOntem, hoje)}');
    expect(s.dias, 5);
    expect(s.emRisco, isTrue, reason: 'chama treme');
  });

  test('UAT-D3 congelamento: 1 por semana-calendario e exige 5 dias na semana anterior', () {
    // 3 semanas cheias (seg-sex) + furo unico na semana corrente.
    final rs = <RegistroHora>[];
    for (var i = 1; i <= 28; i++) {
      final d = DateTime(hoje.year, hoje.month, hoje.day - i);
      if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) continue;
      rs.add(RegistroHora(id: 'w$i', data: d, materiaId: 'mat-x', minutos: 60));
    }
    rs.add(dia(0));
    final s = StatsService.streakDetalhado(rs, hoje);
    final congelados = StatsService.diasCongeladosDoStreak(rs, hoje);
    print('[D3] dias=${s.dias} congelados=${s.congelados} recuperados=${s.recuperados}');
    print('[D3] datas congeladas=${congelados.map((d) => "${d.day}/${d.month}").join(",")}');
    expect(s.congelados, lessThanOrEqualTo(4), reason: 'no maximo 1 por semana');
    // Sem semana anterior forte, nao congela.
    final fraco = [dia(0), dia(-2)];
    print('[D4-pre] sem semana anterior forte: dias=${StatsService.streakDetalhado(fraco, hoje).dias}');
    expect(StatsService.streakDetalhado(fraco, hoje).dias, 1);
  });

  test('UAT-D4 recuperacao 24h devolve metade do run anterior', () {
    // Gap em -1 NAO congelavel (semana anterior ao gap tem 3 dias < 5) e run
    // anterior de 4 dias -> metade (2) volta como bonus.
    final rs = [dia(0), for (var i = 2; i <= 5; i++) dia(-i)];
    final s = StatsService.streakDetalhado(rs, hoje);
    print('[D4] dias=${s.dias} congelados=${s.congelados} recuperados=${s.recuperados} (run anterior=4)');
    expect(s.dias, 1, reason: 'gap nao congelavel quebra o contador');
    expect(s.recuperados, 2, reason: 'metade do run anterior (4~/2)');
  });

  test('UAT-D5 BUG-CANDIDATO: streak exibido (com congelamento) > pico (sem congelamento)', () {
    // Usuario modelo: estuda seg-sab, descansa domingo, 8 semanas seguidas.
    final rs = <RegistroHora>[];
    for (var i = 0; i < 56; i++) {
      final d = DateTime(hoje.year, hoje.month, hoje.day - i);
      if (d.weekday == DateTime.sunday) continue;
      rs.add(RegistroHora(id: 'x$i', data: d, materiaId: 'mat-x', minutos: 60));
    }
    final s = StatsService.streakDetalhado(rs, hoje);
    final pico = StatsService.streakPico(rs);
    final badges = GamificacaoService.badges(rs, const [], hoje);
    final xp = GamificacaoService.xpDetalhado(rs, const [], hoje);
    final b7 = badges.firstWhere((b) => b.id == 'streak-7');
    final b30 = badges.firstWhere((b) => b.id == 'streak-30');
    print('[D5] streak exibido=${s.dias} dias | congelados=${s.congelados} | pico=$pico');
    print('[D5] badge streak-7 conquistada=${b7.conquistada} | streak-30=${b30.conquistada}');
    print('[D5] bonusStreak XP=${xp.bonusStreak} (pico $pico x ${GamificacaoService.xpPorDiaDeStreak})');
    final picoCong = StatsService.streakPicoComCongelamento(rs, hoje);
    print('[D5] picoComCongelamento=$picoCong (regua do contador exibido)');
    print('[D5] pos-correcao: badge streak-7=${b7.conquistada} streak-30=${b30.conquistada} '
        'bonusStreak=${xp.bonusStreak}');
    expect(s.dias, greaterThan(pico),
        reason: 'streakPico cru ignora congelamento (comportamento legado mantido)');
    expect(picoCong, greaterThanOrEqualTo(s.dias),
        reason: 'REGRESSAO: pico nunca pode ficar abaixo do streak corrente');
    expect(b7.conquistada, isTrue, reason: 'REGRESSAO: 39 dias de chama acende a badge de 7');
    expect(b30.conquistada, isTrue);
    expect(xp.bonusStreak, picoCong * GamificacaoService.xpPorDiaDeStreak);
  });

  test('UAT-D6 BORDA temporal: inDays trunca para zero (antecipacao perde 1 dia)', () {
    final agora = DateTime(2026, 7, 29, 20, 0);
    final agendadaFutura = DateTime(2026, 8, 1);
    final agendadaPassada = DateTime(2026, 7, 24);
    print('[D6] antecipacao calendario=-3d | inDays=${agora.difference(agendadaFutura).inDays}');
    print('[D6] atraso calendario=+5d   | inDays=${agora.difference(agendadaPassada).inDays}');
    expect(agora.difference(agendadaFutura).inDays, -2,
        reason: 'diasDeAtraso do use case perde 1 dia de antecipacao');
    expect(agora.difference(agendadaPassada).inDays, 5);
  });

  test('UAT-D7 BORDA temporal: virada de mes/ano e fim de semana', () {
    final rs = [
      RegistroHora(id: 'a', data: DateTime(2025, 12, 30, 23, 30), materiaId: 'm', minutos: 60),
      RegistroHora(id: 'b', data: DateTime(2025, 12, 31, 1, 0), materiaId: 'm', minutos: 60),
      RegistroHora(id: 'c', data: DateTime(2026, 1, 1, 0, 30), materiaId: 'm', minutos: 60),
      RegistroHora(id: 'd', data: DateTime(2026, 1, 2, 23, 59), materiaId: 'm', minutos: 60),
    ];
    final s = StatsService.streakDetalhado(rs, DateTime(2026, 1, 2));
    print('[D7] streak atravessando ano=${s.dias} pico=${StatsService.streakPico(rs)}');
    print('[D7] minutosPorAno=${StatsService.minutosPorAno(rs)}');
    expect(s.dias, 4);
    expect(StatsService.minutosPorAno(rs), {2025: 120, 2026: 120});
    print('[D7] semana de 01/01/2026 comeca em ${StatsService.inicioDaSemana(DateTime(2026, 1, 1))}');
    expect(StatsService.inicioDaSemana(DateTime(2026, 1, 1)), DateTime(2025, 12, 29));
  });

  test('UAT-D8 comparativo mensal clampa fim de mes curto (31/03 vs fevereiro)', () {
    final rs = [
      RegistroHora(id: 'f', data: DateTime(2026, 2, 27), materiaId: 'm', minutos: 100),
      RegistroHora(id: 'm1', data: DateTime(2026, 3, 5), materiaId: 'm', minutos: 60),
    ];
    final c = StatsService.comparativoMensal(rs, DateTime(2026, 3, 31));
    print('[D8] 31/03 vs fev: atual=${c.atual} anterior=${c.anterior} var=${c.variacao}');
    expect(c.anterior, 100, reason: 'fevereiro inteiro, sem estourar para marco');
    expect(c.atual, 60);
  });

  test('UAT-D9 heatmap e minutosPorDia consistentes com a massa', () {
    final massa = construirMassa();
    final porDia = StatsService.minutosPorDia(massa.registros);
    final soma = porDia.values.fold<int>(0, (a, b) => a + b);
    final total = massa.registros.fold<int>(0, (s, r) => s + r.minutos);
    print('[D9] dias distintos=${porDia.length} soma=$soma total=$total');
    expect(soma, total);
    final s = StatsService.streakDetalhado(massa.registros, hoje);
    final pico = StatsService.streakPico(massa.registros);
    print('[D9] massa: streak=${s.dias} congelados=${s.congelados} pico=$pico');
  });
}
