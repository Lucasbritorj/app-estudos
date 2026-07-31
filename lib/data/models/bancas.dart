/// Catálogo e normalização de bancas organizadoras.
///
/// Banca é dimensão de análise, não texto livre: CESPE e FGV cobram de jeitos
/// diferentes (certo/errado vs. múltipla escolha, literalidade vs. raciocínio),
/// e a taxa de acerto por banca é o sinal que diz onde o candidato apanha.
/// Sem normalização o ranking fragmenta — "cespe", "CESPE/CEBRASPE" e
/// "Cebraspe" viram três linhas de 10 questões em vez de uma de 30.
class Bancas {
  /// Bancas mais frequentes em concursos federais/estaduais, para sugestão no
  /// formulário. Lista de conveniência: qualquer texto é aceito, então uma
  /// banca regional não fica de fora.
  static const sugestoes = <String>[
    'CEBRASPE',
    'FGV',
    'FCC',
    'VUNESP',
    'IBFC',
    'AOCP',
    'IADES',
    'QUADRIX',
    'CESGRANRIO',
    'IDECAN',
    'INSTITUTO ACESSO',
    'CONSULPLAN',
    'IBADE',
    'FUNDATEC',
    'INSTITUTO AOCP',
    'ESAF',
  ];

  /// Apelidos que apontam para a mesma organizadora.
  static const _apelidos = <String, String>{
    'CESPE': 'CEBRASPE',
    'CESPE/CEBRASPE': 'CEBRASPE',
    'CESPE-CEBRASPE': 'CEBRASPE',
    'CEBRASPE/CESPE': 'CEBRASPE',
    'FUNDACAO GETULIO VARGAS': 'FGV',
    'FUNDACAO CARLOS CHAGAS': 'FCC',
    'FUNDACAO VUNESP': 'VUNESP',
    'CESGRANRIO FUNDACAO': 'CESGRANRIO',
  };

  /// Chave canônica da banca: maiúsculas, sem acento, espaços colapsados e
  /// apelido resolvido. Null/vazio devolve null — "não informada" é um estado
  /// legítimo e nunca vira a string vazia (que poluiria o agrupamento).
  static String? normalizar(String? bruta) {
    if (bruta == null) return null;
    final semAcento = _semAcento(bruta.trim()).toUpperCase();
    final limpa = semAcento.replaceAll(RegExp(r'\s+'), ' ');
    if (limpa.isEmpty) return null;
    return _apelidos[limpa] ?? limpa;
  }

  static const _comAcento = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç';
  static const _semAcentoMap = 'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc';

  static String _semAcento(String texto) {
    final buffer = StringBuffer();
    for (final rune in texto.runes) {
      final char = String.fromCharCode(rune);
      final i = _comAcento.indexOf(char);
      buffer.write(i >= 0 ? _semAcentoMap[i] : char);
    }
    return buffer.toString();
  }
}
