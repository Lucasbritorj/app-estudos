import 'package:app_estudos/data/models/leitura.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/dominio_service.dart';
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

  group('diagnóstico intimidade × domínio medido (Elo)', () {
    MedicaoDominio medicao(double dominio, {bool confiavel = true}) =>
        (dominio: dominio, questoes: confiavel ? 20 : 4, confiavel: confiavel);

    test('intimidade alta + domínio medido baixo = falso domínio', () {
      expect(PlanejamentoService.diagnostico(5, medicao(0.6)),
          DiagnosticoMateria.falsoDominio);
      expect(PlanejamentoService.diagnostico(4, medicao(0.74)),
          DiagnosticoMateria.falsoDominio);
    });

    test('intimidade 1 = teoria prioritária, mesmo com medição', () {
      expect(PlanejamentoService.diagnostico(1, null),
          DiagnosticoMateria.teoriaPrioritaria);
      expect(PlanejamentoService.diagnostico(1, medicao(0.9)),
          DiagnosticoMateria.teoriaPrioritaria);
    });

    test('sem medição confiável nunca vira falso domínio nem dominada', () {
      expect(PlanejamentoService.diagnostico(5, null),
          DiagnosticoMateria.regular);
      // Amostra pequena (< 10 questões) = palpite, não veredito.
      expect(
          PlanejamentoService.diagnostico(
              5, medicao(0.5, confiavel: false)),
          DiagnosticoMateria.regular);
      expect(
          PlanejamentoService.diagnostico(
              4, medicao(0.95, confiavel: false)),
          DiagnosticoMateria.regular);
    });

    test('intimidade alta + domínio medido alto = dominada', () {
      expect(PlanejamentoService.diagnostico(4, medicao(0.9)),
          DiagnosticoMateria.dominada);
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

  group('metricasPorTopico (uma passada por matéria)', () {
    const base = Topico(id: 'base', materiaId: 'm1', nome: 'Base');
    final avancado = const Topico(
        id: 'avancado',
        materiaId: 'm1',
        nome: 'Avançado',
        prerequisitos: ['base']);

    test('status, minutos, taxa e bloqueio batem com os cálculos por tópico',
        () {
      final registros = [
        reg(materia: 'm1', topico: 'base', minutos: 30, questoes: 10, acertos: 9),
        reg(materia: 'm1', topico: 'base', minutos: 30),
      ];
      final metricas =
          MapaEstudosService.metricasPorTopico([base, avancado], registros);

      expect(metricas['base']!.status, StatusTopico.emEstudo);
      expect(metricas['base']!.minutos, 60);
      expect(metricas['base']!.taxa, 0.9);
      expect(metricas['base']!.bloqueadoPor, isEmpty);
      // base não é confiável (10 questões, mas domínio < 0.6 partindo do
      // neutro com 90%): avançado segue bloqueado.
      expect(metricas['avancado']!.status, StatusTopico.naoIniciado);
      expect(
          metricas['avancado']!.bloqueadoPor.map((t) => t.id), ['base']);
    });

    test('base concluída libera o dependente', () {
      final metricas = MapaEstudosService.metricasPorTopico(
          [base.copyWith(concluido: true), avancado], const []);
      expect(metricas['base']!.status, StatusTopico.concluido);
      expect(metricas['avancado']!.bloqueadoPor, isEmpty);
    });

    test('registro de tópico de outra matéria não contamina', () {
      final metricas = MapaEstudosService.metricasPorTopico(
          [base], [reg(materia: 'm1', topico: 'fantasma', minutos: 99)]);
      expect(metricas['base']!.minutos, 0);
      expect(metricas['base']!.status, StatusTopico.naoIniciado);
    });
  });
}
