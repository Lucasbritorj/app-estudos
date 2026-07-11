class ItemEdital {
  final String nome;

  /// Profundidade hierárquica: "1" = 0, "1.2" = 1, "1.2.3" = 2.
  final int nivel;

  const ItemEdital({required this.nome, required this.nivel});
}

/// Parser de conteúdo programático colado como texto. Heurística:
/// numeração com pontos define a profundidade; marcadores (-, •, *) viram
/// filhos do último item numerado; linha sem prefixo é item de raiz.
class EditalParserService {
  static final _numerado = RegExp(r'^(\d+(?:\.\d+)*)[\.\)]?\s+(.+)$');
  static final _marcador = RegExp(r'^[-•*]\s+(.+)$');

  static List<ItemEdital> parse(String texto) {
    final itens = <ItemEdital>[];
    var nivelAnterior = -1;

    for (final linhaCrua in texto.split('\n')) {
      final linha = linhaCrua.trim();
      if (linha.isEmpty) continue;

      final numerado = _numerado.firstMatch(linha);
      if (numerado != null) {
        final nivel = '.'.allMatches(numerado.group(1)!).length;
        itens.add(ItemEdital(nome: numerado.group(2)!.trim(), nivel: nivel));
        nivelAnterior = nivel;
        continue;
      }

      final marcador = _marcador.firstMatch(linha);
      if (marcador != null) {
        final nivel = nivelAnterior < 0 ? 0 : nivelAnterior + 1;
        itens.add(ItemEdital(nome: marcador.group(1)!.trim(), nivel: nivel));
        continue;
      }

      itens.add(ItemEdital(nome: linha, nivel: 0));
      nivelAnterior = 0;
    }
    return itens;
  }
}
