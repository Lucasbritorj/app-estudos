import 'dart:typed_data';

import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/domain/planilha_import_service.dart';
import 'package:app_estudos/domain/xlsx_reader.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Serial de data do Excel (sistema 1900, epoch 1899-12-30).
int serial(DateTime d) => d.difference(DateTime(1899, 12, 30)).inDays;

/// Monta um .xlsx mínimo em memória com as abas "Registro de Horas" e
/// "Revisões", usando shared strings (com rich text), inline strings,
/// números e uma linha esparsa — os formatos que o Excel real produz.
Uint8List xlsxDeTeste() {
  const ns =
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
  const workbook = '''
<?xml version="1.0" encoding="UTF-8"?>
<workbook $ns xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Registro de Horas" sheetId="1" r:id="rId1"/>
    <sheet name="Revisões" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>''';
  const rels = '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="w" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="w" Target="worksheets/sheet2.xml"/>
</Relationships>''';
  // Índices: 0 Data · 1 Matéria (rich text) · 2 Tópico · 3 Tarefa · 4 Aula ·
  // 5 Página inicial · 6 Página final · 7 Horas · 8 Minutos · 9 Comentário ·
  // 10 Páginas lidas · 11 Páginas/hora · 12 O que revisar · 13 Intervalo ·
  // 14 Status
  const sharedStrings = '''
<?xml version="1.0" encoding="UTF-8"?>
<sst $ns count="15" uniqueCount="15">
  <si><t>Data</t></si>
  <si><r><t>Mat</t></r><r><t>éria</t></r></si>
  <si><t>Tópico</t></si>
  <si><t>Tarefa</t></si>
  <si><t>Aula</t></si>
  <si><t>Página inicial</t></si>
  <si><t>Página final</t></si>
  <si><t>Horas</t></si>
  <si><t>Minutos</t></si>
  <si><t>Comentário</t></si>
  <si><t>Páginas lidas</t></si>
  <si><t>Páginas/hora</t></si>
  <si><t>O que revisar</t></si>
  <si><t>Intervalo</t></si>
  <si><t>Status</t></si>
</sst>''';

  String inline(String ref, String texto) =>
      '<c r="$ref" t="inlineStr"><is><t>$texto</t></is></c>';
  String compartilhada(String ref, int i) =>
      '<c r="$ref" t="s"><v>$i</v></c>';
  String numero(String ref, num v) => '<c r="$ref"><v>$v</v></c>';

  final sheet1 = '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet $ns>
  <sheetData>
    <row r="1">${[
    for (var i = 0; i <= 11; i++)
      compartilhada('${String.fromCharCode(65 + i)}1', i),
  ].join()}</row>
    <row r="2">${numero('A2', serial(DateTime(2026, 7, 9)))}${inline('B2', 'Português')}${inline('C2', 'Crase')}${inline('D2', 'PDF 2')}${numero('F2', 10)}${numero('G2', 20)}${numero('H2', 1)}${numero('I2', 30)}${inline('J2', 'boa sessão')}</row>
    <row r="4">${inline('A4', 'não é data')}${inline('B4', 'Português')}${numero('I4', 60)}</row>
    <row r="5">${numero('A5', serial(DateTime(2026, 7, 8)))}${inline('B5', 'Direito Constitucional')}${numero('I5', 45)}</row>
  </sheetData>
</worksheet>''';

  final sheet2 = '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet $ns>
  <sheetData>
    <row r="1">${compartilhada('A1', 0)}${compartilhada('B1', 1)}${compartilhada('C1', 12)}${compartilhada('D1', 13)}${compartilhada('E1', 14)}</row>
    <row r="2">${numero('A2', serial(DateTime(2026, 7, 16)))}${inline('B2', 'Português')}${inline('C2', 'Crase')}${numero('D2', 7)}${inline('E2', 'Feita')}</row>
    <row r="3">${numero('A3', serial(DateTime(2026, 7, 24)))}${inline('B3', 'Português')}${inline('C3', 'Concordância')}${numero('D3', 15)}${inline('E3', 'A fazer')}</row>
  </sheetData>
</worksheet>''';

  final zip = Archive()
    ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', rels))
    ..addFile(ArchiveFile.string('xl/sharedStrings.xml', sharedStrings))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', sheet1))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet2.xml', sheet2));
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

Materia materiaPortugues() => Materia(
      id: 'm-port',
      nome: 'Português',
      corSlot: 0,
      criadaEm: DateTime(2026, 1, 1),
    );

/// Fixture com o layout da planilha REAL: Visão Geral (rótulo + valor),
/// Registro com "Tempo" mesclado sobre subcolunas Horas/Minutos e aba
/// Sefaz de pesos (Matéria, Número questões, Peso, Mínimo).
Uint8List xlsxPlanilhaReal() {
  const ns =
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
  const workbook = '''
<?xml version="1.0" encoding="UTF-8"?>
<workbook $ns xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Visão Geral" sheetId="1" r:id="rId1"/>
    <sheet name="Registro de horas" sheetId="2" r:id="rId2"/>
    <sheet name="Sefaz" sheetId="3" r:id="rId3"/>
  </sheets>
</workbook>''';
  const rels = '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="w" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="w" Target="worksheets/sheet2.xml"/>
  <Relationship Id="rId3" Type="w" Target="worksheets/sheet3.xml"/>
</Relationships>''';

  String inline(String ref, String texto) =>
      '<c r="$ref" t="inlineStr"><is><t>$texto</t></is></c>';
  String numero(String ref, num v) => '<c r="$ref"><v>$v</v></c>';

  final visaoGeral = '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet $ns>
  <sheetData>
    <row r="1">${inline('A1', 'Horas planejadas para a semana (h)')}${numero('B1', 30)}</row>
    <row r="2">${inline('A2', 'Horas feitas na semana (h)')}${numero('B2', 12.5)}</row>
    <row r="3">${inline('A3', 'Horas restantes na semana (h)')}${numero('B3', 17.5)}</row>
    <row r="4">${inline('A4', 'Horas acumuladas na matéria (h)')}${numero('B4', 120)}</row>
  </sheetData>
</worksheet>''';

  final registro = '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet $ns>
  <sheetData>
    <row r="1">${inline('A1', 'Data')}${inline('B1', 'Matéria')}${inline('C1', 'Tarefa')}${inline('D1', 'Aula')}${inline('E1', 'Página inicial')}${inline('F1', 'Página final')}${inline('G1', 'Tempo')}${inline('I1', 'Comentário')}${inline('J1', 'Páginas lidas')}${inline('K1', 'Páginas/hora')}</row>
    <row r="2">${inline('G2', 'Horas')}${inline('H2', 'Minutos')}</row>
    <row r="3">${numero('A3', serial(DateTime(2026, 7, 9)))}${inline('B3', 'Português')}${inline('C3', 'Lei seca')}${inline('D3', 'Aula 5')}${numero('E3', 10)}${numero('F3', 20)}${numero('G3', 1)}${numero('H3', 30)}${inline('I3', 'ok')}${numero('K3', 7.3)}</row>
    <row r="4">${numero('A4', serial(DateTime(2026, 7, 8)))}${inline('B4', 'Contabilidade')}${numero('H4', 45)}</row>
  </sheetData>
</worksheet>''';

  final sefaz = '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet $ns>
  <sheetData>
    <row r="1">${inline('A1', 'Matéria')}${inline('B1', 'Número questões')}${inline('C1', 'Peso')}${inline('D1', 'Mínimo')}</row>
    <row r="2">${inline('A2', 'Português')}${numero('B2', 20)}${numero('C2', 2)}${numero('D2', 12)}</row>
    <row r="3">${inline('A3', 'Direito Tributário')}${numero('B3', 15)}${numero('C3', 3)}${numero('D3', 9)}</row>
  </sheetData>
</worksheet>''';

  final zip = Archive()
    ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', rels))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', visaoGeral))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet2.xml', registro))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet3.xml', sefaz));
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  group('XlsxReader', () {
    test('lê abas, shared strings (rich text), inline e linha esparsa', () {
      final abas = XlsxReader.lerAbas(xlsxDeTeste());
      expect(abas.keys.toList(), ['Registro de Horas', 'Revisões']);

      final registro = abas['Registro de Horas']!;
      expect(registro[0][0], 'Data');
      expect(registro[0][1], 'Matéria'); // rich text concatenado
      expect(registro[1][1], 'Português'); // inline string
      expect(registro[2], isEmpty); // linha 3 pulada no arquivo
      expect(registro[3][8], '60');
    });

    test('bytes que não são zip: FormatException explícita', () {
      expect(() => XlsxReader.lerAbas(Uint8List.fromList([1, 2, 3])),
          throwsFormatException);
    });
  });

  group('PlanilhaImportService', () {
    test('importa registros: tempo, páginas, matéria existente reusada', () {
      final resultado = PlanilhaImportService.parse(
        XlsxReader.lerAbas(xlsxDeTeste()),
        materiasExistentes: [materiaPortugues()],
      );

      expect(resultado.registros.length, 2);
      final r1 = resultado.registros[0];
      expect(r1.data, DateTime(2026, 7, 9));
      expect(r1.materiaId, 'm-port'); // reusou a existente, não criou outra
      expect(r1.minutos, 90); // 1h + 30min
      expect(r1.tarefa, 'PDF 2');
      expect(r1.paginaInicial, 10);
      expect(r1.paginaFinal, 20);
      expect(r1.paginasLidas, 11);
      expect(r1.comentario, 'boa sessão');

      // Só "Direito Constitucional" é nova; ganha slot de cor livre (0 usado).
      expect(resultado.materiasNovas.length, 1);
      expect(resultado.materiasNovas.first.nome, 'Direito Constitucional');
      expect(resultado.materiasNovas.first.corSlot, 1);
      expect(resultado.registros[1].materiaId,
          resultado.materiasNovas.first.id);
      expect(resultado.registros[1].minutos, 45);

      // Tópico "Crase" criado e ligado ao registro.
      expect(resultado.topicosNovos.length, 1);
      expect(resultado.topicosNovos.first.nome, 'Crase');
      expect(r1.topicoId, resultado.topicosNovos.first.id);
    });

    test('linha com data inválida vira aviso, nunca descarte silencioso', () {
      final resultado = PlanilhaImportService.parse(
        XlsxReader.lerAbas(xlsxDeTeste()),
        materiasExistentes: [materiaPortugues()],
      );
      expect(resultado.avisos, hasLength(1));
      expect(resultado.avisos.first, contains('linha 4'));
      expect(resultado.avisos.first, contains('data inválida'));
    });

    test('importa revisões com status e intervalo', () {
      final resultado = PlanilhaImportService.parse(
        XlsxReader.lerAbas(xlsxDeTeste()),
        materiasExistentes: [materiaPortugues()],
      );
      expect(resultado.revisoes.length, 2);
      final feita = resultado.revisoes[0];
      expect(feita.titulo, 'Crase');
      expect(feita.dataAgendada, DateTime(2026, 7, 16));
      expect(feita.intervaloDias, 7);
      expect(feita.feita, true);
      expect(resultado.revisoes[1].feita, false);
      expect(resultado.revisoes[1].intervaloDias, 15);
    });

    test('re-importar gera os MESMOS ids (não duplica dados)', () {
      final a = PlanilhaImportService.parse(
        XlsxReader.lerAbas(xlsxDeTeste()),
        materiasExistentes: [materiaPortugues()],
      );
      final b = PlanilhaImportService.parse(
        XlsxReader.lerAbas(xlsxDeTeste()),
        materiasExistentes: [materiaPortugues()],
      );
      expect(a.registros.map((r) => r.id).toList(),
          b.registros.map((r) => r.id).toList());
      expect(a.revisoes.map((r) => r.id).toList(),
          b.revisoes.map((r) => r.id).toList());
      expect(a.materiasNovas.map((m) => m.id).toList(),
          b.materiasNovas.map((m) => m.id).toList());
    });

    test('planilha real: Tempo mesclado sobre Horas/Minutos', () {
      final resultado = PlanilhaImportService.parse(
        XlsxReader.lerAbas(xlsxPlanilhaReal()),
        materiasExistentes: [materiaPortugues()],
      );
      expect(resultado.registros.length, 2);
      final r1 = resultado.registros[0];
      expect(r1.minutos, 90); // 1h + 30min sob "Tempo"
      expect(r1.tarefa, 'Lei seca · Aula 5');
      expect(r1.paginaInicial, 10);
      expect(r1.paginasLidas, 11);
      expect(r1.comentario, 'ok');
      expect(resultado.registros[1].minutos, 45); // só subcoluna Minutos
      expect(resultado.avisos, isEmpty); // Páginas/hora derivada não avisa
    });

    test('planilha real: aba Sefaz atualiza peso/questões/mínimo', () {
      final resultado = PlanilhaImportService.parse(
        XlsxReader.lerAbas(xlsxPlanilhaReal()),
        materiasExistentes: [materiaPortugues()],
      );
      expect(resultado.materiasAtualizadas.length, 1);
      final port = resultado.materiasAtualizadas.first;
      expect(port.id, 'm-port'); // atualiza a existente, não cria outra
      expect(port.peso, 2);
      expect(port.questoes, 20);
      expect(port.minimo, 12);

      final tributario = resultado.materiasNovas
          .firstWhere((m) => m.nome == 'Direito Tributário');
      expect(tributario.peso, 3);
      expect(tributario.questoes, 15);
      expect(tributario.minimo, 9);
    });

    test('planilha real: meta semanal vem da Visão Geral; derivadas não', () {
      final resultado = PlanilhaImportService.parse(
        XlsxReader.lerAbas(xlsxPlanilhaReal()),
        materiasExistentes: [materiaPortugues()],
      );
      expect(resultado.metaSemanalMinutos, 30 * 60);
      // "Horas feitas/restantes/acumuladas" são derivadas: nada delas
      // vira registro (só as 2 sessões da aba de registro existem).
      expect(resultado.registros.length, 2);
    });

    test('coluna Tempo única: relógio, fração de dia e horas decimais', () {
      final d = serial(DateTime(2026, 7, 9)).toString();
      final resultado = PlanilhaImportService.parse(
        {
          'Registro': [
            ['Data', 'Matéria', 'Tempo'],
            [d, 'X', '1:30'],
            [d, 'X', '0.0625'],
            [d, 'X', '1.5'],
            [d, 'X', '45'],
          ],
        },
        materiasExistentes: const [],
      );
      expect(resultado.registros.map((r) => r.minutos).toList(),
          [90, 90, 90, 45]);
    });

    test('planilha sem cabeçalho reconhecido: FormatException', () {
      expect(
        () => PlanilhaImportService.parse(
          {
            'Qualquer': [
              ['a', 'b'],
              ['1', '2'],
            ],
          },
          materiasExistentes: const [],
        ),
        throwsFormatException,
      );
    });
  });

  /// D-02 — identidade das linhas importadas.
  ///
  /// Até 08/2026 o id de registro e revisão embutia o ÍNDICE DA LINHA. O
  /// teste que existia ("re-importar gera os MESMOS ids") reimportava o
  /// arquivo byte a byte idêntico, então nunca tocou no furo: bastava
  /// inserir uma sessão nova no topo, apagar uma linha ou clicar em
  /// "Classificar" no Excel para todos os ids abaixo mudarem e o `mesclar`
  /// (upsert por id) regravar a coleção inteira. Duas sessões viravam quatro.
  ///
  /// As abas vão montadas à mão, sem passar por um .xlsx: o que está sob
  /// teste é a identidade das LINHAS, e um fixture de zip+XML por variação
  /// esconderia qual linha mudou. `XlsxReader` tem suíte própria acima.
  group('PlanilhaImportService — id por conteúdo (D-02)', () {
    const cabRegistro = ['Data', 'Matéria', 'Horas', 'Minutos', 'Tarefa'];
    const cabRevisao = [
      'Data',
      'Matéria',
      'O que revisar',
      'Intervalo',
      'Status',
    ];

    const sessaoA = ['09/07/2026', 'Português', '1', '30', 'Crase'];
    const sessaoB = ['08/07/2026', 'Direito', '0', '45', ''];
    const sessaoNova = ['10/07/2026', 'Português', '2', '0', 'Regência'];

    const revisaoA = ['16/07/2026', 'Português', 'Crase', '7', 'Feita'];
    const revisaoB = ['20/07/2026', 'Português', 'Controle', '7', ''];

    List<String> idsRegistro(List<List<String>> linhas) =>
        PlanilhaImportService.parse(
          {
            'Registro de Horas': [cabRegistro, ...linhas],
          },
          materiasExistentes: [materiaPortugues()],
        ).registros.map((r) => r.id).toList();

    List<String> idsRevisao(List<List<String>> linhas) =>
        PlanilhaImportService.parse(
          {
            'Revisões': [cabRevisao, ...linhas],
          },
          materiasExistentes: [materiaPortugues()],
        ).revisoes.map((r) => r.id).toList();

    test('reordenar a planilha não muda nenhum id', () {
      // Um clique em "Classificar" no Excel bastava para zerar a interseção.
      expect(
        idsRegistro([sessaoA, sessaoB]).toSet(),
        idsRegistro([sessaoB, sessaoA]).toSet(),
      );
      expect(
        idsRevisao([revisaoA, revisaoB]).toSet(),
        idsRevisao([revisaoB, revisaoA]).toSet(),
      );
    });

    test('inserir sessão no topo cria id só para ela', () {
      final antes = idsRegistro([sessaoA, sessaoB]).toSet();
      final depois = idsRegistro([sessaoNova, sessaoA, sessaoB]).toSet();
      expect(depois, containsAll(antes));
      expect(depois.difference(antes), hasLength(1));
    });

    test('apagar uma linha não mexe no id das outras', () {
      expect(idsRegistro([sessaoA]).first, idsRegistro([sessaoA, sessaoB])[0]);
    });

    test('duas linhas idênticas continuam sendo dois registros', () {
      // Dois blocos de 30min da mesma tarefa no mesmo dia são duas sessões.
      // Sem o contador de ocorrências, a chave de conteúdo as fundiria numa.
      final ids = idsRegistro([sessaoA, sessaoA]);
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
      // E o par é estável entre imports.
      expect(idsRegistro([sessaoA, sessaoA]), ids);
    });

    test('corrigir o tempo na planilha atualiza o registro, não duplica', () {
      // Minutos/páginas/comentário são ATRIBUTOS da sessão, fora da chave.
      expect(
        idsRegistro([
          ['09/07/2026', 'Português', '1', '30', 'Crase'],
        ]).first,
        idsRegistro([
          ['09/07/2026', 'Português', '0', '45', 'Crase'],
        ]).first,
      );
    });

    test('linha nova na MESMA data não sequestra o id da antiga', () {
      // O pior caso do esquema antigo não era duplicar, era SOBRESCREVER:
      // a linha nova herdava `xlsx-registro-1-<data>` e a sessão original
      // sumia em silêncio.
      final original = idsRegistro([sessaoA]).first;
      final depois = idsRegistro([
        ['09/07/2026', 'Português', '2', '0', 'Regência'],
        sessaoA,
      ]);
      expect(depois.last, original);
      expect(depois.first, isNot(original));
    });

    test('idDeEsquemaAntigo separa os dois esquemas sem ambiguidade', () {
      expect(
        PlanilhaImportService.idDeEsquemaAntigo('xlsx-registro-1-2026-07-09'),
        isTrue,
      );
      expect(
        PlanilhaImportService.idDeEsquemaAntigo('xlsx-revisao-12-2026-07-16'),
        isTrue,
      );
      // O novo começa pela data e SEGUE com hash e contador: o `$` do regex
      // não fecha.
      expect(
        PlanilhaImportService.idDeEsquemaAntigo(idsRegistro([sessaoA]).first),
        isFalse,
      );
      expect(
        PlanilhaImportService.idDeEsquemaAntigo(idsRevisao([revisaoA]).first),
        isFalse,
      );
      // Registro criado à mão no app não pode ser varrido pela limpeza.
      expect(
        PlanilhaImportService.idDeEsquemaAntigo(
          '550e8400-e29b-41d4-a716-446655440000',
        ),
        isFalse,
      );
    });

    test('o hash é o mesmo na VM e no web', () {
      // Pino de regressão. O FNV-1a roda em BigInt porque no web `int` é
      // double de 53 bits: a versão com `int` nativo nem compila
      // (`dart compile js` rejeita a máscara 0xFFFFFFFFFFFFFFFF) e, reduzida
      // para caber, daria ids diferentes por plataforma — o mesmo defeito de
      // identidade, reencarnado. Os literais abaixo foram conferidos com
      // `dart compile js` + node: idênticos byte a byte.
      expect(
        idsRegistro([sessaoA]).first,
        'xlsx-registro-2026-07-09-d6054c927e382ae3-0',
      );
      expect(
        idsRevisao([revisaoA]).first,
        'xlsx-revisao-2026-07-16-7f432e5b2077a323-0',
      );
      expect(idsRegistro([sessaoA, sessaoA]), [
        'xlsx-registro-2026-07-09-d6054c927e382ae3-0',
        'xlsx-registro-2026-07-09-d6054c927e382ae3-1',
      ]);
    });

    test('o cenário que gerava duplicata agora fecha em 3 registros', () {
      // Reprodução literal do furo: importa 2 sessões, o usuário estuda mais
      // uma, a planilha (ordenada por data desc) recebe a nova no topo e é
      // reimportada. Antes: 5 registros, 390 min para 255 min reais.
      final estado = <String, int>{};
      for (final linhas in [
        [sessaoA, sessaoB],
        [sessaoNova, sessaoA, sessaoB],
      ]) {
        final resultado = PlanilhaImportService.parse(
          {
            'Registro de Horas': [cabRegistro, ...linhas],
          },
          materiasExistentes: [materiaPortugues()],
        );
        // Espelha o upsert por id de `_HiveRepositorio.mesclar`.
        for (final r in resultado.registros) {
          estado[r.id] = r.minutos;
        }
      }
      expect(estado, hasLength(3));
      expect(estado.values.fold(0, (a, b) => a + b), 90 + 45 + 120);
    });
  });
}
