import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/retencao_service.dart';
import 'package:app_estudos/domain/revisao_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora recall(String materia, int questoes, int acertos) => RegistroHora(
      id: '$materia-$questoes-$acertos',
      data: DateTime(2026, 7, 1),
      materiaId: materia,
      tipo: TipoEstudo.pratica,
      tarefa: 'Revisão: $materia — assunto',
      minutos: 20,
      questoes: questoes,
      acertos: acertos,
    );

RegistroHora praticaComum(String materia, int questoes, int acertos) =>
    RegistroHora(
      id: '$materia-comum-$questoes',
      data: DateTime(2026, 7, 1),
      materiaId: materia,
      tipo: TipoEstudo.pratica,
      tarefa: 'Exercícios',
      minutos: 30,
      questoes: questoes,
      acertos: acertos,
    );

Revisao pendente(String id, DateTime quando, {bool feita = false}) => Revisao(
      id: id,
      materiaId: 'm1',
      titulo: 'rev $id',
      dataAgendada: quando,
      intervaloDias: 7,
      feita: feita,
    );

void main() {
  group('RetencaoService (true retention)', () {
    test('só conta recall de revisão, ignora prática comum', () {
      final registros = [
        recall('m1', 10, 9), // 90% no recall
        praticaComum('m1', 10, 2), // 20%, NÃO entra na retenção
      ];
      expect(RetencaoService.geral(registros), closeTo(0.9, 0.001));
      expect(RetencaoService.porMateria(registros)['m1']!.taxa,
          closeTo(0.9, 0.001));
    });

    test('sem recall registrado: geral null, mapa vazio', () {
      final registros = [praticaComum('m1', 10, 8)];
      expect(RetencaoService.geral(registros), isNull);
      expect(RetencaoService.porMateria(registros), isEmpty);
    });

    test('agrega por matéria e no geral', () {
      final registros = [
        recall('m1', 10, 8),
        recall('m1', 10, 10),
        recall('m2', 10, 5),
      ];
      final porMat = RetencaoService.porMateria(registros);
      expect(porMat['m1']!.taxa, closeTo(0.9, 0.001)); // 18/20
      expect(porMat['m2']!.taxa, closeTo(0.5, 0.001));
      expect(RetencaoService.geral(registros), closeTo(23 / 30, 0.001));
    });
  });

  group('RevisaoService.forecastCarga', () {
    final hoje = DateTime(2026, 7, 1);

    test('conta pendentes por dia; feitas não entram', () {
      final revisoes = [
        pendente('a', DateTime(2026, 7, 1)), // hoje
        pendente('b', DateTime(2026, 7, 3)),
        pendente('c', DateTime(2026, 7, 3)),
        pendente('d', DateTime(2026, 7, 5), feita: true), // não conta
      ];
      final f = RevisaoService.forecastCarga(revisoes, hoje, dias: 7);
      expect(f.length, 7);
      expect(f[0].quantidade, 1); // 1/7
      expect(f[2].quantidade, 2); // 3/7
      expect(f[4].quantidade, 0); // 5/7 era a feita
    });

    test('atrasadas caem no dia 0 (a fila que já venceu)', () {
      final revisoes = [
        pendente('velha', DateTime(2026, 6, 20)), // atrasada
        pendente('hoje', DateTime(2026, 7, 1)),
      ];
      final f = RevisaoService.forecastCarga(revisoes, hoje, dias: 7);
      expect(f[0].quantidade, 2); // atrasada + hoje
    });

    test('além da janela não entra', () {
      final revisoes = [pendente('longe', DateTime(2026, 8, 1))];
      final f = RevisaoService.forecastCarga(revisoes, hoje, dias: 7);
      expect(f.every((d) => d.quantidade == 0), isTrue);
    });
  });
}
