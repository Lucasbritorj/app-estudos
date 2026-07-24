import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/simulado.dart';
import 'package:app_estudos/domain/aula_service.dart';
import 'package:app_estudos/domain/planejamento_service.dart';
import 'package:flutter_test/flutter_test.dart';

Materia m(String id,
        {int peso = 1, int intimidade = 3, int? minutosAlvo}) =>
    Materia(
      id: id,
      nome: id,
      corSlot: 0,
      peso: peso,
      intimidade: intimidade,
      minutosAlvo: minutosAlvo,
      criadaEm: DateTime(2026, 1, 1),
    );

void main() {
  group('Simulado — derivados', () {
    final simulado = Simulado(
      id: 's1',
      ambienteId: 'geral',
      tipo: TipoSimulado.prova,
      nome: 'SEFAZ objetiva',
      cargo: 'Auditor — FGV',
      data: DateTime(2026, 7, 5),
      tempoMinutos: 240,
      // Deixou de ser const: ResultadoMateria virou factory com invariantes
      // (clamp de acertos/questões) — M-05.
      resultados: [
        ResultadoMateria(materiaId: 'm1', questoes: 40, acertos: 30),
        ResultadoMateria(materiaId: 'm2', questoes: 20, acertos: 18),
      ],
    );

    test('totais, erros e taxa calculados — nunca inputados', () {
      expect(simulado.totalQuestoes, 60);
      expect(simulado.totalAcertos, 48);
      expect(simulado.totalErros, 12);
      expect(simulado.taxaGeral, closeTo(0.8, 1e-9));
      expect(simulado.resultados.first.erros, 10);
      expect(simulado.resultados.first.taxa, closeTo(0.75, 1e-9));
    });

    test('minutosPorQuestao = tempo / questões; null sem tempo', () {
      expect(simulado.minutosPorQuestao, closeTo(4.0, 1e-9));
      final semTempo = Simulado(
        id: 's2',
        ambienteId: 'geral',
        tipo: TipoSimulado.simulado,
        nome: 'X',
        data: DateTime(2026, 7, 5),
        resultados: simulado.resultados,
      );
      expect(semTempo.minutosPorQuestao, null);
    });

    test('roundtrip JSON preserva tudo', () {
      final volta = Simulado.fromJson(simulado.toJson());
      expect(volta.tipo, TipoSimulado.prova);
      expect(volta.cargo, 'Auditor — FGV');
      expect(volta.tempoMinutos, 240);
      expect(volta.resultados.length, 2);
      expect(volta.resultados.last.acertos, 18);
      expect(volta.taxaGeral, simulado.taxaGeral);
    });
  });

  group('filaDeEstudo', () {
    test('ordena por peso desc, depois menor intimidade', () {
      final fila = PlanejamentoService.filaDeEstudo(
        materias: [
          m('leve', peso: 1, minutosAlvo: 600),
          m('pesada', peso: 5, minutosAlvo: 600),
          m('pesada-sabida', peso: 5, intimidade: 5, minutosAlvo: 600),
        ],
        feitoPorMateria: const {},
        minutosSemanais: 600,
      );
      expect(fila.map((f) => f.materia.id).toList(),
          ['pesada', 'pesada-sabida', 'leve']);
    });

    test('ETA acumula: cada matéria espera as anteriores fecharem', () {
      final fila = PlanejamentoService.filaDeEstudo(
        materias: [
          m('a', peso: 3, minutosAlvo: 1200), // 2 semanas
          m('b', peso: 1, minutosAlvo: 600), // +1 semana = 3 acumuladas
        ],
        feitoPorMateria: const {},
        minutosSemanais: 600,
      );
      expect(fila.first.semanasAteConcluir, closeTo(2.0, 1e-9));
      expect(fila.last.semanasAteConcluir, closeTo(3.0, 1e-9));
    });

    test('feito abate do alvo; alvo batido = concluída e não trava a fila',
        () {
      final fila = PlanejamentoService.filaDeEstudo(
        materias: [
          m('feita', peso: 5, minutosAlvo: 600),
          m('meio', peso: 1, minutosAlvo: 600),
        ],
        feitoPorMateria: const {'feita': 900, 'meio': 300},
        minutosSemanais: 600,
      );
      expect(fila.first.concluida, true);
      expect(fila.first.restanteMinutos, 0);
      expect(fila.last.restanteMinutos, 300);
      expect(fila.last.semanasAteConcluir, closeTo(0.5, 1e-9));
    });

    test('sem alvo fica fora; arquivada fica fora; meta 0 = infinito', () {
      final fila = PlanejamentoService.filaDeEstudo(
        materias: [
          m('sem-alvo'),
          m('com-alvo', minutosAlvo: 60),
        ],
        feitoPorMateria: const {},
        minutosSemanais: 0,
      );
      expect(fila.length, 1);
      expect(fila.single.materia.id, 'com-alvo');
      expect(fila.single.semanasAteConcluir, double.infinity);
    });
  });

  group('AulaService — tempo por página e investido', () {
    RegistroHora sessao(int minutos, int paginas) => RegistroHora(
          id: '$minutos-$paginas',
          data: DateTime(2026, 7, 1),
          materiaId: 'm1',
          aulaId: 'a1',
          tipo: TipoEstudo.teoria,
          minutos: minutos,
          paginasLidasManual: paginas,
        );

    test('min/pág = inverso do ritmo ponderado', () {
      final registros = [sessao(60, 20), sessao(30, 10)];
      // 30 páginas em 90 min = 3 min/pág.
      expect(AulaService.minutosPorPagina(registros, 'a1'),
          closeTo(3.0, 1e-9));
      expect(AulaService.minutosInvestidos(registros, 'a1'), 90);
    });

    test('sem sessão com páginas: null, nunca inventa', () {
      expect(AulaService.minutosPorPagina(const [], 'a1'), null);
      expect(AulaService.minutosInvestidos(const [], 'a1'), 0);
    });
  });
}
