import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/insights_service.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora r(DateTime data, int minutos, String materia,
        {int? questoes, int? acertos}) =>
    RegistroHora(
      id: '${data.toIso8601String()}-$minutos-$materia-$questoes',
      data: data,
      materiaId: materia,
      minutos: minutos,
      questoes: questoes,
      acertos: acertos,
    );

Materia m(String id, String nome, {String ambienteId = 'geral'}) => Materia(
      id: id,
      nome: nome,
      ambienteId: ambienteId,
      corSlot: 0,
      criadaEm: DateTime(2026, 1, 1),
    );

void main() {
  // Sexta-feira fixa.
  final hoje = DateTime(2026, 7, 10);

  group('minutosPorDiaSemana', () {
    test('agrega por weekday', () {
      final registros = [
        r(DateTime(2026, 7, 6), 60, 'm1'), // segunda
        r(DateTime(2026, 7, 13), 30, 'm1'), // segunda seguinte
        r(DateTime(2026, 7, 7), 45, 'm1'), // terça
      ];
      final porDia = StatsService.minutosPorDiaSemana(registros);
      expect(porDia[DateTime.monday], 90);
      expect(porDia[DateTime.tuesday], 45);
      expect(porDia[DateTime.sunday], null);
    });
  });

  group('maisEstudada / melhorDiaSemana', () {
    test('vazio devolve null', () {
      expect(InsightsService.maisEstudada([]), null);
      expect(InsightsService.melhorDiaSemana([]), null);
    });

    test('aponta topo correto', () {
      final registros = [
        r(DateTime(2026, 7, 6), 60, 'm1'),
        r(DateTime(2026, 7, 7), 90, 'm2'),
        r(DateTime(2026, 7, 8), 40, 'm1'),
      ];
      final top = InsightsService.maisEstudada(registros)!;
      expect(top.materiaId, 'm1');
      expect(top.minutos, 100);
      final dia = InsightsService.melhorDiaSemana(registros)!;
      expect(dia.diaSemana, DateTime.tuesday);
      expect(dia.minutos, 90);
    });
  });

  group('rankingAcertos', () {
    test('exige amostra mínima e ordena por taxa', () {
      final registros = [
        // m1: 20 questões, 18 acertos (90%).
        r(DateTime(2026, 7, 6), 60, 'm1', questoes: 20, acertos: 18),
        // m2: 15 questões, 9 acertos (60%).
        r(DateTime(2026, 7, 7), 60, 'm2', questoes: 15, acertos: 9),
        // m3: só 2 questões — fora do ranking (ruído).
        r(DateTime(2026, 7, 8), 60, 'm3', questoes: 2, acertos: 2),
      ];
      final ranking = InsightsService.rankingAcertos(registros);
      expect(ranking.length, 2);
      expect(ranking.first.materiaId, 'm1');
      expect(ranking.first.taxa, closeTo(0.9, 1e-9));
      expect(ranking.last.materiaId, 'm2');
    });
  });

  group('minutosPorAmbiente', () {
    test('agrega via matéria e ignora matéria apagada', () {
      final materias = [
        m('m1', 'AFO', ambienteId: 'sefaz'),
        m('m2', 'Python', ambienteId: 'curso'),
      ];
      final registros = [
        r(DateTime(2026, 7, 6), 60, 'm1'),
        r(DateTime(2026, 7, 7), 30, 'm1'),
        r(DateTime(2026, 7, 7), 45, 'm2'),
        r(DateTime(2026, 7, 8), 99, 'apagada'),
      ];
      final porAmbiente =
          InsightsService.minutosPorAmbiente(registros, materias);
      expect(porAmbiente, {'sefaz': 90, 'curso': 45});
    });

    test('respeita janela de datas', () {
      final materias = [m('m1', 'AFO', ambienteId: 'sefaz')];
      final registros = [
        r(DateTime(2026, 7, 1), 60, 'm1'),
        r(DateTime(2026, 7, 8), 30, 'm1'),
      ];
      final porAmbiente = InsightsService.minutosPorAmbiente(
          registros, materias,
          de: DateTime(2026, 7, 6), ate: DateTime(2026, 7, 12));
      expect(porAmbiente, {'sefaz': 30});
    });
  });

  group('melhorarHoje', () {
    test('revisões atrasadas viram primeira ação', () {
      final revisoes = [
        Revisao(
          id: 'r1',
          materiaId: 'm1',
          titulo: 'Rev',
          dataAgendada: DateTime(2026, 7, 1),
          intervaloDias: 7,
        ),
      ];
      final acoes = InsightsService.melhorarHoje(
        registros: [r(hoje, 30, 'm1')],
        materias: [m('m1', 'AFO')],
        revisoes: revisoes,
        hoje: hoje,
      );
      expect(acoes.first.tipo, TipoInsight.revisao);
      expect(acoes.first.mensagem, contains('1 revisão atrasada'));
    });

    test('pior taxa <75% com amostra vira recomendação com matéria', () {
      final registros = [
        r(DateTime(2026, 7, 6), 60, 'm1', questoes: 20, acertos: 10),
        r(hoje, 30, 'm1'),
      ];
      final acoes = InsightsService.melhorarHoje(
        registros: registros,
        materias: [m('m1', 'Direito Constitucional')],
        revisoes: const [],
        hoje: hoje,
      );
      final desempenho =
          acoes.where((a) => a.tipo == TipoInsight.desempenho).toList();
      expect(desempenho, hasLength(1));
      expect(desempenho.first.mensagem,
          contains('Direito Constitucional'));
      expect(desempenho.first.mensagem, contains('50%'));
      expect(desempenho.first.materiaId, 'm1');
    });

    test('streak em risco quando hoje ainda sem estudo', () {
      final registros = [
        r(DateTime(2026, 7, 8), 60, 'm1'),
        r(DateTime(2026, 7, 9), 60, 'm1'),
      ];
      final acoes = InsightsService.melhorarHoje(
        registros: registros,
        materias: [m('m1', 'AFO')],
        revisoes: const [],
        hoje: hoje,
      );
      expect(acoes.any((a) => a.tipo == TipoInsight.streak), true);
    });

    test('sem pendências devolve insight positivo (nunca vazio)', () {
      final acoes = InsightsService.melhorarHoje(
        registros: [r(hoje, 30, 'm1')],
        materias: [m('m1', 'AFO')],
        revisoes: const [],
        hoje: hoje,
      );
      expect(acoes, hasLength(1));
      expect(acoes.single.tipo, TipoInsight.positivo);
    });
  });
}
