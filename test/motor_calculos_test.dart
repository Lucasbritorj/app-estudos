import 'package:app_estudos/data/models/leitura.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/leitura_service.dart';
import 'package:app_estudos/domain/mapa_estudos_service.dart';
import 'package:app_estudos/domain/planejamento_service.dart';
import 'package:app_estudos/domain/revisao_service.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora reg({
  required String materia,
  String? topico,
  int minutos = 60,
  int? questoes,
  int? acertos,
  int? pagInicial,
  int? pagFinal,
}) =>
    RegistroHora(
      id: '$materia-$topico-$minutos-$questoes-$pagInicial',
      data: DateTime(2026, 7, 9),
      materiaId: materia,
      topicoId: topico,
      minutos: minutos,
      questoes: questoes,
      acertos: acertos,
      paginaInicial: pagInicial,
      paginaFinal: pagFinal,
    );

Materia materia(String id, {int peso = 1, int intimidade = 3}) => Materia(
      id: id,
      nome: id,
      corSlot: 0,
      peso: peso,
      intimidade: intimidade,
      criadaEm: DateTime(2026, 1, 1),
    );

void main() {
  group('desempenhoPorTopico', () {
    test('agrega por tópico; registros sem tópico ficam fora', () {
      final registros = [
        reg(materia: 'm1', topico: 't1', questoes: 10, acertos: 6),
        reg(materia: 'm1', topico: 't1', questoes: 10, acertos: 8),
        reg(materia: 'm1', questoes: 10, acertos: 10), // sem tópico
      ];
      final d = StatsService.desempenhoPorTopico(registros);
      expect(d.keys.toList(), ['t1']);
      expect(d['t1'], (questoes: 20, acertos: 14));
    });
  });

  group('ritmo e projeção de leitura por matéria', () {
    final registros = [
      // 30 páginas em 60min = 30 pág/h na m1.
      reg(materia: 'm1', minutos: 60, pagInicial: 1, pagFinal: 30),
      // Ritmo de outra matéria não contamina.
      reg(materia: 'm2', minutos: 60, pagInicial: 1, pagFinal: 5),
    ];

    test('paginasPorHoraGeral filtrado por matéria', () {
      expect(StatsService.paginasPorHoraGeral(registros, materiaId: 'm1'),
          30.0);
      expect(StatsService.paginasPorHoraGeral(registros, materiaId: 'm2'),
          5.0);
    });

    test('páginas restantes e projeção de término', () {
      final leituras = [
        Leitura(
          id: 'l1',
          titulo: 'PDF AFO',
          materiaId: 'm1',
          paginaInicio: 1,
          paginaFim: 100,
          partes: 4,
          partesConcluidas: const [true, false, false, false], // 25 feitas
        ),
      ];
      expect(LeituraService.paginasRestantesDaMateria(leituras, 'm1'), 75);
      expect(LeituraService.progressoDaMateria(leituras, 'm1'), 0.25);
      // 75 páginas a 30 pág/h = 150 minutos.
      expect(LeituraService.minutosParaTerminar(75, 30.0), 150);
    });

    test('sem ritmo medido: projeção null, nunca inventada', () {
      expect(LeituraService.minutosParaTerminar(75, null), isNull);
      expect(LeituraService.progressoDaMateria(const [], 'm1'), isNull);
    });
  });

  group('diagnóstico intimidade × acerto', () {
    test('intimidade alta + acerto baixo = falso domínio', () {
      expect(PlanejamentoService.diagnostico(5, 0.6),
          DiagnosticoMateria.falsoDominio);
      expect(PlanejamentoService.diagnostico(4, 0.74),
          DiagnosticoMateria.falsoDominio);
    });

    test('intimidade 1 = teoria prioritária, mesmo sem questões', () {
      expect(PlanejamentoService.diagnostico(1, null),
          DiagnosticoMateria.teoriaPrioritaria);
      expect(PlanejamentoService.diagnostico(1, 0.9),
          DiagnosticoMateria.teoriaPrioritaria);
    });

    test('sem questões registradas nunca vira falso domínio', () {
      expect(PlanejamentoService.diagnostico(5, null),
          DiagnosticoMateria.regular);
    });

    test('intimidade alta + acerto alto = dominada', () {
      expect(PlanejamentoService.diagnostico(4, 0.9),
          DiagnosticoMateria.dominada);
    });

    test('ciclo ajustado dá mais carga ao falso domínio', () {
      final materias = [
        materia('falsa', peso: 1, intimidade: 5),
        materia('normal', peso: 1, intimidade: 3),
      ];
      final ciclo = PlanejamentoService.distribuirAjustado(
          600, materias, {'falsa': 0.5, 'normal': 0.8});
      // Pesos efetivos 1.5 vs 1.0: 360 vs 240.
      expect(ciclo['falsa'], 360);
      expect(ciclo['normal'], 240);
      expect(ciclo.values.fold(0, (a, b) => a + b), 600);
    });
  });

  group('reagendarPorEstudo', () {
    final pendente = Revisao(
      id: 'r1',
      materiaId: 'm1',
      topicoId: 't1',
      titulo: 'Crase (7d)',
      dataAgendada: DateTime(2026, 7, 10),
      intervaloDias: 7,
    );

    test('pendente do tópico reancora em último estudo + intervalo', () {
      final alteradas = RevisaoService.reagendarPorEstudo(
          [pendente], 't1', DateTime(2026, 7, 9, 22));
      expect(alteradas, hasLength(1));
      expect(alteradas.first.dataAgendada, DateTime(2026, 7, 16));
    });

    test('feita, de outro tópico ou manual (intervalo 0) não muda', () {
      final revisoes = [
        pendente.copyWith(feita: true),
        Revisao(
          id: 'r2',
          materiaId: 'm1',
          topicoId: 'outro',
          titulo: 'x',
          dataAgendada: DateTime(2026, 7, 10),
          intervaloDias: 7,
        ),
        Revisao(
          id: 'r3',
          materiaId: 'm1',
          topicoId: 't1',
          titulo: 'manual',
          dataAgendada: DateTime(2026, 7, 10),
          intervaloDias: 0,
        ),
      ];
      expect(
          RevisaoService.reagendarPorEstudo(
              revisoes, 't1', DateTime(2026, 7, 9)),
          isEmpty);
    });

    test('data já correta não entra na lista de alteradas', () {
      final ancorada = pendente.copyWith(
          dataAgendada: DateTime(2026, 7, 16));
      expect(
          RevisaoService.reagendarPorEstudo(
              [ancorada], 't1', DateTime(2026, 7, 9)),
          isEmpty);
    });
  });

  group('MapaEstudosService', () {
    const t = Topico(id: 't1', materiaId: 'm1', nome: 'Crase');

    test('sem registro = não iniciado; com registro = em estudo', () {
      expect(MapaEstudosService.statusDe(t, const []),
          StatusTopico.naoIniciado);
      expect(
          MapaEstudosService.statusDe(t, [reg(materia: 'm1', topico: 't1')]),
          StatusTopico.emEstudo);
    });

    test('concluído vence, e taxa vem das questões do tópico', () {
      final concluido = t.copyWith(concluido: true);
      final registros = [
        reg(materia: 'm1', topico: 't1', questoes: 10, acertos: 9),
      ];
      expect(MapaEstudosService.statusDe(concluido, registros),
          StatusTopico.concluido);
      expect(MapaEstudosService.taxaDoTopico(registros, 't1'), 0.9);
      expect(MapaEstudosService.minutosDoTopico(registros, 't1'), 60);
    });

    test('sem questões: taxa null (cor neutra, nunca inventada)', () {
      expect(
          MapaEstudosService.taxaDoTopico(
              [reg(materia: 'm1', topico: 't1')], 't1'),
          isNull);
    });
  });
}
