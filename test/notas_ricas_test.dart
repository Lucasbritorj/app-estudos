import 'package:app_estudos/core/utils/notas_ricas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('texto simples vira um segmento sem formatação', () {
    final linhas = parseNotas('só texto');
    expect(linhas, hasLength(1));
    expect(linhas.first.bullet, false);
    expect(linhas.first.segmentos, [const SegmentoNota('só texto')]);
  });

  test('negrito e destaque inline, com texto ao redor', () {
    final linhas = parseNotas('ver **CF art. 5º** e ==prazo de 10 dias== ok');
    expect(linhas.first.segmentos, const [
      SegmentoNota('ver '),
      SegmentoNota('CF art. 5º', negrito: true),
      SegmentoNota(' e '),
      SegmentoNota('prazo de 10 dias', destaque: true),
      SegmentoNota(' ok'),
    ]);
  });

  test('linha com "- " vira bullet; as demais não', () {
    final linhas = parseNotas('título\n- item 1\n- item **2**');
    expect(linhas.map((l) => l.bullet).toList(), [false, true, true]);
    expect(linhas[1].segmentos, [const SegmentoNota('item 1')]);
    expect(linhas[2].segmentos, const [
      SegmentoNota('item '),
      SegmentoNota('2', negrito: true),
    ]);
  });

  test('marcador sem fechar fica literal — nunca lança', () {
    final linhas = parseNotas('abre **sem fechar');
    expect(linhas.first.segmentos, [const SegmentoNota('abre **sem fechar')]);
  });

  test('notas antigas sem marcador passam intactas (retrocompatível)', () {
    final linhas = parseNotas('nota antiga\ncom duas linhas');
    expect(linhas, hasLength(2));
    expect(linhas.every((l) => !l.bullet), true);
    expect(
        linhas.every(
            (l) => l.segmentos.every((s) => !s.negrito && !s.destaque)),
        true);
  });

  test('string vazia rende uma linha vazia (sem crash no render)', () {
    final linhas = parseNotas('');
    expect(linhas, hasLength(1));
    expect(linhas.first.segmentos, isEmpty);
  });
}
