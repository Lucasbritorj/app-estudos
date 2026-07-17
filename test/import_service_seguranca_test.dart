import 'dart:convert';

import 'package:app_estudos/domain/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Segurança do import de backup (A-003 do ledger): o contrato do parser é
/// "falha com FormatException explícita" — a UI captura só FormatException
/// (exportar_screen). O campo `planejamento` fazia `(v as num)` sem
/// validação: valor não numérico lançava TypeError, furava o catch da UI e
/// virava exceção não tratada (CWE-755); valor negativo entrava direto na
/// meta semanal (CWE-20).
void main() {
  String backup(Map<String, Object?> planejamento) => jsonEncode({
        'versao': 1,
        'planejamento': planejamento,
      });

  group('ImportService.parseBackup — campo planejamento hostil', () {
    test('valor não numérico lança FormatException (nunca TypeError)', () {
      expect(() => ImportService.parseBackup(backup({'1': 'sessenta'})),
          throwsA(isA<FormatException>()));
    });

    test('valor negativo é clampado a zero (invariante de minutos)', () {
      final resultado = ImportService.parseBackup(backup({'3': -50}));
      expect(resultado.planejamento[3], 0);
    });

    test('valor válido continua aceito', () {
      final resultado = ImportService.parseBackup(backup({'2': 90}));
      expect(resultado.planejamento[2], 90);
    });

    test('dia fora de 1..7 continua ignorado', () {
      final resultado = ImportService.parseBackup(backup({'9': 60}));
      expect(resultado.planejamento, isEmpty);
    });
  });
}
