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

  /// D-03 — matéria excluída na dimensão.
  ///
  /// A cascata preserva os registros de horas (log histórico) mas tira a
  /// matéria do `state`, então o modelo estrela cria uma linha sintética para
  /// não quebrar o relacionamento (UAT-E4 já cobre isso). O que faltava: a
  /// linha saía SEMPRE com o mesmo rótulo, `(matéria excluída)`, e sem
  /// ambiente nem peso. Duas matérias excluídas viravam ids distintos com nome
  /// idêntico — num gráfico agrupado por nome, uma barra só. O tombstone tinha
  /// nome, peso, ambiente e intimidade intactos o tempo todo
  /// (`MateriasRepositorio.historicas()`).
  group('D-03 — dimensão de matéria excluída', () {
    Materia materiaDe(
      String id,
      String nome, {
      String ambienteId = 'amb1',
      int peso = 3,
      int intimidade = 3,
    }) => Materia(
      id: id,
      nome: nome,
      ambienteId: ambienteId,
      corSlot: 0,
      peso: peso,
      intimidade: intimidade,
      criadaEm: DateTime(2026, 1, 1),
    );

    // Datas distintas de propósito: `List.sort` não promete estabilidade, e a
    // ordem das linhas sintéticas segue a ordem do fato.
    RegistroHora registroDe(String id, String materiaId, int dia) =>
        RegistroHora(
          id: id,
          data: DateTime(2026, 7, dia),
          materiaId: materiaId,
          minutos: 60,
        );

    final viva = materiaDe('m-viva', 'AFO');
    final excluida = materiaDe(
      'm-morta',
      'Direito Constitucional',
      peso: 5,
      intimidade: 4,
    ).comExclusao(DateTime(2026, 8, 1));
    // Tombstone cujo ambiente também sumiu — a UI barra excluir ambiente com
    // matéria viva, mas um backup importado traz a referência pendurada.
    final semAmbiente = materiaDe(
      'm-sem-amb',
      'Português',
      ambienteId: 'amb-sumido',
    ).comExclusao(DateTime(2026, 8, 1));

    final registrosD03 = [
      registroDe('r1', 'm-viva', 10),
      registroDe('r2', 'm-morta', 11),
      registroDe('r3', 'm-sem-amb', 12),
      // Sem tombstone: box já não tem essa matéria de jeito nenhum.
      registroDe('r4', 'm-fantasma', 13),
    ];
    final historicas = {
      viva.id: viva,
      excluida.id: excluida,
      semAmbiente.id: semAmbiente,
    };

    Map<String, String> comHistorico() => ExportService.modeloEstrela(
      registros: registrosD03,
      materias: [viva],
      topicos: const [],
      ambientes: [ambiente],
      materiasHistoricas: historicas,
    );

    List<String> coluna(String csv, int indice) => [
      for (final l in csv.trim().split('\r\n').skip(1)) l.split(',')[indice],
    ];

    test('linha sintética usa nome, peso e ambiente REAIS do tombstone', () {
      final linhas = comHistorico()['dim_materia.csv']!.trim().split('\r\n');
      expect(linhas[1], 'm-viva,AFO,amb1,3,3,,,false,false');
      expect(linhas[2], 'm-morta,Direito Constitucional,amb1,5,4,,,false,true');
      expect(linhas[3], 'm-sem-amb,Português,amb-sumido,3,3,,,false,true');
    });

    test('sem tombstone, o rótulo genérico continua como último recurso', () {
      final linhas = comHistorico()['dim_materia.csv']!.trim().split('\r\n');
      expect(linhas[4], 'm-fantasma,(matéria excluída),,,,,,true,true');
    });

    test('nomes deixam de colidir: 1 nome por id', () {
      final dim = comHistorico()['dim_materia.csv']!;
      expect(coluna(dim, 1).toSet(), hasLength(coluna(dim, 0).length));
    });

    test('excluida é coluna própria, separada de arquivada', () {
      final dim = comHistorico()['dim_materia.csv']!;
      expect(dim.trim().split('\r\n').first, endsWith(',arquivada,excluida'));
      // O tombstone não estava arquivado — antes a linha sintética cravava
      // `arquivada=true` e misturava as duas leituras no filtro do BI.
      expect(coluna(dim, 7), ['false', 'false', 'false', 'true']);
      expect(coluna(dim, 8), ['false', 'true', 'true', 'true']);
    });

    test('todo ambiente_id de dim_materia tem linha em dim_ambiente', () {
      final tabelas = comHistorico();
      final referenciados = coluna(tabelas['dim_materia.csv']!, 2).toSet()
        ..removeWhere((id) => id.isEmpty);
      final naDimensao = coluna(tabelas['dim_ambiente.csv']!, 0).toSet();
      expect(referenciados.difference(naDimensao), isEmpty);
      expect(
        tabelas['dim_ambiente.csv'],
        contains('amb-sumido,${ExportService.nomeAmbienteExcluido},'),
      );
    });

    test('ambiente_id vazio NÃO vira linha de dimensão', () {
      // Só a sintética sem tombstone tem ambiente vazio: ali o ambiente é
      // desconhecido de fato, e chave vazia na dimensão seria pior que a
      // ausência.
      final ids = coluna(comHistorico()['dim_ambiente.csv']!, 0);
      expect(ids, isNot(contains('')));
    });

    test('sem materiasHistoricas o modelo segue íntegro, só anônimo', () {
      // Contrato de compatibilidade: o parâmetro é opcional e nenhum call site
      // antigo muda de comportamento além das colunas novas.
      final tabelas = ExportService.modeloEstrela(
        registros: registrosD03,
        materias: [viva],
        topicos: const [],
        ambientes: [ambiente],
      );
      final noFato = coluna(tabelas['fato_registros.csv']!, 2).toSet();
      final naDimensao = coluna(tabelas['dim_materia.csv']!, 0).toSet();
      expect(noFato.difference(naDimensao), isEmpty);

      final nomes = coluna(tabelas['dim_materia.csv']!, 1);
      final genericos = nomes.where(
        (n) => n == ExportService.nomeMateriaExcluida,
      );
      expect(genericos, hasLength(3));
    });
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
