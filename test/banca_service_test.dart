import 'package:app_estudos/data/models/bancas.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/simulado.dart';
import 'package:app_estudos/domain/banca_service.dart';
import 'package:flutter_test/flutter_test.dart';

var _seq = 0;

RegistroHora reg({
  required String materiaId,
  String? banca,
  int? questoes,
  int? acertos,
}) => RegistroHora(
  id: 'r-${_seq++}',
  data: DateTime(2026, 7, 9),
  materiaId: materiaId,
  tipo: TipoEstudo.pratica,
  minutos: 60,
  questoes: questoes,
  acertos: acertos,
  banca: banca,
);

Simulado sim({
  required String banca,
  required List<ResultadoMateria> resultados,
}) => Simulado(
  id: 's-${_seq++}',
  ambienteId: 'geral',
  tipo: TipoSimulado.simulado,
  nome: 'Simulado teste',
  banca: banca,
  data: DateTime(2026, 7, 10),
  resultados: resultados,
);

void main() {
  group('Bancas.normalizar', () {
    test('CESPE, cespe e CESPE/CEBRASPE colapsam em CEBRASPE', () {
      expect(Bancas.normalizar('CESPE'), 'CEBRASPE');
      expect(Bancas.normalizar('cespe'), 'CEBRASPE');
      expect(Bancas.normalizar('CESPE/CEBRASPE'), 'CEBRASPE');
      expect(Bancas.normalizar('Cebraspe'), 'CEBRASPE');
      expect(Bancas.normalizar('cebraspe'), 'CEBRASPE');
    });

    test('vazio, só espaço ou null viram null — nunca string vazia', () {
      expect(Bancas.normalizar(''), isNull);
      expect(Bancas.normalizar('   '), isNull);
      expect(Bancas.normalizar(null), isNull);
    });

    test('remove acento e caixa; espaços internos colapsam', () {
      expect(Bancas.normalizar('fgv'), 'FGV');
      expect(Bancas.normalizar('  fgv  '), 'FGV');
      expect(Bancas.normalizar('Fundação Getúlio Vargas'), 'FGV');
      expect(Bancas.normalizar('São Paulo  Concursos'), 'SAO PAULO CONCURSOS');
    });
  });

  group('BancaService.agregar', () {
    test('soma questões/acertos de sessões E simulados na mesma banca', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'CESPE', questoes: 10, acertos: 7),
        reg(materiaId: 'm2', banca: 'cebraspe', questoes: 5, acertos: 3),
        reg(materiaId: 'm1', banca: 'FGV', questoes: 20, acertos: 15),
      ];
      final simulados = [
        sim(
          banca: 'Cebraspe',
          resultados: [
            ResultadoMateria(materiaId: 'm1', questoes: 30, acertos: 20),
          ],
        ),
      ];
      final agregado = BancaService.agregar(registros, simulados);
      // CESPE + cebraspe + Cebraspe colapsam todos em CEBRASPE: 10+5+30=45
      // questões, 7+3+20=30 acertos, 1 simulado.
      expect(agregado['CEBRASPE'], (questoes: 45, acertos: 30, simulados: 1));
      expect(agregado['FGV'], (questoes: 20, acertos: 15, simulados: 0));
      expect(agregado.length, 2);
    });

    test('sessão sem banca fica fora — não existe balde "outras"', () {
      final registros = [
        reg(materiaId: 'm1', banca: null, questoes: 10, acertos: 5),
      ];
      expect(BancaService.agregar(registros, const []), isEmpty);
    });

    test('sessão com questões <= 0 fica fora mesmo com banca informada', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'FGV', questoes: 0, acertos: 0),
      ];
      expect(BancaService.agregar(registros, const []), isEmpty);
    });

    test('simulado sem banca fica fora do agregado', () {
      final simulados = [
        sim(
          banca: '',
          resultados: [
            ResultadoMateria(materiaId: 'm1', questoes: 10, acertos: 5),
          ],
        ),
      ];
      expect(BancaService.agregar(const [], simulados), isEmpty);
    });
  });

  group('BancaService.ranking', () {
    test('exclui banca abaixo da amostra mínima mas mantém no agregado', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'FGV', questoes: 9, acertos: 9),
        reg(materiaId: 'm1', banca: 'FCC', questoes: 10, acertos: 8),
      ];
      final agregado = BancaService.agregar(registros, const []);
      expect(agregado.containsKey('FGV'), isTrue); // segue no agregado bruto

      final ranking = BancaService.ranking(registros, const []);
      expect(ranking.map((d) => d.banca), ['FCC']); // só FCC entra
    });

    test('ordena por taxa desc; empate desempata por questões desc', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'A', questoes: 10, acertos: 5), // 50%
        reg(materiaId: 'm1', banca: 'B', questoes: 10, acertos: 9), // 90%
        reg(
          materiaId: 'm1',
          banca: 'C',
          questoes: 20,
          acertos: 18,
        ), // 90%, mais questões
      ];
      final ranking = BancaService.ranking(registros, const []);
      expect(ranking.map((d) => d.banca).toList(), ['C', 'B', 'A']);
    });

    test('amostra mínima é parametrizável', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'FGV', questoes: 4, acertos: 3),
      ];
      expect(
        BancaService.ranking(
          registros,
          const [],
          amostraMinimaQuestoes: 5,
        ),
        isEmpty,
      );
      expect(
        BancaService.ranking(
          registros,
          const [],
          amostraMinimaQuestoes: 4,
        ).map((d) => d.banca),
        ['FGV'],
      );
    });
  });

  group('BancaService.pontoFraco', () {
    test('acha o pior par banca×matéria com amostra suficiente', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'FGV', questoes: 10, acertos: 8), // 80%
        reg(materiaId: 'm2', banca: 'FGV', questoes: 10, acertos: 3), // 30%
        reg(materiaId: 'm1', banca: 'FCC', questoes: 10, acertos: 9), // 90%
      ];
      final pior = BancaService.pontoFraco(registros, const []);
      expect(pior, isNotNull);
      expect(pior!.banca, 'FGV');
      expect(pior.materiaId, 'm2');
      expect(pior.taxa, 0.3);
      expect(pior.questoes, 10);
    });

    test('em empate mantém o primeiro par inserido — determinístico', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'A', questoes: 10, acertos: 5), // 50%
        reg(
          materiaId: 'm2',
          banca: 'B',
          questoes: 10,
          acertos: 5,
        ), // 50% empatado
      ];
      final pior = BancaService.pontoFraco(registros, const []);
      expect(pior, isNotNull);
      expect(pior!.banca, 'A');
      expect(pior.materiaId, 'm1');
    });

    test('null quando nenhum par atinge a amostra mínima', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'A', questoes: 9, acertos: 1),
      ];
      expect(BancaService.pontoFraco(registros, const []), isNull);
    });

    test('null sem registros nem simulados', () {
      expect(BancaService.pontoFraco(const [], const []), isNull);
    });
  });

  group('BancaService.porBancaEMateria', () {
    test('monta matriz banca×matéria somando sessões e simulados', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'FGV', questoes: 10, acertos: 6),
        reg(materiaId: 'm1', banca: 'FGV', questoes: 5, acertos: 5),
        reg(materiaId: 'm2', banca: 'FGV', questoes: 8, acertos: 2),
      ];
      final simulados = [
        sim(
          banca: 'FGV',
          resultados: [
            ResultadoMateria(materiaId: 'm1', questoes: 10, acertos: 10),
          ],
        ),
      ];
      final matriz = BancaService.porBancaEMateria(registros, simulados);
      expect(matriz['FGV']!['m1'], (questoes: 25, acertos: 21));
      expect(matriz['FGV']!['m2'], (questoes: 8, acertos: 2));
    });

    test('resultado de simulado com questões <= 0 é ignorado na matriz', () {
      final simulados = [
        sim(
          banca: 'FGV',
          resultados: [ResultadoMateria(materiaId: 'm1', questoes: 0, acertos: 0)],
        ),
      ];
      expect(
        BancaService.porBancaEMateria(const [], simulados),
        isEmpty,
      );
    });
  });

  group('BancaService.taxaDaBanca', () {
    test('retorna a taxa da banca específica; null sem dado dela', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'FGV', questoes: 10, acertos: 7),
      ];
      expect(BancaService.taxaDaBanca(registros, const [], 'FGV'), 0.7);
      expect(BancaService.taxaDaBanca(registros, const [], 'FCC'), isNull);
    });
  });

  group('BancaService.bancasUsadas', () {
    test('ordena por frequência desc; empate desempata alfabético', () {
      final registros = [
        reg(materiaId: 'm1', banca: 'FGV', questoes: 10, acertos: 5),
        reg(materiaId: 'm1', banca: 'FCC', questoes: 10, acertos: 5),
        reg(materiaId: 'm1', banca: 'FGV', questoes: 10, acertos: 5),
      ];
      final simulados = [
        sim(
          banca: 'CEBRASPE',
          resultados: [
            ResultadoMateria(materiaId: 'm1', questoes: 5, acertos: 5),
          ],
        ),
      ];
      // FGV usada 2x; CEBRASPE e FCC 1x cada — empate desempatado
      // alfabeticamente (CEBRASPE < FCC).
      expect(BancaService.bancasUsadas(registros, simulados), [
        'FGV',
        'CEBRASPE',
        'FCC',
      ]);
    });
  });

  group('bordas de listas vazias — nada de divisão por zero', () {
    test('todos os métodos aceitam registros e simulados vazios', () {
      expect(BancaService.agregar(const [], const []), isEmpty);
      expect(BancaService.ranking(const [], const []), isEmpty);
      expect(BancaService.pontoFraco(const [], const []), isNull);
      expect(BancaService.porBancaEMateria(const [], const []), isEmpty);
      expect(BancaService.bancasUsadas(const [], const []), isEmpty);
      expect(BancaService.taxaDaBanca(const [], const [], 'FGV'), isNull);
    });
  });
}
