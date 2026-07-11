/// Formatação leve de notas — markdown-lite próprio, sem dependência:
/// **negrito**, ==destaque== e linhas iniciadas com "- " viram lista.
/// O storage continua texto puro (retrocompatível com notas existentes,
/// seguro para export e para editar em qualquer lugar).
class SegmentoNota {
  final String texto;
  final bool negrito;
  final bool destaque;

  const SegmentoNota(this.texto,
      {this.negrito = false, this.destaque = false});

  @override
  bool operator ==(Object other) =>
      other is SegmentoNota &&
      other.texto == texto &&
      other.negrito == negrito &&
      other.destaque == destaque;

  @override
  int get hashCode => Object.hash(texto, negrito, destaque);

  @override
  String toString() =>
      'SegmentoNota("$texto", negrito: $negrito, destaque: $destaque)';
}

class LinhaNota {
  final bool bullet;
  final List<SegmentoNota> segmentos;

  const LinhaNota({required this.bullet, required this.segmentos});
}

/// Marcadores inline: **...** (negrito) e ==...== (destaque). Sem
/// aninhamento — o primeiro marcador fechado vence.
final _inline = RegExp(r'\*\*(.+?)\*\*|==(.+?)==');

List<SegmentoNota> _parseInline(String texto) {
  final segmentos = <SegmentoNota>[];
  var cursor = 0;
  for (final m in _inline.allMatches(texto)) {
    if (m.start > cursor) {
      segmentos.add(SegmentoNota(texto.substring(cursor, m.start)));
    }
    final negrito = m.group(1);
    if (negrito != null) {
      segmentos.add(SegmentoNota(negrito, negrito: true));
    } else {
      segmentos.add(SegmentoNota(m.group(2)!, destaque: true));
    }
    cursor = m.end;
  }
  if (cursor < texto.length) {
    segmentos.add(SegmentoNota(texto.substring(cursor)));
  }
  return segmentos;
}

/// Texto puro -> linhas formatadas. Nunca lança: entrada malformada
/// (marcador sem fechar) rende texto literal.
List<LinhaNota> parseNotas(String texto) {
  return [
    for (final linha in texto.split('\n'))
      linha.startsWith('- ')
          ? LinhaNota(bullet: true, segmentos: _parseInline(linha.substring(2)))
          : LinhaNota(bullet: false, segmentos: _parseInline(linha)),
  ];
}
