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

  /// Teto de bytes REAIS descomprimidos por parte XML. Medido durante a
  /// inflação (não pelo `size` do header do zip, que o atacante controla):
  /// defesa contra zip bomb (CWE-400). Uma parte de planilha real fica
  /// muito abaixo disso.
  static const _maxBytesParteXml = 50 * 1024 * 1024;

  /// Teto do arquivo .xlsx inteiro (bytes comprimidos reais recebidos).
  /// Rejeição barata antes de descomprimir qualquer coisa.
  static const _maxBytesArquivo = 64 * 1024 * 1024;

  /// Nome da aba -> linhas -> células como texto ('' para célula vazia).
  /// Linhas preservam a numeração original (linhas puladas viram vazias).
  /// Qualquer conteúdo corrompido vira FormatException com contexto —
  /// nunca exceção crua de zip/XML vazando para a UI.
  ///
  /// [maxBytesParte] e [maxBytesArquivo] são costuras de teste; produção usa
  /// os tetos padrão.
  static Map<String, List<List<String>>> lerAbas(
    Uint8List bytes, {
    int maxBytesParte = _maxBytesParteXml,
    int maxBytesArquivo = _maxBytesArquivo,
  }) {
    if (bytes.length > maxBytesArquivo) {
      throw FormatException(
          'Arquivo .xlsx excede ${maxBytesArquivo ~/ (1024 * 1024)} MB — '
          'rejeitado por segurança antes de abrir.');
    }
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
          return _descomprimirLimitado(f, caminho, maxBytesParte);
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

  /// Descomprime uma parte do zip abortando assim que os bytes REAIS passam
  /// do teto — defesa contra zip bomb (header mente tamanho pequeno, conteúdo
  /// expande para GBs).
  ///
  /// Inflaciona chamando `Inflate.stream(..., output: _SaidaLimitada)`
  /// DIRETAMENTE, em vez de `f.decompress`/`f.content`. Isso é deliberado:
  /// o wrapper padrão de descompressão da plataforma web
  /// (`_zlib_decoder_web.dart`) materializa a parte inteira em memória
  /// (`Inflate.stream(input).getBytes()`) ANTES de escrever no output — o
  /// teto só agiria tarde demais, sem limitar o pico. O `Inflate` (Dart puro,
  /// idêntico em todas as plataformas) escreve bloco a bloco no stream, então
  /// o corte acontece antes de o payload ser materializado, inclusive no
  /// alvo de deploy web. Entradas de zip usam deflate cru (raw), que é
  /// exatamente o que `Inflate` espera.
  static String _descomprimirLimitado(
      ArchiveFile f, String caminho, int maxBytes) {
    final saida = _SaidaLimitada(maxBytes);
    final raw = f.rawContent;
    try {
      if (raw == null) {
        return '';
      }
      if (f.compression == CompressionType.none) {
        // Armazenado sem compressão: sem inflar; capa o tamanho real e copia.
        final bruto = raw.getStream(decompress: false);
        saida.writeStream(bruto);
      } else {
        // Deflate (padrão do .xlsx): inflação incremental para o teto.
        Inflate.stream(raw.getStream(decompress: false), output: saida);
      }
    } on _LimiteExcedido {
      throw FormatException(
          'Parte "$caminho" excede ${maxBytes ~/ (1024 * 1024)} MB '
          'descomprimida — arquivo rejeitado por segurança.');
    }
    return utf8.decode(saida.getBytes(), allowMalformed: true);
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

/// Sinaliza que a descompressão passou do teto de bytes reais.
class _LimiteExcedido implements Exception {
  const _LimiteExcedido();
}

/// Buffer de saída que aborta a inflação assim que os bytes escritos passam
/// de [maxBytes]. Como o `archive` inflaciona incrementalmente para este
/// stream, o corte acontece antes de o payload de um zip bomb ser
/// materializado — a checagem é sobre bytes REAIS, não sobre o `size`
/// declarado no header (que o atacante controla).
class _SaidaLimitada extends OutputMemoryStream {
  _SaidaLimitada(this.maxBytes);
  final int maxBytes;

  @override
  void writeByte(int value) {
    if (length + 1 > maxBytes) throw const _LimiteExcedido();
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    if (this.length + (length ?? bytes.length) > maxBytes) {
      throw const _LimiteExcedido();
    }
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    if (length + stream.length > maxBytes) throw const _LimiteExcedido();
    super.writeStream(stream);
  }
}
