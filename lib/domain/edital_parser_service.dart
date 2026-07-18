class ItemEdital {
  final String nome;

  /// Profundidade hierárquica: "1" = 0, "1.2" = 1, "1.2.3" = 2.
  final int nivel;

  const ItemEdital({required this.nome, required this.nivel});
}

/// Bloco de uma matéria dentro de um edital completo colado.
class SecaoEdital {
  /// Nome da matéria detectado no cabeçalho; null = texto sem cabeçalhos
  /// (uma matéria só).
  final String? materia;
  final List<ItemEdital> itens;

  const SecaoEdital({required this.materia, required this.itens});
}

/// Parser de conteúdo programático colado como texto (copiado do PDF).
/// PDFs colam vários itens na MESMA linha e separam por ';' — por isso o
/// texto é fragmentado por linha, por ';' e por numeração embutida antes
/// de classificar. Numeração com pontos define profundidade; marcadores
/// (-, •, *) e letras (a, b) viram filhos do último numerado.
class EditalParserService {
  static final _numerado = RegExp(r'^(\d+(?:\.\d+)*)\s*[\.\)\-–—:]?\s+(.+)$');
  static final _marcador = RegExp(r'^(?:[-•*]|[a-z][\)\.])\s+(.+)$');

  /// Quebra "…textos. 2 Tipologia… 2.1 Gêneros…" antes de cada numeração
  /// que segue pontuação de fim de item — o caso clássico do copy/paste de
  /// PDF que fazia metade dos tópicos sumir dentro do nome do anterior.
  static final _numeracaoEmbutida = RegExp(
    r'(?<=[\.;:])\s+(?=\d+(?:\.\d+)*\s*[\.\)\-–—:]?\s+\S)',
  );

  /// Cabeçalho de matéria colado no meio da linha ("… 2 Crase. NOÇÕES DE
  /// INFORMÁTICA: 1 Hardware…"): separa antes da sequência em caixa alta
  /// terminada em ':' que vem depois de pontuação.
  static final _cabecalhoEmbutido = RegExp(
    r'(?<=[\.;])\s+(?=[A-ZÀ-Ü][A-ZÀ-Ü0-9\s]{2,}:)',
  );

  static List<String> _fragmentar(String texto) {
    final fragmentos = <String>[];
    for (final linha in texto.split('\n')) {
      for (final pedaco in linha.split(';')) {
        for (final parte in pedaco.split(_cabecalhoEmbutido)) {
          for (final fragmento in parte.split(_numeracaoEmbutida)) {
            final limpo = fragmento.trim();
            if (limpo.isNotEmpty) fragmentos.add(limpo);
          }
        }
      }
    }
    return fragmentos;
  }

  /// Remove pontuação solta no fim do nome ("Crase." vira "Crase").
  static String _limparNome(String nome) =>
      nome.replaceAll(RegExp(r'[\s\.,;:]+$'), '').trim();

  static List<ItemEdital> parse(String texto) {
    final itens = <ItemEdital>[];
    var nivelAnterior = -1;

    for (final fragmento in _fragmentar(texto)) {
      final numerado = _numerado.firstMatch(fragmento);
      if (numerado != null) {
        final nivel = '.'.allMatches(numerado.group(1)!).length;
        itens.add(
          ItemEdital(nome: _limparNome(numerado.group(2)!), nivel: nivel),
        );
        nivelAnterior = nivel;
        continue;
      }

      final marcador = _marcador.firstMatch(fragmento);
      if (marcador != null) {
        final nivel = nivelAnterior < 0 ? 0 : nivelAnterior + 1;
        itens.add(
          ItemEdital(nome: _limparNome(marcador.group(1)!), nivel: nivel),
        );
        continue;
      }

      itens.add(ItemEdital(nome: _limparNome(fragmento), nivel: 0));
      nivelAnterior = 0;
    }
    return itens;
  }

  /// Cabeçalho de matéria: fragmento SEM numeração, curto, em caixa alta
  /// (≥70% das letras) ou terminando em ':' — padrão de edital
  /// ("LÍNGUA PORTUGUESA:", "NOÇÕES DE INFORMÁTICA").
  static bool _pareceMateria(String fragmento) {
    if (_numerado.hasMatch(fragmento) || _marcador.hasMatch(fragmento)) {
      return false;
    }
    final nome = _limparNome(fragmento);
    if (nome.length < 3 || nome.length > 80) return false;
    final letras = nome.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
    if (letras.isEmpty) return false;
    final maiusculas = letras.replaceAll(RegExp(r'[^A-ZÀ-Ü]'), '');
    return maiusculas.length / letras.length >= 0.7 ||
        fragmento.trim().endsWith(':');
  }

  /// Edital completo com várias matérias: cabeçalhos viram seções, itens
  /// numerados abaixo pertencem à seção corrente. Sem cabeçalho nenhum,
  /// devolve uma seção única com materia == null.
  static List<SecaoEdital> parseSecoes(String texto) {
    final secoes = <SecaoEdital>[];
    String? materiaAtual;
    var itensAtuais = <ItemEdital>[];
    var nivelAnterior = -1;

    void fechar() {
      if (materiaAtual != null || itensAtuais.isNotEmpty) {
        secoes.add(SecaoEdital(materia: materiaAtual, itens: itensAtuais));
      }
    }

    for (final fragmento in _fragmentar(texto)) {
      if (_pareceMateria(fragmento)) {
        fechar();
        materiaAtual = _limparNome(fragmento);
        itensAtuais = <ItemEdital>[];
        nivelAnterior = -1;
        continue;
      }
      final numerado = _numerado.firstMatch(fragmento);
      if (numerado != null) {
        final nivel = '.'.allMatches(numerado.group(1)!).length;
        itensAtuais.add(
          ItemEdital(nome: _limparNome(numerado.group(2)!), nivel: nivel),
        );
        nivelAnterior = nivel;
        continue;
      }
      final marcador = _marcador.firstMatch(fragmento);
      if (marcador != null) {
        final nivel = nivelAnterior < 0 ? 0 : nivelAnterior + 1;
        itensAtuais.add(
          ItemEdital(nome: _limparNome(marcador.group(1)!), nivel: nivel),
        );
        continue;
      }
      itensAtuais.add(ItemEdital(nome: _limparNome(fragmento), nivel: 0));
      nivelAnterior = 0;
    }
    fechar();
    return secoes;
  }
}
