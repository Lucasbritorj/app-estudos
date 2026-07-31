// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import '_massa_fake.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:app_estudos/domain/gamificacao_service.dart';
import 'package:app_estudos/domain/dominio_service.dart';
import 'package:app_estudos/domain/prontidao_service.dart';
import 'package:app_estudos/domain/revisao_service.dart';

void main() {
  final massa = construirMassa();

  test('UAT-A1 carga inicial: volumetria da massa fake', () {
    print('[A1] materias=${massa.materias.length} topicos=${massa.topicos.length} '
        'aulas=${massa.aulas.length} registros=${massa.registros.length} '
        'revisoes=${massa.revisoes.length}');
    expect(massa.materias.length, 5);
    expect(massa.topicos.length, 9);
    expect(massa.registros.length, greaterThan(50));
  });

  test('UAT-A2 horas liquidas: dia/semana/mes/ano coerentes', () {
    final dia = StatsService.minutosNoDia(massa.registros, hoje);
    final semana = StatsService.minutosNaSemana(massa.registros, hoje);
    final mes = StatsService.minutosNoMes(massa.registros, hoje);
    final ano = StatsService.minutosNoAno(massa.registros, hoje.year);
    final total = massa.registros.fold<int>(0, (s, r) => s + r.minutos);
    print('[A2] hoje=${dia}min semana=${semana}min mes=${mes}min ano=${ano}min total=${total}min '
        '(${(total / 60).toStringAsFixed(1)}h)');
    expect(dia, lessThanOrEqualTo(semana));
    expect(semana, lessThanOrEqualTo(mes));
    expect(mes, lessThanOrEqualTo(ano));
    expect(ano, total, reason: 'massa inteira cai em 2026');
  });

  test('UAT-A3 resumo diario e serie de 30 dias', () {
    final r = StatsService.resumoDiario(massa.registros);
    final serie = StatsService.serieDiaria(massa.registros, hoje, 30);
    print('[A3] media=${r.media} max=${r.maximo} min=${r.minimo} '
        'serie30_zeros=${serie.where((e) => e.minutos == 0).length}');
    expect(r.minimo, lessThanOrEqualTo(r.media));
    expect(r.media, lessThanOrEqualTo(r.maximo));
    expect(serie.length, 30);
    expect(serie.last.dia, StatsService.dataSemHora(hoje));
  });

  test('UAT-A4 comparativos MoM/YoY parcial-vs-parcial', () {
    final mom = StatsService.comparativoMensal(massa.registros, hoje);
    final yoy = StatsService.comparativoAnual(massa.registros, hoje);
    print('[A4] MoM atual=${mom.atual} anterior=${mom.anterior} var=${mom.variacao}');
    print('[A4] YoY atual=${yoy.atual} anterior=${yoy.anterior} var=${yoy.variacao}');
    expect(yoy.anterior, 0, reason: 'sem historico em 2025');
    expect(yoy.variacao, isNull, reason: 'base zero => null, nunca infinito');
  });

  test('UAT-A5 desempenho por materia e taxa geral', () {
    final porMat = StatsService.desempenhoPorMateria(massa.registros);
    final geral = StatsService.taxaAcertoGeral(massa.registros);
    for (final m in massa.materias) {
      final d = porMat[m.id];
      final taxa = d == null || d.questoes == 0 ? null : d.acertos / d.questoes;
      print('[A5] ${m.nome}: q=${d?.questoes ?? 0} a=${d?.acertos ?? 0} '
          'taxa=${taxa == null ? "n/d" : "${(taxa * 100).toStringAsFixed(2)}%"}');
      if (d != null) expect(d.acertos, lessThanOrEqualTo(d.questoes));
    }
    print('[A5] taxa geral=${(geral! * 100).toStringAsFixed(2)}%');
    expect(porMat.containsKey('mat-info'), isFalse,
        reason: 'materia sem questoes nao aparece (nao inventa 0%)');
  });

  test('UAT-A6 streak, XP, nivel e badges', () {
    final s = StatsService.streakDetalhado(massa.registros, hoje);
    final pico = StatsService.streakPico(massa.registros);
    final pesos = {for (final m in massa.materias) m.id: m.peso};
    final xp = GamificacaoService.xpDetalhado(
        massa.registros, massa.revisoes, hoje, pesoPorMateria: pesos);
    final nivel = GamificacaoService.progressoNivel(xp.total);
    final badges = GamificacaoService.badges(massa.registros, massa.revisoes, hoje);
    print('[A6] streak dias=${s.dias} congelados=${s.congelados} '
        'recuperados=${s.recuperados} emRisco=${s.emRisco} pico=$pico');
    print('[A6] XP base=${xp.base} revisoes=${xp.bonusRevisoes} streak=${xp.bonusStreak} '
        'total=${xp.total} nivel=${nivel.nivel} (${nivel.xpNoNivel}/${nivel.xpParaProximo})');
    print('[A6] badges=${badges.where((b) => b.conquistada).map((b) => b.id).join(",")}');
    final picoCong = StatsService.streakPicoComCongelamento(massa.registros, hoje);
    print('[A6] picoComCongelamento=$picoCong bonusStreak=${xp.bonusStreak}');
    expect(s.dias, greaterThan(0));
    expect(xp.total, xp.base + xp.bonusRevisoes + xp.bonusStreak);
    expect(picoCong, greaterThanOrEqualTo(s.dias),
        reason: 'invariante: recorde >= streak corrente');
    expect(xp.bonusStreak, picoCong * GamificacaoService.xpPorDiaDeStreak);
  });

  test('UAT-A7 dominio Elo por materia + prontidao', () {
    final medidos = DominioService.dominioPorMateria(
        massa.registros, massa.materias.map((m) => m.id), referencia: hoje);
    final dominios = ProntidaoService.dominiosAtuais(massa.materias, medidos);
    final pr = ProntidaoService.prontidao(massa.materias, dominios);
    final aj = ProntidaoService.prontidaoAjustada(massa.materias, dominios);
    final cob = ProntidaoService.coberturaConfiavel(massa.materias, medidos);
    for (final m in massa.materias) {
      final d = medidos[m.id];
      print('[A7] ${m.nome}: elo=${d?.dominio.toStringAsFixed(4) ?? "n/d"} '
          'q=${d?.questoes ?? 0} confiavel=${d?.confiavel ?? false} '
          'usado=${dominios[m.id]!.toStringAsFixed(4)}');
    }
    print('[A7] prontidao=${(pr! * 100).toStringAsFixed(2)}% '
        'ajustada=${(aj! * 100).toStringAsFixed(2)}% cobertura=${(cob * 100).toStringAsFixed(1)}%');
    expect(aj, lessThanOrEqualTo(pr), reason: 'ajustada penaliza dispersao');
    expect(cob, inInclusiveRange(0.0, 1.0));
  });

  test('UAT-A8 fila de revisoes: atrasadas/hoje/futuras + forecast', () {
    final atrasadas = massa.revisoes.where((r) => r.statusEm(hoje) == RevisaoStatus.atrasada).length;
    final aFazer = massa.revisoes.where((r) => r.statusEm(hoje) == RevisaoStatus.aFazer).length;
    final feitas = massa.revisoes.where((r) => r.feita).length;
    final fc = RevisaoService.forecastCarga(massa.revisoes, hoje, dias: 30);
    print('[A8] atrasadas=$atrasadas aFazer=$aFazer feitas=$feitas');
    print('[A8] forecast dia0=${fc.first.quantidade} soma30=${fc.fold<int>(0, (s, e) => s + e.quantidade)}');
    expect(atrasadas, 2);
    expect(feitas, 4);
    expect(fc.first.quantidade, 4, reason: '2 atrasadas + 2 de hoje caem no dia 0');
  });

  test('UAT-A9 ritmo de leitura (paginas/hora) e teoria vs pratica', () {
    final ritmo = StatsService.paginasPorHoraGeral(massa.registros);
    final tipo = StatsService.minutosPorTipo(massa.registros);
    print('[A9] pag/h=${ritmo?.toStringAsFixed(2) ?? "n/d"} '
        'teoria=${tipo.teoria}min pratica=${tipo.pratica}min');
    expect(tipo.teoria + tipo.pratica,
        massa.registros.fold<int>(0, (s, r) => s + r.minutos));
  });
}
