import 'package:app_estudos/data/models/revisao.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hoje = DateTime(2026, 7, 9);

  Revisao revisao(DateTime agendada, {bool feita = false}) => Revisao(
        id: 'r1',
        materiaId: 'm1',
        titulo: 'Revisão AFO',
        dataAgendada: agendada,
        intervaloDias: 7,
        feita: feita,
      );

  test('agendada para hoje = a fazer', () {
    expect(revisao(DateTime(2026, 7, 9)).statusEm(hoje), RevisaoStatus.aFazer);
  });

  test('agendada para o futuro = a fazer', () {
    expect(
        revisao(DateTime(2026, 7, 16)).statusEm(hoje), RevisaoStatus.aFazer);
  });

  test('data passada e não feita = atrasada', () {
    expect(
        revisao(DateTime(2026, 7, 8)).statusEm(hoje), RevisaoStatus.atrasada);
  });

  test('feita nunca fica atrasada', () {
    expect(revisao(DateTime(2026, 7, 1), feita: true).statusEm(hoje),
        RevisaoStatus.feita);
  });

  test('json roundtrip', () {
    final original = revisao(DateTime(2026, 7, 16));
    final copia = Revisao.fromJson(original.toJson());
    expect(copia.id, original.id);
    expect(copia.dataAgendada, original.dataAgendada);
    expect(copia.intervaloDias, 7);
    expect(copia.feita, false);
  });
}
