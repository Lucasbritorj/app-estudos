import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:flutter_test/flutter_test.dart';

/// Integridade dos modelos na borda do backup (A-004 do ledger): o dialog
/// de matéria impõe peso >= 1 e a prontidão/planejamento fazem média
/// ponderada por peso — um backup adulterado com peso <= 0 envenena a média
/// silenciosamente (CWE-20). Páginas negativas ou intervalo invertido
/// geravam contagem de páginas negativa contaminando ritmo/stats.
void main() {
  group('Materia.fromJson — invariantes contra backup adulterado', () {
    Materia deJson(int peso) => Materia.fromJson({
          'id': 'm1',
          'nome': 'Português',
          'corSlot': 0,
          'peso': peso,
          'criadaEm': '2026-01-01T00:00:00.000',
        });

    test('peso negativo é clampado a 1 (invariante do domínio)', () {
      expect(deJson(-3).peso, 1);
    });

    test('peso zero é clampado a 1', () {
      expect(deJson(0).peso, 1);
    });

    test('peso válido preservado', () {
      expect(deJson(5).peso, 5);
    });
  });

  group('Topico.fromJson — invariantes contra backup adulterado', () {
    test('peso < 1 é clampado a 1', () {
      final t = Topico.fromJson({
        'id': 't1',
        'materiaId': 'm1',
        'nome': 'Crase',
        'peso': -1,
      });
      expect(t.peso, 1);
    });
  });

  group('RegistroHora — páginas hostis não contaminam stats', () {
    RegistroHora registro({int? inicial, int? fim}) => RegistroHora(
          id: 'r1',
          data: DateTime(2026, 7, 1),
          materiaId: 'm1',
          minutos: 60,
          paginaInicial: inicial,
          paginaFinal: fim,
        );

    test('intervalo invertido não produz contagem negativa', () {
      expect(registro(inicial: 10, fim: 2).paginasLidas, isNull);
    });

    test('página negativa é descartada (vira null)', () {
      expect(registro(inicial: -10, fim: -5).paginasLidas, isNull);
    });

    test('intervalo válido segue contagem inclusiva', () {
      expect(registro(inicial: 10, fim: 20).paginasLidas, 11);
    });
  });
}
