import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:app_estudos/domain/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('roundtrip export -> import preserva os dados', () {
    final materia = Materia(
        id: 'm1', nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026));
    final registro = RegistroHora(
      id: 'r1',
      data: DateTime(2026, 7, 9),
      materiaId: 'm1',
      minutos: 90,
      questoes: 10,
      acertos: 8,
    );
    final json = ExportService.jsonCompleto(
      materias: [materia],
      topicos: [],
      aulas: [],
      registros: [registro],
      revisoes: [],
      leituras: [],
      planejamento: {1: 120, 5: 60},
    );

    final backup = ImportService.parseBackup(json);
    expect(backup.materias.single.nome, 'AFO');
    expect(backup.registros.single.minutos, 90);
    expect(backup.registros.single.acertos, 8);
    expect(backup.planejamento, {1: 120, 5: 60});
    expect(backup.revisoes, isEmpty);
  });

  test('JSON inválido falha com mensagem explícita', () {
    expect(() => ImportService.parseBackup('não é json'),
        throwsFormatException);
  });

  test('versão desconhecida é recusada', () {
    expect(() => ImportService.parseBackup('{"versao": 99}'),
        throwsFormatException);
  });

  test('lista com item corrompido é recusada (nada de import parcial)', () {
    expect(
        () => ImportService.parseBackup(
            '{"versao": 1, "materias": [{"id": "x"}]}'),
        throwsFormatException);
  });
}
