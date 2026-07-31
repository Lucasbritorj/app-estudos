import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/edital_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cobertura de domínio do edital verticalizado: situação por tópico
/// (intocado/estudado/frágil/dominado), cobertura ponderada por peso,
/// cobertura geral e ordenação dos buracos. Números do Elo (frágil/
/// dominado) foram conferidos batendo o algoritmo de `DominioService`
/// fora do teste — ver comentário em cada caso.
void main() {
  final hoje = DateTime(2026, 1, 10);

  Materia materia(String id, {int peso = 1, bool arquivada = false}) => Materia(
    id: id,
    nome: id.toUpperCase(),
    corSlot: 0,
    peso: peso,
    arquivada: arquivada,
    criadaEm: DateTime(2025, 1, 1),
  );

  Topico topico(
    String id,
    String materiaId, {
    int peso = 1,
    bool concluido = false,
    String? nome,
  }) => Topico(
    id: id,
    materiaId: materiaId,
    nome: nome ?? id,
    peso: peso,
    concluido: concluido,
  );

  RegistroHora registro(
    String id,
    String materiaId,
    String? topicoId, {
    int minutos = 30,
    int? questoes,
    int? acertos,
    DateTime? data,
  }) => RegistroHora(
    id: id,
    data: data ?? hoje,
    materiaId: materiaId,
    topicoId: topicoId,
    minutos: minutos,
    questoes: questoes,
    acertos: acertos,
  );

  group('linhas — situação por tópico', () {
    test('tópico sem nenhum registro é intocado', () {
      final t = topico('t1', 'm1');
      final linhas = EditalService.linhas([t], const []);
      expect(linhas.single.situacao, SituacaoTopico.intocado);
      expect(linhas.single.minutos, 0);
      expect(linhas.single.questoes, 0);
    });

    test('tópico com sessão mas sem questões é estudado', () {
      final t = topico('t1', 'm1');
      final r = registro('r1', 'm1', 't1', minutos: 40);
      final linhas = EditalService.linhas([t], [r]);
      expect(linhas.single.situacao, SituacaoTopico.estudado);
      expect(linhas.single.minutos, 40);
    });

    test('domínio Elo confiável abaixo de 0,6 é frágil', () {
      final t = topico('t1', 'm1');
      // 1 sessão de 10 questões / 7 acertos, mesmo dia da referência:
      // rating = 0,8*(0,7-0,5) = 0,16 -> dominio = sigmoide(0,16) ≈ 0,540.
      // 10 questões >= amostraMinima (10) -> confiável, e 0,540 < 0,6.
      final r = registro('r1', 'm1', 't1', questoes: 10, acertos: 7);
      final linhas = EditalService.linhas([t], [r], referencia: hoje);
      expect(linhas.single.situacao, SituacaoTopico.fragil);
      expect(linhas.single.dominio, lessThan(0.6));
      expect(linhas.single.dominio, isNotNull);
    });

    test('domínio Elo confiável a partir de 0,6 é dominado', () {
      final t = topico('t1', 'm1');
      // 2 sessões de 10 questões / 10 acertos no mesmo dia (sem
      // decaimento de recência entre elas nem até a referência): rating
      // acumula 0,4 na 1ª sessão e +0,321 na 2ª = 0,721 ->
      // dominio = sigmoide(0,721) ≈ 0,673 >= 0,6, confiável (20 questões).
      final registros = [
        registro('r1', 'm1', 't1', questoes: 10, acertos: 10, data: hoje),
        registro('r2', 'm1', 't1', questoes: 10, acertos: 10, data: hoje),
      ];
      final linhas = EditalService.linhas([t], registros, referencia: hoje);
      expect(linhas.single.situacao, SituacaoTopico.dominado);
      expect(linhas.single.dominio, greaterThanOrEqualTo(0.6));
    });

    test('tópico concluído manualmente é dominado mesmo sem sessão', () {
      final t = topico('t1', 'm1', concluido: true);
      final linhas = EditalService.linhas([t], const []);
      expect(linhas.single.situacao, SituacaoTopico.dominado);
      expect(linhas.single.minutos, 0);
    });
  });

  group('cobertura', () {
    test('pondera por peso do tópico, não por contagem', () {
      final a = topico('a', 'm1', peso: 1, concluido: true); // dominado
      final b = topico('b', 'm1', peso: 3); // intocado
      final mat = materia('m1');
      final resultado = EditalService.coberturaPorMateria(
        [mat],
        [a, b],
        const [],
      );
      final c = resultado.single;
      expect(c.totalTopicos, 2);
      expect(c.dominados, 1);
      expect(c.intocados, 1);
      // peso dominado (1) / peso total (1+3=4) = 0,25 — NÃO 0,5 (metade
      // dos tópicos): prova que quem manda é o peso, não a contagem.
      expect(c.cobertura, closeTo(0.25, 1e-9));
    });

    test(
      'matéria sem tópico cadastrado tem cobertura 0 com totalTopicos 0',
      () {
        final mat = materia('m1');
        final c = EditalService.cobertura(mat, const []);
        expect(c.totalTopicos, 0);
        expect(c.cobertura, 0.0);
        expect(c.coberturaTocada, 0.0);
        expect(c.intocados, 0);
        expect(c.dominados, 0);
      },
    );
  });

  group('coberturaGeral', () {
    test('é null quando não há tópico cadastrado', () {
      final mat = materia('m1');
      final geral = EditalService.coberturaGeral([mat], const [], const []);
      expect(geral, isNull);
    });

    test('pondera por peso da matéria × peso do tópico', () {
      final matA = materia('mA', peso: 1);
      final matB = materia('mB', peso: 5);
      final tA = topico('ta', 'mA', peso: 1, concluido: true); // peso 1*1
      final tB = topico('tb', 'mB', peso: 1); // intocado, peso 5*1
      final geral = EditalService.coberturaGeral(
        [matA, matB],
        [tA, tB],
        const [],
      );
      // dominado: só tA (peso 1). total: 1 + 5 = 6.
      expect(geral, closeTo(1 / 6, 1e-9));
    });
  });

  group('buracos', () {
    test('ordenam por prioridade desc; empate: intocado antes de frágil, '
        'depois por nome', () {
      final matX = materia('mX', peso: 2);
      final matY = materia('mY', peso: 1);

      // prioridade 6 (peso 2 × peso 3), intocados:
      final abelha = topico('abelha', 'mX', peso: 3, nome: 'Abelha');
      final zebra = topico('zebra', 'mX', peso: 3, nome: 'Zebra');
      // mesma prioridade 6, mas frágil — deve vir DEPOIS dos intocados.
      final fragilSeis = topico(
        'fragilSeis',
        'mX',
        peso: 3,
        nome: 'Fragil Seis',
      );
      // prioridade 5 (peso 1 × peso 5), intocado.
      final prontaCinco = topico(
        'prontaCinco',
        'mY',
        peso: 5,
        nome: 'ProntaCinco',
      );
      // prioridade 2 (peso 2 × peso 1), frágil.
      final fragilDois = topico(
        'fragilDois',
        'mX',
        peso: 1,
        nome: 'FragilDois',
      );

      // fragilSeis/fragilDois: mesma sessão 10Q/7A do teste de situação
      // acima (dominio ≈ 0,540, confiável, < 0,6 -> frágil).
      final registros = [
        registro(
          'r1',
          'mX',
          'fragilSeis',
          questoes: 10,
          acertos: 7,
          data: hoje,
        ),
        registro(
          'r2',
          'mX',
          'fragilDois',
          questoes: 10,
          acertos: 7,
          data: hoje,
        ),
      ];

      final buracos = EditalService.buracos(
        [matX, matY],
        [abelha, zebra, fragilSeis, prontaCinco, fragilDois],
        registros,
        referencia: hoje,
      );

      expect(buracos.map((b) => b.linha.topico.nome).toList(), [
        'Abelha',
        'Zebra',
        'Fragil Seis',
        'ProntaCinco',
        'FragilDois',
      ]);
      expect(buracos.map((b) => b.prioridade).toList(), [6, 6, 6, 5, 2]);
    });

    test('limite corta a lista mantendo a ordem', () {
      final matX = materia('mX', peso: 1);
      final topicos = [
        topico('t1', 'mX', peso: 5, nome: 'T1'),
        topico('t2', 'mX', peso: 3, nome: 'T2'),
        topico('t3', 'mX', peso: 1, nome: 'T3'),
      ];
      final buracos = EditalService.buracos(
        [matX],
        topicos,
        const [],
        limite: 2,
      );
      expect(buracos.length, 2);
      expect(buracos.map((b) => b.linha.topico.nome).toList(), ['T1', 'T2']);
    });

    test('ignora tópico de matéria arquivada', () {
      final matArq = materia('mArq', peso: 5, arquivada: true);
      final t = topico('t1', 'mArq', peso: 5, nome: 'Arquivado');
      final buracos = EditalService.buracos([matArq], [t], const []);
      expect(buracos, isEmpty);
    });
  });

  group('distribuicao', () {
    test('conta tópicos por situação e ignora matéria arquivada', () {
      final matAtiva = materia('mAtiva');
      final matArq = materia('mArq', arquivada: true);
      final tIntocado = topico('t1', 'mAtiva');
      final tDominado = topico('t2', 'mAtiva', concluido: true);
      final tArquivado = topico('t3', 'mArq');

      final dist = EditalService.distribuicao(
        [matAtiva, matArq],
        [tIntocado, tDominado, tArquivado],
        const [],
      );

      expect(dist[SituacaoTopico.intocado], 1);
      expect(dist[SituacaoTopico.dominado], 1);
      expect(dist[SituacaoTopico.estudado], 0);
      expect(dist[SituacaoTopico.fragil], 0);
      // Soma bate com os tópicos da matéria ATIVA (2), não com os 3
      // cadastrados — o tópico da matéria arquivada não entra na conta.
      expect(dist.values.fold(0, (a, b) => a + b), 2);
    });
  });
}
