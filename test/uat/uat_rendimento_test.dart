// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import '_massa_fake.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:app_estudos/domain/revisao_service.dart';
import 'package:app_estudos/domain/mapa_estudos_service.dart';
import 'package:app_estudos/domain/dominio_service.dart';

RegistroHora reg({
  required String id,
  required DateTime data,
  String materia = 'mat-x',
  String? topico,
  int minutos = 60,
  int? questoes,
  int? acertos,
  int? pIni,
  int? pFim,
}) => RegistroHora(
      id: id,
      data: data,
      materiaId: materia,
      topicoId: topico,
      minutos: minutos,
      questoes: questoes,
      acertos: acertos,
      paginaInicial: pIni,
      paginaFinal: pFim,
    );

void main() {
  test('UAT-C1 BORDA divisao por zero: 0 questoes => null, nunca 0% nem NaN', () {
    final so0 = [reg(id: '1', data: hoje, questoes: 0, acertos: 0)];
    print('[C1] taxaGeral(questoes=0)=${StatsService.taxaAcertoGeral(so0)}');
    print('[C1] desempenhoPorMateria=${StatsService.desempenhoPorMateria(so0)}');
    print('[C1] taxaDoTopico=${MapaEstudosService.taxaDoTopico(so0, "top-x")}');
    print('[C1] taxaAcertoDe=${RevisaoService.taxaAcertoDe(so0, materiaId: "mat-x")}');
    print('[C1] dominioDe=${DominioService.dominioDe(so0)}');
    expect(StatsService.taxaAcertoGeral(so0), isNull);
    expect(StatsService.desempenhoPorMateria(so0), isEmpty);
    expect(RevisaoService.taxaAcertoDe(so0, materiaId: 'mat-x'), isNull);
    expect(DominioService.dominioDe(so0), isNull);
    expect(StatsService.taxaAcertoGeral(const []), isNull);
    expect(StatsService.paginasPorHoraGeral(const []), isNull);
    expect(StatsService.resumoDiario(const []), (media: 0, maximo: 0, minimo: 0));
  });

  test('UAT-C2 invariante acertos <= questoes (form, calculo e backup)', () {
    final direto = reg(id: '1', data: hoje, questoes: 10, acertos: 99);
    final negativo = reg(id: '2', data: hoje, questoes: -5, acertos: -3);
    final semQ = reg(id: '3', data: hoje, questoes: null, acertos: 7);
    print('[C2] direto q=${direto.questoes} a=${direto.acertos} taxa=${direto.taxaAcerto}');
    print('[C2] negativo q=${negativo.questoes} a=${negativo.acertos} taxa=${negativo.taxaAcerto}');
    print('[C2] semQuestoes q=${semQ.questoes} a=${semQ.acertos} taxa=${semQ.taxaAcerto}');
    expect(direto.acertos, 10);
    expect(negativo.questoes, 0);
    expect(negativo.acertos, 0);
    expect(semQ.acertos, isNull);

    final viaBackup = RegistroHora.fromJson({
      'id': 'b1', 'data': hoje.toIso8601String(), 'materiaId': 'mat-x',
      'minutos': 999999, 'questoes': 10, 'acertos': 500,
    });
    print('[C2] backup minutos=${viaBackup.minutos} (teto=${RegistroHora.maxMinutosPorSessao}) '
        'a=${viaBackup.acertos} taxa=${viaBackup.taxaAcerto}');
    expect(viaBackup.acertos, 10);
    expect(viaBackup.minutos, RegistroHora.maxMinutosPorSessao);
    expect(viaBackup.taxaAcerto, 1.0);
  });

  test('UAT-C3 percentual exato = acertos/questoes*100 (ponderado, nao media de medias)', () {
    final rs = [
      reg(id: '1', data: dias(-2), questoes: 100, acertos: 50),
      reg(id: '2', data: dias(-1), questoes: 10, acertos: 10),
    ];
    final geral = StatsService.taxaAcertoGeral(rs)!;
    print('[C3] ponderado=${(geral * 100).toStringAsFixed(4)}% '
        'media-de-medias=${((0.5 + 1.0) / 2 * 100).toStringAsFixed(2)}%');
    expect(geral, closeTo(60 / 110, 1e-12));
    expect(geral * 100, closeTo(54.5454545454, 1e-8));
  });

  test('UAT-C4 janela de recencia: ultimas 10 sessoes com questoes', () {
    final rs = [
      for (var i = 0; i < 10; i++) reg(id: 'velho$i', data: dias(-100 + i), questoes: 10, acertos: 0),
      for (var i = 0; i < 10; i++) reg(id: 'novo$i', data: dias(-9 + i), questoes: 10, acertos: 10),
    ];
    final taxa = RevisaoService.taxaAcertoDe(rs, materiaId: 'mat-x');
    print('[C4] taxa janela10=$taxa (acumulada seria 0.5)');
    expect(taxa, 1.0, reason: 'periodo ruim antigo nao segura mais o intervalo');
    final taxa3 = RevisaoService.taxaAcertoDe(rs, materiaId: 'mat-x', ultimasSessoes: 20);
    expect(taxa3, closeTo(0.5, 1e-12));
  });

  test('UAT-C5 escopo topico vs materia na taxa da revisao', () {
    final rs = [
      reg(id: '1', data: dias(-1), materia: 'mat-x', topico: 'top-a', questoes: 10, acertos: 2),
      reg(id: '2', data: dias(-1), materia: 'mat-x', topico: 'top-b', questoes: 10, acertos: 10),
    ];
    final porTopico = RevisaoService.taxaAcertoDe(rs, materiaId: 'mat-x', topicoId: 'top-a');
    final porMateria = RevisaoService.taxaAcertoDe(rs, materiaId: 'mat-x');
    print('[C5] topico-a=$porTopico materia=$porMateria');
    expect(porTopico, closeTo(0.2, 1e-12));
    expect(porMateria, closeTo(0.6, 1e-12));
  });

  test('UAT-C6 paginas lidas inclusivas e intervalo invertido', () {
    final ok = reg(id: '1', data: hoje, pIni: 10, pFim: 20, minutos: 60);
    final invertido = reg(id: '2', data: hoje, pIni: 20, pFim: 10, minutos: 60);
    final semMinutos = reg(id: '3', data: hoje, pIni: 1, pFim: 10, minutos: 0);
    print('[C6] inclusivo=${ok.paginasLidas} ritmo=${ok.paginasPorHora} '
        'invertido=${invertido.paginasLidas} semMinutos=${semMinutos.paginasPorHora}');
    expect(ok.paginasLidas, 11);
    expect(ok.paginasPorHora, closeTo(11.0, 1e-12));
    expect(invertido.paginasLidas, isNull);
    expect(semMinutos.paginasPorHora, isNull, reason: 'nunca divide por zero minutos');
  });

  test('UAT-C7 massa real: soma por materia = total e taxa por topico', () {
    final massa = construirMassa();
    final porMat = StatsService.minutosPorMateria(massa.registros);
    final total = massa.registros.fold<int>(0, (s, r) => s + r.minutos);
    print('[C7] soma por materia=${porMat.values.fold<int>(0, (a, b) => a + b)} total=$total');
    expect(porMat.values.fold<int>(0, (a, b) => a + b), total);
    final porTop = StatsService.desempenhoPorTopico(massa.registros);
    for (final e in porTop.entries) {
      expect(e.value.acertos, lessThanOrEqualTo(e.value.questoes));
    }
    print('[C7] topicos com questoes=${porTop.length} '
        '(top-conc sem questoes presente? ${porTop.containsKey("top-conc")})');
    expect(porTop.containsKey('top-conc'), isFalse, reason: 'topico so de teoria nao entra');
  });
}
