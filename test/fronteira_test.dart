import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/mapa_estudos_service.dart';
import 'package:flutter_test/flutter_test.dart';

Topico topico(String id,
        {List<String> prerequisitos = const [],
        bool concluido = false,
        int peso = 1,
        String? nome}) =>
    Topico(
      id: id,
      materiaId: 'm1',
      nome: nome ?? id,
      peso: peso,
      concluido: concluido,
      prerequisitos: prerequisitos,
    );

RegistroHora sessao(String topicoId, int questoes, int acertos) =>
    RegistroHora(
      id: '$topicoId-$questoes-$acertos',
      data: DateTime(2026, 7, 1),
      materiaId: 'm1',
      topicoId: topicoId,
      minutos: 60,
      questoes: questoes,
      acertos: acertos,
    );

void main() {
  group('satisfeito / bloqueadoPor', () {
    test('concluído satisfaz sem precisar de questões', () {
      expect(
          MapaEstudosService.satisfeito(topico('a', concluido: true), const []),
          isTrue);
    });

    test('domínio confiável acima do limiar satisfaz', () {
      // 2 sessões cheias boas: domínio ~0.67 >= 0.6, 20 questões >= 10.
      final registros = [sessao('a', 10, 10), sessao('a', 10, 10)];
      expect(MapaEstudosService.satisfeito(topico('a'), registros), isTrue);
    });

    test('domínio alto com pouca amostra NÃO satisfaz', () {
      final registros = [sessao('a', 5, 5)]; // 5 questões < amostra mínima
      expect(MapaEstudosService.satisfeito(topico('a'), registros), isFalse);
    });

    test('domínio baixo não satisfaz', () {
      final registros = [sessao('a', 10, 3), sessao('a', 10, 4)];
      expect(MapaEstudosService.satisfeito(topico('a'), registros), isFalse);
    });

    test('bloqueadoPor lista só os pré-requisitos pendentes', () {
      final todos = [
        topico('a', concluido: true),
        topico('b'),
        topico('c', prerequisitos: ['a', 'b']),
      ];
      final bloqueios =
          MapaEstudosService.bloqueadoPor(todos[2], todos, const []);
      expect(bloqueios.map((t) => t.id), ['b']);
    });

    test('pré-requisito apagado é ignorado — nunca trava para sempre', () {
      final todos = [
        topico('c', prerequisitos: ['fantasma']),
      ];
      expect(MapaEstudosService.bloqueadoPor(todos[0], todos, const []),
          isEmpty);
    });
  });

  group('fronteira', () {
    test('sem pré-requisitos: todo não concluído entra, por peso desc', () {
      final todos = [
        topico('a', peso: 1),
        topico('b', peso: 3),
        topico('c', concluido: true, peso: 5),
      ];
      expect(
          MapaEstudosService.fronteira(todos, const []).map((t) => t.id),
          ['b', 'a']);
    });

    test('bloqueado fica fora; libera quando o pré-requisito conclui', () {
      final antes = [
        topico('base'),
        topico('avancado', prerequisitos: ['base']),
      ];
      expect(MapaEstudosService.fronteira(antes, const []).map((t) => t.id),
          ['base']);

      final depois = [
        topico('base', concluido: true),
        topico('avancado', prerequisitos: ['base']),
      ];
      expect(MapaEstudosService.fronteira(depois, const []).map((t) => t.id),
          ['avancado']);
    });

    test('domínio comprovado libera dependente sem marcar concluído', () {
      final todos = [
        topico('base'),
        topico('avancado', prerequisitos: ['base']),
      ];
      final registros = [sessao('base', 10, 10), sessao('base', 10, 9)];
      expect(
          MapaEstudosService.fronteira(todos, registros).map((t) => t.id),
          containsAll(['base', 'avancado']));
    });
  });

  group('criariaCiclo (grafo deve permanecer DAG)', () {
    test('auto-referência é ciclo', () {
      expect(MapaEstudosService.criariaCiclo([topico('a')], 'a', 'a'), isTrue);
    });

    test('ciclo direto: b depende de a, adicionar b como pré de a', () {
      final todos = [
        topico('a'),
        topico('b', prerequisitos: ['a']),
      ];
      expect(MapaEstudosService.criariaCiclo(todos, 'a', 'b'), isTrue);
      expect(MapaEstudosService.criariaCiclo(todos, 'b', 'a'), isFalse,
          reason: 'aresta já existente não é ciclo novo');
    });

    test('ciclo transitivo: a -> b -> c, adicionar c como pré de a', () {
      final todos = [
        topico('a'),
        topico('b', prerequisitos: ['a']),
        topico('c', prerequisitos: ['b']),
      ];
      expect(MapaEstudosService.criariaCiclo(todos, 'a', 'c'), isTrue);
      expect(MapaEstudosService.criariaCiclo(todos, 'c', 'a'), isFalse);
    });

    test('id inexistente nunca é ciclo', () {
      expect(MapaEstudosService.criariaCiclo([topico('a')], 'a', 'fantasma'),
          isFalse);
    });
  });

  test('prerequisitos sobrevivem a json e copyWith', () {
    final original = topico('c', prerequisitos: ['a', 'b']);
    expect(Topico.fromJson(original.toJson()).prerequisitos, ['a', 'b']);
    expect(original.copyWith(concluido: true).prerequisitos, ['a', 'b']);
    expect(original.copyWith(prerequisitos: []).prerequisitos, isEmpty);
    // JSON antigo sem o campo: lista vazia, nunca quebra.
    final antigo = Topico.fromJson({
      'id': 'x',
      'materiaId': 'm1',
      'nome': 'X',
    });
    expect(antigo.prerequisitos, isEmpty);
  });
}
