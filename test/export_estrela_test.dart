import 'dart:convert';

import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Export modelo estrela para BI (1b do plano de melhorias): fato no grão
/// sessão + dimensões normalizadas + calendário contínuo, zipados.
void main() {
  final ambiente = Ambiente(
    id: 'amb1',
    nome: 'SEFAZ',
    corSlot: 0,
    criadoEm: DateTime(2026, 1, 1),
    dataProva: DateTime(2026, 12, 6),
  );
  final materia = Materia(
    id: 'm1',
    nome: 'AFO',
    ambienteId: 'amb1',
    corSlot: 0,
    peso: 3,
    criadaEm: DateTime(2026, 1, 1),
  );
  final topico = Topico(id: 't1', materiaId: 'm1', nome: 'Orçamento');
  final registros = [
    RegistroHora(
      id: 'r1',
      data: DateTime(2026, 7, 10),
      materiaId: 'm1',
      topicoId: 't1',
      minutos: 90,
      questoes: 10,
      acertos: 8,
      tipo: TipoEstudo.pratica,
    ),
    RegistroHora(
      id: 'r2',
      data: DateTime(2026, 7, 13),
      materiaId: 'm1',
      minutos: 60,
    ),
  ];

  Map<String, String> estrela() => ExportService.modeloEstrela(
    registros: registros,
    materias: [materia],
    topicos: [topico],
    ambientes: [ambiente],
  );

  test('gera as 5 tabelas com os nomes esperados', () {
    expect(estrela().keys, {
      'fato_registros.csv',
      'dim_materia.csv',
      'dim_topico.csv',
      'dim_ambiente.csv',
      'dim_data.csv',
    });
  });

  test('fato: 1 linha por sessão, só chaves e medidas, erros derivado', () {
    final linhas = estrela()['fato_registros.csv']!.trim().split('\r\n');
    expect(linhas.length, 3); // cabeçalho + 2 sessões
    expect(linhas[1], 'r1,2026-07-10,m1,t1,,pratica,90,1.5000,,10,8,2,0.8000');
    expect(linhas[2], 'r2,2026-07-13,m1,,,teoria,60,1.0000,,,,,');
  });

  test('dim_data cobre do primeiro ao último registro, sem buracos', () {
    final linhas = estrela()['dim_data.csv']!.trim().split('\r\n');
    // 10 a 13 de julho = 4 dias + cabeçalho.
    expect(linhas.length, 5);
    expect(linhas[1], '2026-07-10,2026,7,julho,10,5,sexta,2026-07-06,3,false');
    expect(linhas.last.startsWith('2026-07-13'), isTrue);
    expect(linhas.last.endsWith('false'), isTrue);
  });

  test('dim_ambiente leva a data da prova em ISO', () {
    expect(estrela()['dim_ambiente.csv'], contains('amb1,SEFAZ,2026-12-06'));
  });

  test('nome com vírgula e fórmula é neutralizado como nos demais CSVs', () {
    final tabelas = ExportService.modeloEstrela(
      registros: const [],
      materias: [
        Materia(
          id: 'm2',
          nome: '=1+1, hostil',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        ),
      ],
      topicos: const [],
      ambientes: const [],
    );
    expect(tabelas['dim_materia.csv'], contains('"\'=1+1, hostil"'));
  });

  test('zip empacota as 5 tabelas com conteúdo íntegro', () {
    final tabelas = estrela();
    final zip = ExportService.zipModeloEstrela(tabelas);
    final lido = ZipDecoder().decodeBytes(zip);
    expect(lido.files.map((f) => f.name).toSet(), tabelas.keys.toSet());
    final fato = lido.files.firstWhere((f) => f.name == 'fato_registros.csv');
    expect(
      utf8.decode(fato.content as List<int>),
      tabelas['fato_registros.csv'],
    );
  });
}
