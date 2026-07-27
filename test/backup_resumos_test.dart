import 'dart:convert';

import 'package:app_estudos/data/models/resumo.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:app_estudos/domain/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

// D-01: jsonCompleto não serializava resumos, mas ApagarDadosUseCase.apagarTudo
// apaga o box de resumos. O diálogo de wipe manda exportar backup antes de
// apagar — sem isto, o backup "completo" não continha resumos e restaurar
// depois de um wipe perdia todas as páginas de resumo, em silêncio.
void main() {
  group('backup de resumos (D-01)', () {
    test('jsonCompleto -> parseBackup preserva resumos', () {
      final resumos = [
        Resumo(
          sigla: 'DC',
          nome: 'Direito Constitucional',
          texto: '**controle de constitucionalidade** ==difuso==',
          atualizadoEm: DateTime(2026, 7, 20),
          doCatalogo: true,
        ),
        Resumo(sigla: 'XYZ', nome: 'Matéria custom', texto: 'notas livres'),
      ];
      final json = ExportService.jsonCompleto(
        materias: const [],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
        leituras: const [],
        planejamento: const {},
        resumos: resumos,
      );

      final backup = ImportService.parseBackup(json);
      expect(backup.resumos, hasLength(2));
      expect(backup.resumos.first.sigla, 'DC');
      expect(backup.resumos.first.texto, contains('difuso'));
      expect(backup.resumos.first.doCatalogo, true);
      expect(backup.resumos.first.atualizadoEm, DateTime(2026, 7, 20));
      expect(backup.resumos.last.sigla, 'XYZ');
      expect(backup.resumo, contains('2 resumos'));
    });

    test('backup antigo sem a chave "resumos" parseia sem exceção', () {
      final json = ExportService.jsonCompleto(
        materias: const [],
        topicos: const [],
        aulas: const [],
        registros: const [],
        revisoes: const [],
        leituras: const [],
        planejamento: const {},
      );
      final mapa = jsonDecode(json) as Map<String, dynamic>;
      mapa.remove('resumos'); // simula backup gerado antes do fix D-01
      final backup = ImportService.parseBackup(jsonEncode(mapa));
      expect(backup.resumos, isEmpty);
    });
  });
}
