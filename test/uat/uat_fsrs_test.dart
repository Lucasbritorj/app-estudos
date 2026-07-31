// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:app_estudos/domain/revisao_service.dart';

typedef Passo = ({int dias, int intervalo, bool reforco, double estabilidade, double dificuldade});

/// Roda a cadeia FSRS-lite ate encerrar (null) ou estourar [maxPassos].
List<Passo> cadeia({
  required int intervaloInicial,
  required double? taxa,
  int atraso = 0,
  int maxPassos = 40,
}) {
  final out = <Passo>[];
  double? s;
  double? d;
  var intervalo = intervaloInicial;
  for (var i = 0; i < maxPassos; i++) {
    final p = RevisaoService.proximoPassoFsrs(
      estabilidade: s,
      dificuldade: d,
      intervaloAtual: intervalo,
      diasDeAtraso: atraso,
      taxaAcerto: taxa,
    );
    if (p == null) break;
    out.add(p);
    s = p.estabilidade;
    d = p.dificuldade;
    intervalo = p.intervalo;
  }
  return out;
}

String fmt(List<Passo> c) => c
    .map((p) => '${p.dias}d(S=${p.estabilidade.toStringAsFixed(2)},D=${p.dificuldade.toStringAsFixed(2)}${p.reforco ? ",REF" : ""})')
    .join(' -> ');

void main() {
  test('UAT-B1 cadeia sem questoes (taxa null) cresce e encerra no teto', () {
    final c = cadeia(intervaloInicial: 7, taxa: null);
    print('[B1] ${fmt(c)}');
    print('[B1] passos=${c.length} ultimo=${c.last.dias}d teto=${RevisaoService.tetoDiasFsrs}');
    for (var i = 1; i < c.length; i++) {
      expect(c[i].dias, greaterThan(c[i - 1].dias), reason: 'progressao monotona');
    }
    expect(c.last.dias, lessThanOrEqualTo(RevisaoService.tetoDiasFsrs));
    expect(c.length, lessThan(40), reason: 'cadeia termina (nao e infinita)');
  });

  test('UAT-B2 taxa >= 85% (pleno) vs 75-84% (dificil) vs < 75% (lapso)', () {
    final pleno = cadeia(intervaloInicial: 7, taxa: 0.90);
    final dificil = cadeia(intervaloInicial: 7, taxa: 0.80, maxPassos: 12);
    print('[B2] pleno   : ${fmt(pleno.take(6).toList())}');
    print('[B2] dificil : ${fmt(dificil.take(6).toList())}');
    expect(dificil.first.dias, lessThan(pleno.first.dias),
        reason: '75-84% cresce na metade do ritmo');
    expect(dificil.first.dificuldade, greaterThan(pleno.first.dificuldade),
        reason: 'dificil sobe D, pleno baixa D');

    final lapso = RevisaoService.proximoPassoFsrs(
        estabilidade: 30, dificuldade: 5, intervaloAtual: 30, taxaAcerto: 0.60);
    print('[B2] lapso S30 -> ${lapso!.dias}d S=${lapso.estabilidade} D=${lapso.dificuldade} ref=${lapso.reforco}');
    expect(lapso.reforco, isTrue);
    expect(lapso.estabilidade, closeTo(12.0, 1e-9), reason: 'S cai para 40%');
    expect(lapso.dias, 12);
  });

  test('UAT-B3 lapso nunca agenda abaixo de 1 dia nem encerra a cadeia', () {
    final p = RevisaoService.proximoPassoFsrs(
        estabilidade: 1.0, dificuldade: 10, intervaloAtual: 1, taxaAcerto: 0.0);
    print('[B3] lapso no piso: ${p!.dias}d S=${p.estabilidade} D=${p.dificuldade}');
    expect(p.dias, greaterThanOrEqualTo(1));
    expect(p.estabilidade, greaterThanOrEqualTo(1.0));

    final noTeto = RevisaoService.proximoPassoFsrs(
        estabilidade: 400, dificuldade: 5, intervaloAtual: 120, taxaAcerto: 0.10);
    print('[B3] lapso acima do teto: ${noTeto?.dias}d S=${noTeto?.estabilidade}');
    expect(noTeto, isNotNull, reason: 'errou nunca encerra a cadeia');
    expect(noTeto!.dias, lessThanOrEqualTo(RevisaoService.tetoDiasFsrs));
  });

  test('UAT-B4 antecipacao nao queima a cadeia (freio fracaoDecorrida)', () {
    final emDia = RevisaoService.proximoPassoFsrs(
        estabilidade: 60, dificuldade: 5, intervaloAtual: 60, diasDeAtraso: 0, taxaAcerto: null);
    final antecipada = RevisaoService.proximoPassoFsrs(
        estabilidade: 60, dificuldade: 5, intervaloAtual: 60, diasDeAtraso: -59, taxaAcerto: null);
    final antecipMax = RevisaoService.proximoPassoFsrs(
        estabilidade: 60, dificuldade: 5, intervaloAtual: 60, diasDeAtraso: -60, taxaAcerto: null);
    print('[B4] emDia=${emDia?.dias}d antecipada(-59)=${antecipada?.dias}d antecipMax(-60)=${antecipMax?.dias}d');
    expect(antecipada!.dias, lessThan(emDia?.dias ?? 1 << 30));
    expect(antecipMax!.dias, greaterThanOrEqualTo(60), reason: 'nunca reduz abaixo do intervalo vigente');
    expect(antecipMax.estabilidade, greaterThanOrEqualTo(60.0));
  });

  test('UAT-B5 atraso longo: bonus de esquecimento sem estourar teto', () {
    final atrasada = RevisaoService.proximoPassoFsrs(
        estabilidade: 20, dificuldade: 5, intervaloAtual: 20, diasDeAtraso: 200, taxaAcerto: null);
    final emDia = RevisaoService.proximoPassoFsrs(
        estabilidade: 20, dificuldade: 5, intervaloAtual: 20, diasDeAtraso: 0, taxaAcerto: null);
    print('[B5] emDia=${emDia?.dias}d atrasada200=${atrasada?.dias}d');
    expect(atrasada!.dias, greaterThan(emDia!.dias));
    expect(atrasada.dias, lessThanOrEqualTo(RevisaoService.tetoDiasFsrs));
  });

  test('UAT-B6 revisao manual (intervalo 0, sem estado) usa semente', () {
    final p = RevisaoService.proximoPassoFsrs(intervaloAtual: 0, taxaAcerto: null);
    print('[B6] manual -> ${p!.dias}d S=${p.estabilidade.toStringAsFixed(4)} D=${p.dificuldade}');
    expect(p.dias, greaterThanOrEqualTo(1));
    expect(p.estabilidade, greaterThan(3.0), reason: 'semente 3d cresce no 1o passo');
  });

  test('UAT-B7 dificuldade fica em [1,10] e reverte a media', () {
    var d = 10.0;
    final trilha = <double>[];
    for (var i = 0; i < 10; i++) {
      final p = RevisaoService.proximoPassoFsrs(
          estabilidade: 10, dificuldade: d, intervaloAtual: 10, taxaAcerto: 0.95);
      d = p!.dificuldade;
      trilha.add(d);
    }
    print('[B7] D partindo de 10 com acerto alto: ${trilha.map((e) => e.toStringAsFixed(2)).join(" ")}');
    expect(d, lessThan(10.0));
    expect(d, greaterThanOrEqualTo(1.0));

    var dBaixa = 1.0;
    for (var i = 0; i < 10; i++) {
      final p = RevisaoService.proximoPassoFsrs(
          estabilidade: 10, dificuldade: dBaixa, intervaloAtual: 10, taxaAcerto: 0.50);
      dBaixa = p!.dificuldade;
    }
    print('[B7] D partindo de 1 com lapso repetido: ${dBaixa.toStringAsFixed(2)}');
    expect(dBaixa, inInclusiveRange(1.0, 10.0));
  });

  test('UAT-B8 proximoIntervalo (cadeia classica) e bordas', () {
    expect(RevisaoService.proximoIntervalo([7, 15, 30, 60], 0), 7);
    expect(RevisaoService.proximoIntervalo([7, 15, 30, 60], 60), isNull);
    expect(RevisaoService.proximoIntervalo([], 7), isNull);
    expect(RevisaoService.proximoIntervalo([30, 7, 15], 7), 15, reason: 'ordena antes');
    print('[B8] ok: cadeia classica ordena e encerra');
  });

  test('UAT-B9 BORDA estado corrompido: estabilidade 0 / negativa / gigante / NaN', () {
    for (final s in <double>[0.0, -5.0, 1e12, double.nan, double.infinity]) {
      Object? erro;
      Passo? p;
      try {
        p = RevisaoService.proximoPassoFsrs(
            estabilidade: s, dificuldade: 5, intervaloAtual: 7, taxaAcerto: null);
      } catch (e) {
        erro = e;
      }
      print('[B9] S=$s -> ${erro != null ? "EXCEPTION: ${erro.runtimeType}: $erro" : "dias=${p?.dias} S=${p?.estabilidade}"}');
      expect(erro, isNull, reason: 'estado corrompido nunca pode lancar');
      if (p != null) {
        expect(p.dias, inInclusiveRange(1, RevisaoService.tetoDiasFsrs));
        expect(p.estabilidade.isFinite, isTrue);
        expect(p.dificuldade, inInclusiveRange(1.0, 10.0));
      }
    }
    // Dificuldade corrompida tambem nao pode vazar.
    final comD = RevisaoService.proximoPassoFsrs(
        estabilidade: 10, dificuldade: double.nan, intervaloAtual: 10, taxaAcerto: null);
    print('[B9] D=NaN -> dias=${comD?.dias} D=${comD?.dificuldade}');
    expect(comD, isNotNull);
    expect(comD!.dificuldade.isFinite, isTrue);
  });

  test('UAT-B10 BORDA retencaoAlvo extrema', () {
    for (final r in <double>[0.99, 0.9, 0.7, 0.5]) {
      final p = RevisaoService.proximoPassoFsrs(
          estabilidade: 30, dificuldade: 5, intervaloAtual: 30, taxaAcerto: null, retencaoAlvo: r);
      print('[B10] retencao=$r -> ${p == null ? "cadeia encerrada" : "${p.dias}d"}');
    }
  });
}
