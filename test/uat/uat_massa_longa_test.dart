// ignore_for_file: avoid_print
import 'package:app_estudos/domain/gamificacao_service.dart';
import 'package:app_estudos/domain/revisao_service.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '_massa_fake.dart';

/// UAT-L — invariantes de métrica sobre a massa longa (4 meses).
///
/// A massa curta (`construirMassa`, 60 dias) cobre a jornada; ela não cobre o
/// que só aparece com horizonte: MoM encadeado com base não-zero, streak
/// atravessando virada de mês, e — o furo mais caro — dia ABAIXO do piso. O
/// mínimo por sessão da massa curta é 35 min, então nenhum teste sobre ela
/// consegue provar que o piso rejeita alguma coisa.
///
/// Tudo ancorado em `hoje` (2026-07-29) e semeado com [seedMassaLonga]: os
/// números abaixo são fixos, não dependem do relógio do CI.
void main() {
  final massa = construirMassaLonga();
  final registros = massa.registros;
  final pesos = {for (final m in massa.materias) m.id: m.peso};

  test('UAT-L0 volumetria e janela da massa longa', () {
    final porDia = StatsService.minutosPorDia(registros);
    final meses =
        porDia.keys
            .map((d) => '${d.year}-${d.month.toString().padLeft(2, '0')}')
            .toSet()
            .toList()
          ..sort();
    print(
      '[L0] registros=${registros.length} dias=${porDia.length} meses=$meses',
    );
    expect(registros, hasLength(148));
    expect(porDia, hasLength(99));
    expect(meses, ['2026-04', '2026-05', '2026-06', '2026-07']);
    expect(registros.first.data, DateTime(2026, 4, 1, 20));
    expect(registros.last.data, DateTime(2026, 7, 29, 20));
  });

  test('UAT-L1 soma de minutosPorDia == total dos registros', () {
    final porDia = StatsService.minutosPorDia(registros);
    final somaDia = porDia.values.fold(0, (a, b) => a + b);
    final somaReg = registros.fold(0, (a, r) => a + r.minutos);
    print('[L1] somaDia=$somaDia somaReg=$somaReg');
    expect(somaDia, somaReg);
    expect(somaReg, 9357);
    // E o agregado anual não pode divergir: a massa inteira cai em 2026.
    expect(StatsService.minutosNoAno(registros, 2026), somaReg);
  });

  test('UAT-L2 dia abaixo do piso NÃO conta como dia de estudo real', () {
    final piso = StatsService.pisoMinutosStreak;
    final porDia = StatsService.minutosPorDia(registros);
    final fracos = porDia.entries.where((e) => e.value < piso).toList();
    print(
      '[L2] piso=$piso dias fracos=${fracos.length} '
      '${fracos.map((e) => "${e.key.day}/${e.key.month}:${e.value}min").take(3).toList()}',
    );

    // A contraprova só existe porque a massa longa cria sessões-token.
    expect(fracos, hasLength(6));
    expect(fracos.every((e) => e.value == minutosTokenMassaLonga), isTrue);

    // O streak de um dia fraco isolado é 0: o piso rejeita o dia inteiro,
    // não "meio dia".
    final soFraco = registros
        .where((r) => r.minutos == minutosTokenMassaLonga)
        .toList();
    expect(soFraco, isNotEmpty);
    final diaFraco = StatsService.dataSemHora(soFraco.first.data);
    expect(StatsService.streakDetalhado(soFraco, diaFraco).dias, 0);
  });

  test('UAT-L3 XP bate a fórmula do GamificacaoService, sem quest', () {
    final xp = GamificacaoService.xpDetalhado(
      registros,
      massa.revisoes,
      hoje,
      pesoPorMateria: pesos,
    );
    print(
      '[L3] base=${xp.base} rev=${xp.bonusRevisoes} '
      'streak=${xp.bonusStreak} total=${xp.total}',
    );

    // Cada parcela recomposta pela API pública — se alguém trocar a fórmula
    // por dentro, isto cai junto.
    expect(xp.base, GamificacaoService.xpPonderado(registros, pesos));
    expect(xp.bonusRevisoes, GamificacaoService.bonusRevisoes(massa.revisoes));
    expect(
      xp.bonusStreak,
      StatsService.streakPicoComCongelamento(registros, hoje) *
          GamificacaoService.xpPorDiaDeStreak,
    );
    expect(xp.total, xp.base + xp.bonusRevisoes + xp.bonusStreak);
    expect(xp.total, 12676);
  });

  test('UAT-L4 XP é monótono sob acréscimo de registros', () {
    // A massa é só acréscimo: prefixos cronológicos crescentes nunca podem
    // baixar o XP. Foi assim que o peso perdido na cascata de matéria apareceu
    // (UAT-E2) — a monotonia é a régua.
    final ordenados = [...registros]..sort((a, b) => a.data.compareTo(b.data));
    var anterior = -1;
    for (final corte in [20, 50, 90, 120, ordenados.length]) {
      final prefixo = ordenados.take(corte).toList();
      final xp = GamificacaoService.xpDetalhado(
        prefixo,
        const [],
        hoje,
        pesoPorMateria: pesos,
      ).total;
      print('[L4] $corte registros -> xp=$xp');
      expect(xp, greaterThanOrEqualTo(anterior));
      anterior = xp;
    }
  });

  test('UAT-L5 taxa geral é ponderada e nunca NaN', () {
    final comQuestoes = registros.where((r) => r.questoes != null).toList();
    final questoes = comQuestoes.fold(0, (a, r) => a + r.questoes!);
    final acertos = comQuestoes.fold(0, (a, r) => a + (r.acertos ?? 0));
    final geral = StatsService.taxaAcertoGeral(registros)!;
    print('[L5] $acertos/$questoes = ${geral.toStringAsFixed(4)}');

    // Ponderado pelo total, não média de médias.
    expect(geral, closeTo(acertos / questoes, 1e-9));
    expect(geral.isNaN, isFalse);
    expect(geral, inInclusiveRange(0.0, 1.0));

    // Sessão-token não tem questões: zero questões => null, nunca 0% nem NaN.
    final soToken = registros
        .where((r) => r.minutos == minutosTokenMassaLonga)
        .toList();
    expect(soToken.every((r) => r.questoes == null), isTrue);
    expect(StatsService.taxaAcertoGeral(soToken), isNull);
  });

  test('UAT-L6 forecast coerente com as revisões pendentes', () {
    final forecast = RevisaoService.forecastCarga(
      massa.revisoes,
      hoje,
      dias: 30,
    );
    final pendentes = massa.revisoes.where((r) => !r.feita).toList();
    print(
      '[L6] forecast30=${forecast.fold(0, (a, e) => a + e.quantidade)} '
      'pendentes=${pendentes.length}',
    );

    expect(forecast.every((e) => e.quantidade >= 0), isTrue);
    // Toda pendente da janela cai no forecast; nenhuma fora dela entra.
    final naJanela = pendentes
        .where((r) => !r.dataAgendada.isAfter(dias(30)))
        .length;
    expect(forecast.fold(0, (a, e) => a + e.quantidade), naJanela);
    expect(forecast.fold(0, (a, e) => a + e.quantidade), 9);
  });

  test('UAT-L7 MoM encadeado: 3 bases não-zero + base zero => null', () {
    // Só existe com 4 meses. Na massa curta (2 meses) há uma comparação útil.
    final leituras = [
      for (var i = 0; i < 4; i++)
        StatsService.comparativoMensal(
          registros,
          DateTime(hoje.year, hoje.month - i, 15),
        ),
    ];
    for (var i = 0; i < leituras.length; i++) {
      print(
        '[L7] ${hoje.month - i}: atual=${leituras[i].atual} '
        'anterior=${leituras[i].anterior} var=${leituras[i].variacao}',
      );
    }
    // Julho, junho e maio têm mês anterior com dado.
    for (final c in leituras.take(3)) {
      expect(c.anterior, greaterThan(0));
      expect(c.variacao, isNotNull);
    }
    // Abril é o primeiro mês da janela: base zero => null, nunca infinito.
    expect(leituras[3].anterior, 0);
    expect(leituras[3].variacao, isNull);
  });

  test('UAT-L8 determinismo: âncora fixa, seed fixa, mesmos totais', () {
    final outra = construirMassaLonga();
    expect(
      outra.registros.map((r) => r.id).toList(),
      registros.map((r) => r.id).toList(),
    );
    expect(outra.registros.fold(0, (a, r) => a + r.minutos), 9357);
    // Nenhum id de registro depende de posição de linha de planilha (D-02):
    // aqui o prefixo é próprio da massa, não `xlsx-registro-<i>-<data>`.
    expect(registros.every((r) => r.id.startsWith('long-')), isTrue);
  });
}
