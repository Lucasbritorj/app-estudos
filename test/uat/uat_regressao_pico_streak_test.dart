// ignore_for_file: avoid_print
// Replica os casos da suite EXISTENTE do repo que dependem do pico de streak,
// para provar que a correcao nao quebrou nenhuma expectativa ja aceita.
// Origem: test/gamificacao_service_test.dart e test/streak_piso_minutos_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/gamificacao_service.dart';
import 'package:app_estudos/domain/stats_service.dart';

RegistroHora reg(DateTime data, int minutos) => RegistroHora(
      id: '${data.toIso8601String()}-$minutos',
      data: data,
      materiaId: 'm1',
      minutos: minutos,
    );

void main() {
  final hoje = DateTime(2026, 7, 9);

  test('REG-1 base + 50 por revisao feita + 10 por dia de streak', () {
    final registros = [reg(hoje, 100), reg(DateTime(2026, 7, 8, 8), 50)];
    final revisoes = [
      Revisao(id: 'r1', materiaId: 'm1', titulo: 'x',
          dataAgendada: DateTime(2026, 7, 1), intervaloDias: 7, feita: true),
      Revisao(id: 'r2', materiaId: 'm1', titulo: 'y',
          dataAgendada: DateTime(2026, 7, 20), intervaloDias: 15),
    ];
    final xp = GamificacaoService.xpDetalhado(registros, revisoes, hoje);
    print('[REG-1] base=${xp.base} rev=${xp.bonusRevisoes} streak=${xp.bonusStreak} total=${xp.total}');
    expect(xp.base, 150);
    expect(xp.bonusRevisoes, 50);
    expect(xp.bonusStreak, 20);
    expect(xp.total, 220);
  });

  test('REG-2 sem dados, tudo zero', () {
    final xp = GamificacaoService.xpDetalhado(const [], const [], hoje);
    print('[REG-2] total=${xp.total}');
    expect(xp.total, 0);
  });

  test('REG-3 bonus de streak usa o PICO historico (monotono)', () {
    final registros = [
      reg(hoje, 60),
      for (var d = 4; d <= 7; d++) reg(DateTime(2026, 7, d), 30),
    ];
    final xp = GamificacaoService.xpDetalhado(registros, const [], hoje);
    print('[REG-3] bonusStreak=${xp.bonusStreak} '
        'picoCru=${StatsService.streakPico(registros)} '
        'picoCong=${StatsService.streakPicoComCongelamento(registros, hoje)}');
    expect(xp.bonusStreak, 40);
  });

  test('REG-4 XP total e monotono: perder o streak nao derruba o XP', () {
    final base = [for (var d = 1; d <= 5; d++) reg(DateTime(2026, 7, d), 30)];
    final comQuebra = [...base, reg(DateTime(2026, 8, 1), 30)];
    final xpBase = GamificacaoService.xpDetalhado(base, const [], hoje);
    final xpDepois =
        GamificacaoService.xpDetalhado(comQuebra, const [], DateTime(2026, 8, 1));
    print('[REG-4] antes=${xpBase.total}(streak=${xpBase.bonusStreak}) '
        'depois=${xpDepois.total}(streak=${xpDepois.bonusStreak})');
    expect(xpDepois.bonusStreak, xpBase.bonusStreak);
    expect(xpDepois.total, greaterThanOrEqualTo(xpBase.total));
  });

  Map<String, bool> conquistadas(List<RegistroHora> r, List<Revisao> v) => {
        for (final b in GamificacaoService.badges(r, v, hoje)) b.id: b.conquistada,
      };

  test('REG-5 badges: nada com lista vazia', () {
    final b = conquistadas(const [], const []);
    print('[REG-5] ${b.entries.where((e) => e.value).map((e) => e.key).toList()}');
    expect(b.values.any((v) => v), false);
  });

  test('REG-6 badges: 50h e primeira sessao', () {
    final registros = [for (var i = 0; i < 10; i++) reg(DateTime(2026, 7, 9 - i, 8), 5 * 60)];
    final b = conquistadas(registros, const []);
    print('[REG-6] horas-50=${b["horas-50"]} horas-100=${b["horas-100"]}');
    expect(b['primeira-sessao'], true);
    expect(b['horas-50'], true);
    expect(b['horas-100'], false);
  });

  test('REG-7 badges: streak de 7 dias', () {
    final registros = [for (var i = 0; i < 7; i++) reg(DateTime(2026, 7, 9 - i, 8), 30)];
    final b = conquistadas(registros, const []);
    print('[REG-7] streak-7=${b["streak-7"]} streak-30=${b["streak-30"]} '
        'picoCong=${StatsService.streakPicoComCongelamento(registros, hoje)}');
    expect(b['streak-7'], true);
    expect(b['streak-30'], false);
  });

  test('REG-8 badge de streak NAO e revogada ao quebrar (pico em janeiro)', () {
    final registros = [for (var d = 1; d <= 7; d++) reg(DateTime(2026, 1, d, 8), 30)];
    print('[REG-8] streak-7=${conquistadas(registros, const [])["streak-7"]} '
        'picoCong=${StatsService.streakPicoComCongelamento(registros, hoje)}');
    expect(conquistadas(registros, const [])['streak-7'], true);
  });

  test('REG-9 piso de minutos no streak (test/streak_piso_minutos_test.dart)', () {
    final tokens = [for (var i = 0; i < 10; i++) reg(DateTime(2026, 7, 9 - i, 8), 1)];
    print('[REG-9] pico cru=${StatsService.streakPico(tokens)} '
        'picoCong=${StatsService.streakPicoComCongelamento(tokens, hoje)} '
        'bonus=${GamificacaoService.xpDetalhado(tokens, const [], hoje).bonusStreak}');
    expect(StatsService.streakPico(tokens), 0);
    expect(StatsService.streakPicoComCongelamento(tokens, hoje), 0);
    expect(GamificacaoService.xpDetalhado(tokens, const [], hoje).bonusStreak, 0);
  });

  test('REG-10 pico com congelamento nunca abaixo do pico cru', () {
    final casos = <String, List<RegistroHora>>{
      'run unico 5d': [for (var d = 1; d <= 5; d++) reg(DateTime(2026, 7, d), 30)],
      'dois runs': [
        for (var d = 1; d <= 9; d++) reg(DateTime(2026, 6, d), 30),
        for (var d = 1; d <= 3; d++) reg(DateTime(2026, 7, d), 30),
      ],
      'com registro futuro': [
        for (var d = 1; d <= 4; d++) reg(DateTime(2026, 7, d), 30),
        reg(DateTime(2026, 12, 25), 30),
      ],
    };
    casos.forEach((nome, rs) {
      final cru = StatsService.streakPico(rs);
      final cong = StatsService.streakPicoComCongelamento(rs, hoje);
      print('[REG-10] $nome: cru=$cru cong=$cong');
      expect(cong, greaterThanOrEqualTo(cru), reason: nome);
    });
  });
}
