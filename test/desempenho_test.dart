import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora reg(String materia, {int? questoes, int? acertos}) =>
    RegistroHora(
      id: '$materia-$questoes-$acertos',
      data: DateTime(2026, 7, 9),
      materiaId: materia,
      minutos: 60,
      questoes: questoes,
      acertos: acertos,
    );

void main() {
  test('taxaAcerto da sessão', () {
    expect(reg('m', questoes: 20, acertos: 15).taxaAcerto, 0.75);
    expect(reg('m').taxaAcerto, isNull);
    expect(reg('m', questoes: 0, acertos: 0).taxaAcerto, isNull);
  });

  test('desempenhoPorMateria acumula questões e acertos', () {
    final registros = [
      reg('afo', questoes: 20, acertos: 15),
      reg('afo', questoes: 10, acertos: 9),
      reg('sql', questoes: 30, acertos: 30),
      reg('port'), // sem questões: fora
    ];
    final desempenho = StatsService.desempenhoPorMateria(registros);
    expect(desempenho['afo'], (questoes: 30, acertos: 24));
    expect(desempenho['sql'], (questoes: 30, acertos: 30));
    expect(desempenho.containsKey('port'), false);
  });

  test('taxaAcertoGeral ponderada; null sem questões', () {
    final registros = [
      reg('afo', questoes: 20, acertos: 10),
      reg('sql', questoes: 80, acertos: 70),
    ];
    expect(StatsService.taxaAcertoGeral(registros), 0.8);
    expect(StatsService.taxaAcertoGeral([reg('afo')]), isNull);
  });

  test('json roundtrip com questões/acertos', () {
    final original = reg('afo', questoes: 12, acertos: 8);
    final copia = RegistroHora.fromJson(original.toJson());
    expect(copia.questoes, 12);
    expect(copia.acertos, 8);
    expect(copia.taxaAcerto, 8 / 12);
  });
}
