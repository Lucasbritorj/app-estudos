import 'dart:typed_data';

import 'package:app_estudos/domain/xlsx_reader.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Segurança do leitor de .xlsx (A-001 do ledger): um arquivo hostil pode
/// declarar referências de linha/coluna gigantes nos atributos `r` e dirigir
/// a alocação de memória do parser (CWE-400). O leitor deve rejeitar refs
/// além dos limites reais do Excel (1.048.576 linhas × 16.384 colunas) com
/// FormatException — nunca alocar sob controle do arquivo.
Uint8List xlsxComSheet(String sheetXml) {
  const ns =
      'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
  const workbook = '''
<?xml version="1.0" encoding="UTF-8"?>
<workbook $ns xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Plan1" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';
  const rels = '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="w" Target="worksheets/sheet1.xml"/>
</Relationships>''';
  final zip = Archive()
    ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', rels))
    ..addFile(ArchiveFile.string('xl/worksheets/sheet1.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<worksheet $ns><sheetData>$sheetXml</sheetData></worksheet>'''));
  return Uint8List.fromList(ZipEncoder().encode(zip));
}

void main() {
  group('XlsxReader — limites contra arquivo hostil', () {
    test('linha declarada além do máximo do Excel lança FormatException', () {
      // r="2000000" > 1.048.576: sem teto, o parser alocaria 2M de linhas
      // vazias ditadas pelo arquivo.
      final bytes = xlsxComSheet(
          '<row r="2000000"><c r="A2000000" t="inlineStr"><is><t>x</t></is></c></row>');
      expect(() => XlsxReader.lerAbas(bytes),
          throwsA(isA<FormatException>()));
    });

    test('coluna declarada além do máximo do Excel lança FormatException',
        () {
      // ZZZ = coluna 18.278 > 16.384: sem teto, o parser alocaria as células
      // intermediárias ditadas pelo arquivo.
      final bytes = xlsxComSheet(
          '<row r="1"><c r="ZZZ1" t="inlineStr"><is><t>x</t></is></c></row>');
      expect(() => XlsxReader.lerAbas(bytes),
          throwsA(isA<FormatException>()));
    });

    test('refs no limite real do Excel continuam aceitas', () {
      // XFD é a última coluna legítima (16.384): não pode ser rejeitada.
      final bytes = xlsxComSheet(
          '<row r="3"><c r="XFD3" t="inlineStr"><is><t>ok</t></is></c></row>');
      final abas = XlsxReader.lerAbas(bytes);
      expect(abas['Plan1']![2].last, 'ok');
      expect(abas['Plan1']![2].length, 16384);
    });
  });

  group('XlsxReader — zip bomb (tamanho declarado mentiroso)', () {
    // Parte cujo conteúdo REAL expande muito além do teto, mas cujo header
    // ZIP declara um `size` pequeno. A defesa não pode confiar no header —
    // tem de medir os bytes reais da inflação.
    Uint8List xlsxComParteMentirosa(int bytesReais,
        {required int tamanhoDeclarado}) {
      const ns =
          'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
      const workbook = '''
<?xml version="1.0" encoding="UTF-8"?>
<workbook $ns xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Plan1" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';
      const rels = '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="w" Target="worksheets/sheet1.xml"/>
</Relationships>''';
      // Conteúdo altamente compressível (comprime muito, expande no acesso).
      final recheio = 'A' * bytesReais;
      final grande = '<?xml version="1.0" encoding="UTF-8"?>'
          '<worksheet $ns><sheetData><row r="1">'
          '<c r="A1" t="inlineStr"><is><t>$recheio</t></is></c>'
          '</row></sheetData></worksheet>';
      final parteBomba =
          ArchiveFile.string('xl/worksheets/sheet1.xml', grande);
      // MENTIRA: o header passa a declarar um tamanho pequeno, embora o
      // conteúdo real seja `grande`.
      parteBomba.size = tamanhoDeclarado;
      final zip = Archive()
        ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
        ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', rels))
        ..addFile(parteBomba);
      return Uint8List.fromList(ZipEncoder().encode(zip));
    }

    test('parte que estoura o teto real é rejeitada mesmo declarando size '
        'pequeno', () {
      // Conteúdo real ~64 KB; teto injetado 4 KB; header mente "1000 bytes".
      final bytes =
          xlsxComParteMentirosa(64 * 1024, tamanhoDeclarado: 1000);
      expect(
          () => XlsxReader.lerAbas(bytes, maxBytesParte: 4 * 1024),
          throwsA(isA<FormatException>()));
    });

    test('parte dentro do teto real continua aceita', () {
      final bytes = xlsxComParteMentirosa(1024, tamanhoDeclarado: 1000);
      // Não deve lançar: 1 KB real < 4 KB de teto.
      expect(() => XlsxReader.lerAbas(bytes, maxBytesParte: 4 * 1024),
          returnsNormally);
    });

    test('arquivo inteiro acima do teto de entrada é rejeitado cedo', () {
      final bytes = xlsxComSheet(
          '<row r="1"><c r="A1" t="inlineStr"><is><t>x</t></is></c></row>');
      expect(() => XlsxReader.lerAbas(bytes, maxBytesArquivo: 10),
          throwsA(isA<FormatException>()));
    });

    test('método de compressão não suportado (ex.: bzip2) é rejeitado '
        'explícito, sem inflar lixo', () {
      const ns =
          'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
      const workbook = '''
<?xml version="1.0" encoding="UTF-8"?>
<workbook $ns xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Plan1" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';
      const rels = '''
<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="w" Target="worksheets/sheet1.xml"/>
</Relationships>''';
      final sheet = ArchiveFile.string('xl/worksheets/sheet1.xml',
          '<?xml version="1.0"?><worksheet $ns><sheetData/></worksheet>')
        ..compression = CompressionType.bzip2;
      final zip = Archive()
        ..addFile(ArchiveFile.string('xl/workbook.xml', workbook))
        ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', rels))
        ..addFile(sheet);
      final bytes = Uint8List.fromList(ZipEncoder().encode(zip));
      expect(() => XlsxReader.lerAbas(bytes),
          throwsA(isA<FormatException>()));
    });
  });
}
