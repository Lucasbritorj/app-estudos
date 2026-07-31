// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import '_massa_fake.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/mapa_estudos_service.dart';

/// Transcricao FIEL de TopicosScreen._emOrdemHierarquica
/// (lib/features/materias/topicos_screen.dart:79-104) — a logica de
/// renderizacao da arvore vive dentro do widget, entao o UAT a replica
/// para poder exercita-la fora do Flutter.
List<(Topico, int)> emOrdemHierarquica(List<Topico> topicos) {
  final porPai = <String?, List<Topico>>{};
  for (final t in topicos) {
    porPai.putIfAbsent(t.parentId, () => []).add(t);
  }
  final resultado = <(Topico, int)>[];
  final emitidos = <String>{};

  void visitar(String? paiId, int profundidade) {
    for (final t in porPai[paiId] ?? const <Topico>[]) {
      if (!emitidos.add(t.id)) continue;
      resultado.add((t, profundidade));
      visitar(t.id, profundidade + 1);
    }
  }

  visitar(null, 0);
  for (final t in topicos) {
    if (!emitidos.add(t.id)) continue;
    resultado.add((t, 0));
    visitar(t.id, 1);
  }
  return resultado;
}

Topico t(String id, {String? pai, String nome = '', int peso = 1, List<String> pre = const []}) =>
    Topico(id: id, materiaId: 'mat-x', parentId: pai, nome: nome.isEmpty ? id : nome, peso: peso, prerequisitos: pre);

void main() {
  test('UAT-F1 arvore normal: raiz seguida dos filhos, profundidade correta', () {
    final massa = construirMassa();
    final doConst = massa.topicos.where((x) => x.materiaId == 'mat-const').toList();
    final ordem = emOrdemHierarquica(doConst);
    print('[F1] ${ordem.map((e) => "${"  " * e.$2}${e.$1.nome}").join(" | ")}');
    expect(ordem.length, doConst.length, reason: 'nenhum topico perdido');
    expect(ordem.first.$1.id, 'top-df');
    expect(ordem[1].$2, 1, reason: 'subtopico indentado');
  });

  test('UAT-F2 excluir o PAI promove os filhos a raiz (nao desaparecem)', () {
    final lista = [t('pai'), t('f1', pai: 'pai'), t('f2', pai: 'pai'), t('neto', pai: 'f1')];
    final semPai = lista.where((x) => x.id != 'pai').toList();
    final ordem = emOrdemHierarquica(semPai);
    print('[F2] apos excluir o pai: ${ordem.map((e) => "${e.$1.id}@${e.$2}").join(" ")}');
    expect(ordem.length, 3, reason: 'orfaos preservados');
    expect(ordem.map((e) => e.$1.id).toSet(), {'f1', 'f2', 'neto'});
    expect(ordem.where((e) => e.$1.id == 'neto').length, 1, reason: 'sem duplicata');
  });

  test('UAT-F3 REGRESSAO: ciclo em parentId nao esconde topico nem travar', () {
    final ciclo = [t('a', pai: 'b'), t('b', pai: 'a'), t('livre')];
    final ordem = emOrdemHierarquica(ciclo);
    print('[F3] ciclo a<->b -> lista renderizada=${ordem.map((e) => "${e.$1.id}@${e.$2}").join(" ")}');
    expect(ordem.length, ciclo.length, reason: 'nenhum topico sumiu');
    expect(ordem.map((e) => e.$1.id).toSet(), {'a', 'b', 'livre'});
    expect(ordem.map((e) => e.$1.id).toList().length,
        ordem.map((e) => e.$1.id).toSet().length, reason: 'sem duplicata');
  });

  test('UAT-F4 REGRESSAO: auto-pai (parentId == id) continua visivel', () {
    final auto = [t('self', pai: 'self'), t('ok')];
    final ordem = emOrdemHierarquica(auto);
    print('[F4] auto-pai -> ${ordem.map((e) => "${e.$1.id}@${e.$2}").join(" ")}');
    expect(ordem.map((e) => e.$1.id).toSet(), {'self', 'ok'});
  });

  test('UAT-F4b REGRESSAO: ciclo de 3 + filho pendurado no ciclo', () {
    final lista = [t('x', pai: 'z'), t('y', pai: 'x'), t('z', pai: 'y'), t('folha', pai: 'z')];
    final ordem = emOrdemHierarquica(lista);
    print('[F4b] ${ordem.map((e) => "${e.$1.id}@${e.$2}").join(" ")}');
    expect(ordem.length, 4);
    expect(ordem.map((e) => e.$1.id).toSet(), {'x', 'y', 'z', 'folha'});
  });

  test('UAT-F5 criariaCiclo protege prerequisitos (mas nada protege parentId)', () {
    final lista = [t('a'), t('b', pre: ['a']), t('c', pre: ['b'])];
    print('[F5] a->a? ${MapaEstudosService.criariaCiclo(lista, "a", "a")}');
    print('[F5] a<-c (fecharia a->b->c->a)? ${MapaEstudosService.criariaCiclo(lista, "a", "c")}');
    print('[F5] c<-a (aresta redundante, sem ciclo)? ${MapaEstudosService.criariaCiclo(lista, "c", "a")}');
    expect(MapaEstudosService.criariaCiclo(lista, 'a', 'a'), isTrue);
    expect(MapaEstudosService.criariaCiclo(lista, 'a', 'c'), isTrue);
    expect(MapaEstudosService.criariaCiclo(lista, 'c', 'a'), isFalse);
  });

  test('UAT-F6 prerequisito apagado nao trava a fronteira', () {
    final lista = [t('vivo', pre: ['fantasma'], peso: 5), t('outro', peso: 1)];
    final fronteira = MapaEstudosService.fronteira(lista, const []);
    print('[F6] fronteira com pre-requisito inexistente=${fronteira.map((x) => x.id).join(",")}');
    expect(fronteira.map((x) => x.id), ['vivo', 'outro'], reason: 'ordena por peso desc');
    expect(MapaEstudosService.bloqueadoPor(lista.first, lista, const []), isEmpty);
  });

  test('UAT-F7 fronteira respeita conclusao e dominio de liberacao', () {
    final base = t('base');
    final dep = t('dep', pre: ['base']);
    final fronteiraBloqueada = MapaEstudosService.fronteira([base, dep], const []);
    final concluido = base.copyWith(concluido: true);
    final fronteiraLiberada = MapaEstudosService.fronteira([concluido, dep], const []);
    print('[F7] bloqueada=${fronteiraBloqueada.map((x) => x.id).join(",")} '
        'liberada=${fronteiraLiberada.map((x) => x.id).join(",")}');
    expect(fronteiraBloqueada.map((x) => x.id), ['base']);
    expect(fronteiraLiberada.map((x) => x.id), ['dep']);
  });

  test('UAT-F8 peso do topico nunca rebaixa via backup (invariante >= 1)', () {
    final zero = Topico.fromJson({'id': 'z', 'materiaId': 'm', 'nome': 'z', 'peso': 0});
    final neg = Topico.fromJson({'id': 'n', 'materiaId': 'm', 'nome': 'n', 'peso': -9});
    print('[F8] peso 0 -> ${zero.peso} | peso -9 -> ${neg.peso}');
    expect(zero.peso, 1);
    expect(neg.peso, 1);
    final comCiclo = Topico.fromJson({'id': 'a', 'materiaId': 'm', 'nome': 'a', 'parentId': 'a'});
    print('[F8] >>> fromJson ACEITA parentId == id: ${comCiclo.parentId}');
    expect(comCiclo.parentId, 'a', reason: 'nenhuma validacao de hierarquia no import');
  });

  test('UAT-F9 profundidade extrema: 500 niveis nao estoura a pilha', () {
    final cadeia = [t('n0'), for (var i = 1; i < 500; i++) t('n$i', pai: 'n${i - 1}')];
    final ordem = emOrdemHierarquica(cadeia);
    print('[F9] profundidade max renderizada=${ordem.map((e) => e.$2).reduce((a, b) => a > b ? a : b)} '
        'itens=${ordem.length}');
    expect(ordem.length, 500);
  });
}
