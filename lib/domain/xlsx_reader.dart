import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Leitor mínimo de .xlsx (zip + SpreadsheetML): extrai as células como texto,
/// aba por aba. Cobre o necessário para importar a planilha de estudos sem
/// adotar o pacote 'excel' completo (archive e xml já eram transitivos).
///
/// Limitação assumida: datas chegam como número serial do Excel (a conversão
/// fica no serviço de import, que conhece quais colunas são datas).
class XlsxReader {
  /// Limites reais do Excel. Refs `r` vêm do arquivo (não confiável) e ditam
  /// alocação de linhas/células — sem teto, um .xlsx hostil trava o app.
  static const _maxLinhas = 1048576;
  static const _maxColunas = 16384;
  static const _maxBytesParteXml = 50 * 1024 * 1024;

  /// Nome da aba -> linhas -> células como texto ('' para célula vazia).
  /// Linhas preservam a numeração original (linhas puladas viram vazias).
  /// Qualquer conteúdo corrompido vira FormatException com contexto —
  /// nunca exceção crua de zip/XML vazando para a UI.
  static Map<String, List<List<String>>> lerAbas(Uint8List bytes) {
    final Archive zip;
    try {
      zip = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
          'Arquivo não é um .xlsx válido (não é um zip legível). '
          'Confira se é a planilha salva pelo Excel, não .xls antigo ou .csv.');
    }

    String? conteudo(String caminho) {
      for (final f in zip.files) {
        if (f.name == caminho) {
          if (f.size > _maxBytesParteXml) {
            throw FormatException(
                'Parte "$caminho" excede '
                '${_maxBytesParteXml ~/ (1024 * 1024)} MB descomprimida — '
                'arquivo rejeitado por segurança.');
          }
          return utf8.decode(f.content as List<int>, allowMalformed: true);
        }
      }
      return null;
    }

    final compartilhadas = _protegido('textos compartilhados',
        () => _lerSharedStrings(conteudo('xl/sharedStrings.xml')));
    final abas = _protegido(
        'índice de abas',
        () => _mapearAbas(conteudo('xl/workbook.xml'),
            conteudo('xl/_rels/workbook.xml.rels')));

    final resultado = <String, List<List<String>>>{};
    for (final aba in abas.entries) {
      final xmlAba = conteudo('xl/${aba.value}');
      if (xmlAba == null) continue;
      resultado[aba.key] = _protegido(
          'aba "${aba.key}"', () => _lerPlanilha(xmlAba, compartilhadas));
    }
    if (resultado.isEmpty) {
      throw const FormatException(
          'Nenhuma aba encontrada — o arquivo é mesmo um .xlsx?');
    }
    return resultado;
  }

  /// Converte falha de XML/estrutura em FormatException com contexto.
  static T _protegido<T>(String onde, T Function() acao) {
    try {
      return acao();
    } on FormatException {
      rethrow;
    } catch (erro) {
      throw FormatException('Conteúdo corrompido em $onde do .xlsx: $erro');
    }
  }

  /// Aba (nome exibido) -> caminho relativo a xl/ do worksheet.
  static Map<String, String> _mapearAbas(String? workbook, String? rels) {
    if (workbook == null) {
      throw const FormatException('xl/workbook.xml ausente no arquivo.');
    }
    final alvosPorId = <String, String>{};
    if (rels != null) {
      for (final rel
          in XmlDocument.parse(rels).findAllElements('Relationship')) {
        final id = rel.getAttribute('Id');
        var alvo = rel.getAttribute('Target') ?? '';
        if (alvo.startsWith('/xl/')) alvo = alvo.substring(4);
        if (id != null && alvo.contains('worksheets/')) {
          alvosPorId[id] = alvo;
        }
      }
    }

    final abas = <String, String>{};
    var indice = 1;
    for (final sheet
        in XmlDocument.parse(workbook).findAllElements('sheet')) {
      final nome = sheet.getAttribute('name') ?? 'Planilha$indice';
      final rId = sheet.getAttribute('r:id') ?? sheet.getAttribute('id');
      final alvo = alvosPorId[rId] ?? 'worksheets/sheet$indice.xml';
      abas[nome] = alvo;
      indice++;
    }
    return abas;
  }

  static List<String> _lerSharedStrings(String? xml) {
    if (xml == null) return const [];
    return [
      for (final si in XmlDocument.parse(xml).findAllElements('si'))
        si.findAllElements('t').map((t) => t.innerText).join(),
    ];
  }

  static List<List<String>> _lerPlanilha(
      String xml, List<String> compartilhadas) {
    final linhas = <List<String>>[];
    for (final row in XmlDocument.parse(xml).findAllElements('row')) {
      final numeroLinha =
          int.tryParse(row.getAttribute('r') ?? '') ?? (linhas.length + 1);
      if (numeroLinha > _maxLinhas) {
        throw FormatException(
            'Linha $numeroLinha além do máximo do Excel ($_maxLinhas) — '
            'arquivo rejeitado por segurança.');
      }
      while (linhas.length < numeroLinha - 1) {
        linhas.add(const []);
      }
      final celulas = <String>[];
      for (final c in row.findElements('c')) {
        final coluna = _colunaDe(c.getAttribute('r') ?? '');
        if (coluna >= _maxColunas) {
          throw FormatException(
              'Célula além da coluna máxima do Excel (XFD) na linha '
              '$numeroLinha — arquivo rejeitado por segurança.');
        }
        while (celulas.length < coluna) {
          celulas.add('');
        }
        celulas.add(_valorDe(c, compartilhadas));
      }
      linhas.add(celulas);
    }
    return linhas;
  }

  static String _valorDe(XmlElement c, List<String> compartilhadas) {
    final tipo = c.getAttribute('t');
    if (tipo == 'inlineStr') {
      return c
          .findElements('is')
          .expand((e) => e.findAllElements('t'))
          .map((t) => t.innerText)
          .join();
    }
    final v = c.getElement('v')?.innerText ?? '';
    if (tipo == 's') {
      final i = int.tryParse(v);
      return (i != null && i >= 0 && i < compartilhadas.length)
          ? compartilhadas[i]
          : '';
    }
    if (tipo == 'b') return v == '1' ? 'true' : 'false';
    return v;
  }

  /// "B3" -> 1 (coluna 0-based); ignora a parte numérica.
  static int _colunaDe(String ref) {
    var coluna = 0;
    for (final code in ref.codeUnits) {
      if (code >= 65 && code <= 90) {
        coluna = coluna * 26 + (code - 64);
      } else {
        break;
      }
    }
    return coluna == 0 ? 0 : coluna - 1;
  }
}
