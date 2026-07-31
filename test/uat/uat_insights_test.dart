// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import '_massa_fake.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/insights_service.dart';
import 'package:app_estudos/domain/stats_service.dart';

RegistroHora r(DateTime d, int min, {int? q, int? a}) => RegistroHora(
      id: '${d.toIso8601String()}-$min-${q ?? 0}',
      data: d, materiaId: 'm1', minutos: min, questoes: q, acertos: a);

Materia m(String id, String nome) =>
    Materia(id: id, nome: nome, corSlot: 0, criadaEm: dias(-90));

void main() {
  test('UAT-I1 REGRESSAO: insight de streak usa a regua da chama e a constante', () {
    // Streak vivo ate ontem, hoje sem estudo -> em risco.
    final registros = [for (var i = 1; i <= 4; i++) r(dias(-i), 60)];
    final acoes = InsightsService.melhorarHoje(
      registros: registros, materias: [m('m1', 'AFO')], revisoes: const [], hoje: hoje);
    final streak = acoes.firstWhere((a) => a.tipo == TipoInsight.streak);
    final detalhado = StatsService.streakDetalhado(registros, hoje);
    print('[I1] "${streak.mensagem}"');
    print('[I1] chama=${detalhado.dias} dias emRisco=${detalhado.emRisco} '
        'piso=${StatsService.pisoMinutosStreak}');
    expect(streak.mensagem, contains('Streak de ${detalhado.dias} dias'),
        reason: 'numero identico ao exibido no dashboard');
    expect(streak.mensagem, contains('${StatsService.pisoMinutosStreak} minutos'),
        reason: 'tempo citado sai da constante, nao de literal 25');
    expect(streak.mensagem, isNot(contains('25 minutos')));
  });

  test('UAT-I2 REGRESSAO: sessao-token abaixo do piso nao cancela o alerta', () {
    final registros = [
      for (var i = 1; i <= 4; i++) r(dias(-i), 60),
      r(hoje, 5), // 5 min hoje: nao sustenta o streak (piso 15)
    ];
    final acoes = InsightsService.melhorarHoje(
      registros: registros, materias: [m('m1', 'AFO')], revisoes: const [], hoje: hoje);
    final temAlerta = acoes.any((a) => a.tipo == TipoInsight.streak);
    print('[I2] 5 min hoje -> alerta de streak=$temAlerta '
        '(minutosNoDia=${StatsService.minutosNoDia(registros, hoje)}, '
        'emRisco=${StatsService.streakDetalhado(registros, hoje).emRisco})');
    expect(temAlerta, isTrue,
        reason: 'antes `minutosNoDia > 0` calava o alerta com 1 min');
  });

  test('UAT-I3 estudo real hoje silencia o alerta', () {
    final registros = [for (var i = 0; i <= 4; i++) r(dias(-i), 60)];
    final acoes = InsightsService.melhorarHoje(
      registros: registros, materias: [m('m1', 'AFO')], revisoes: const [], hoje: hoje);
    print('[I3] tipos=${acoes.map((a) => a.tipo.name).toList()}');
    expect(acoes.any((a) => a.tipo == TipoInsight.streak), isFalse);
    expect(acoes, isNotEmpty, reason: 'nunca devolve lista vazia');
  });

  test('UAT-I3b REGRESSAO: casos da suite existente (test/insights_service_test.dart)', () {
    final hj = DateTime(2026, 7, 10); // sexta fixa da suite existente
    RegistroHora rr(DateTime d, int min, String mat, {int? q, int? a}) =>
        RegistroHora(id: '$d-$min-$mat-$q', data: d, materiaId: mat,
            minutos: min, questoes: q, acertos: a);
    Materia mm(String id, String nome) =>
        Materia(id: id, nome: nome, corSlot: 0, criadaEm: DateTime(2026, 1, 1));

    // "streak em risco quando hoje ainda sem estudo"
    final emRisco = InsightsService.melhorarHoje(
      registros: [rr(DateTime(2026, 7, 8), 60, 'm1'), rr(DateTime(2026, 7, 9), 60, 'm1')],
      materias: [mm('m1', 'AFO')], revisoes: const [], hoje: hj);
    print('[I3b] em risco -> ${emRisco.map((a) => a.tipo.name).toList()}');
    expect(emRisco.any((a) => a.tipo == TipoInsight.streak), isTrue);

    // "sem pendencias devolve insight positivo (nunca vazio)"
    final positivo = InsightsService.melhorarHoje(
      registros: [rr(hj, 30, 'm1')], materias: [mm('m1', 'AFO')],
      revisoes: const [], hoje: hj);
    print('[I3b] estudou hoje -> ${positivo.map((a) => a.tipo.name).toList()}');
    expect(positivo, isNotEmpty);
    expect(positivo.any((a) => a.tipo == TipoInsight.streak), isFalse);

    // "baixo desempenho" convivendo com estudo de hoje
    final desempenho = InsightsService.melhorarHoje(
      registros: [
        rr(DateTime(2026, 7, 6), 60, 'm1', q: 20, a: 10),
        rr(hj, 30, 'm1'),
      ],
      materias: [mm('m1', 'AFO')], revisoes: const [], hoje: hj);
    print('[I3b] desempenho ruim -> ${desempenho.map((a) => a.tipo.name).toList()}');
    expect(desempenho.any((a) => a.tipo == TipoInsight.desempenho), isTrue);
  });

  test('UAT-I4 sem streak nenhum, nao inventa alerta', () {
    final acoes = InsightsService.melhorarHoje(
      registros: const [], materias: [m('m1', 'AFO')], revisoes: const [], hoje: hoje);
    print('[I4] tipos=${acoes.map((a) => a.tipo.name).toList()}');
    expect(acoes.any((a) => a.tipo == TipoInsight.streak), isFalse);
  });
}
