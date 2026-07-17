import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Segurança do export CSV (A-002 do ledger): célula iniciada em = + - @
/// (ou tab/CR) é interpretada como fórmula pelo Excel — dado vindo de fora
/// (xlsx/edital/backup de terceiro) executaria no Excel de quem abre o
/// export (CSV/formula injection, CWE-1236). Neutralização: prefixo '
/// força a célula a texto sem perder conteúdo.
void main() {
  final materias = {
    'm1': Materia(
        id: 'm1',
        nome: '=HYPERLINK("http://exemplo";"clique")',
        corSlot: 0,
        criadaEm: DateTime(2026, 1, 1)),
  };
  final topicos = {
    't1': Topico(id: 't1', materiaId: 'm1', nome: '@indireto'),
  };
  final registros = [
    RegistroHora(
      id: 'r1',
      data: DateTime(2026, 7, 1),
      materiaId: 'm1',
      topicoId: 't1',
      tarefa: '+SOMA(1;2)',
      minutos: 30,
      comentario: '=1+1',
    ),
    RegistroHora(
      id: 'r2',
      data: DateTime(2026, 7, 2),
      materiaId: 'm1',
      tarefa: '-nota solta',
      minutos: 45,
      comentario: 'comentário normal',
    ),
  ];

  // Nenhuma célula (início de linha ou após separador) pode começar com
  // gatilho de fórmula; célula entre aspas começa com " e já passa.
  final gatilhoNaCelula = RegExp(r'(^|;|,)[=+@-]', multiLine: true);

  group('ExportService — neutralização de fórmula (CWE-1236)', () {
    test('csvRegistros neutraliza células iniciadas em gatilho de fórmula',
        () {
      final csv =
          ExportService.csvRegistros(registros, materias, topicos);
      expect(csv, isNot(matches(gatilhoNaCelula)));
      // Conteúdo preservado, apenas prefixado com apóstrofo.
      expect(csv, contains("'=1+1"));
      expect(csv, contains("'+SOMA(1;2)"));
      expect(csv, contains("'@indireto"));
      expect(csv, contains("'-nota solta"));
      // Texto inofensivo permanece intacto.
      expect(csv, contains(';comentário normal'));
    });

    test('csvBi neutraliza células iniciadas em gatilho de fórmula', () {
      final csv = ExportService.csvBi(registros, materias, topicos,
          metaSemanalMinutos: 600);
      expect(csv, isNot(matches(gatilhoNaCelula)));
      expect(csv, contains("'=HYPERLINK"));
    });
  });
}
