import 'dart:convert';

import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final materias = {
    'm1': Materia(
        id: 'm1', nome: 'AFO', corSlot: 0, criadaEm: DateTime(2026)),
  };

  test('CSV: cabeçalho, data BR, decimal com vírgula, ordem cronológica', () {
    final registros = [
      RegistroHora(
        id: 'b',
        data: DateTime(2026, 7, 9, 10),
        materiaId: 'm1',
        tarefa: 'Aula 2',
        minutos: 120,
        paginaInicial: 1,
        paginaFinal: 22,
      ),
      RegistroHora(
        id: 'a',
        data: DateTime(2026, 7, 8, 10),
        materiaId: 'm1',
        tarefa: 'Aula 1',
        minutos: 60,
      ),
    ];
    final linhas = ExportService.csvRegistros(registros, materias, {})
        .trim()
        .split('\r\n');
    expect(linhas.first.startsWith('Data;Matéria;Tópico;Tarefa'), true);
    // Ordenado por data: dia 8 vem antes do dia 9.
    expect(linhas[1].startsWith('08/07/2026;AFO;;Aula 1;60'), true);
    expect(linhas[2], contains('11,0')); // 22 págs em 2h = 11,0 pág/h
  });

  test('CSV: campo com ; ou aspas é escapado', () {
    final registros = [
      RegistroHora(
        id: 'a',
        data: DateTime(2026, 7, 9),
        materiaId: 'm1',
        tarefa: 'Lei 4.320; art. "1º"',
        minutos: 30,
      ),
    ];
    final csv = ExportService.csvRegistros(registros, materias, {});
    expect(csv, contains('"Lei 4.320; art. ""1º"""'));
  });

  test('JSON completo: decodifica e preserva coleções', () {
    final json = ExportService.jsonCompleto(
      materias: materias.values.toList(),
      topicos: [],
      aulas: [],
      registros: [
        RegistroHora(
            id: 'a',
            data: DateTime(2026, 7, 9),
            materiaId: 'm1',
            minutos: 30),
      ],
      revisoes: [],
      leituras: [],
      planejamento: {1: 120},
    );
    final decodificado = jsonDecode(json) as Map<String, dynamic>;
    expect(decodificado['versao'], 1);
    expect((decodificado['materias'] as List).length, 1);
    expect((decodificado['registros'] as List).length, 1);
    expect(decodificado['planejamento'], {'1': 120});
  });

  group('csvBi', () {
    test('flat BI: ISO, decimal com ponto, união horas+questões+meta', () {
      final registros = [
        RegistroHora(
          id: 'a',
          data: DateTime(2026, 7, 9, 22),
          materiaId: 'm1',
          tarefa: 'Aula, com vírgula',
          minutos: 90,
          paginaInicial: 1,
          paginaFinal: 30,
          questoes: 10,
          acertos: 8,
        ),
      ];
      final csv = ExportService.csvBi(registros, materias, {},
          metaSemanalMinutos: 1800);
      final linhas = csv.trim().split('\r\n');

      expect(linhas.first,
          'data,semana_inicio,materia,peso_materia,topico,tarefa,minutos,horas,'
          'pagina_inicial,pagina_final,paginas_lidas,paginas_por_hora,'
          'questoes,acertos,taxa_acerto,meta_semanal_minutos,comentario');
      final dados = linhas[1];
      expect(dados, startsWith('2026-07-09,2026-07-06,AFO,1,')); // ISO + segunda
      expect(dados, contains('"Aula, com vírgula"')); // vírgula escapada
      expect(dados, contains(',90,1.5000,')); // horas decimal com PONTO
      expect(dados, contains(',10,8,0.8000,1800,')); // questões + meta
      expect(csv, isNot(contains(';'))); // nada do formato pt-BR aqui
    });

    test('campos ausentes ficam vazios, nunca inventados', () {
      final csv = ExportService.csvBi(
        [
          RegistroHora(
              id: 'a',
              data: DateTime(2026, 7, 9),
              materiaId: 'm1',
              minutos: 60),
        ],
        materias,
        {},
        metaSemanalMinutos: 1800,
      );
      final dados = csv.trim().split('\r\n')[1];
      // pagina_inicial..taxa_acerto vazios (8 vírgulas seguidas).
      expect(dados, contains(',60,1.0000,,,,,,,,1800,'));
    });
  });
}
