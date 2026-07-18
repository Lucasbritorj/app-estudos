/// Sessão de leitura de um dia: páginas + minutos. Min/pág é DERIVADO.
class SessaoLeitura {
  final DateTime data;
  final int paginas;

  /// Minutos gastos; null = não cronometrado.
  final int? minutos;

  const SessaoLeitura({
    required this.data,
    required this.paginas,
    this.minutos,
  });

  double? get minutosPorPagina =>
      (minutos == null || minutos! <= 0 || paginas <= 0)
      ? null
      : minutos! / paginas;

  Map<String, dynamic> toJson() => {
    'data': data.toIso8601String(),
    'paginas': paginas,
    'minutos': minutos,
  };

  factory SessaoLeitura.fromJson(Map<String, dynamic> json) => SessaoLeitura(
    data: DateTime.parse(json['data'] as String),
    paginas: (json['paginas'] as num).toInt(),
    minutos: (json['minutos'] as num?)?.toInt(),
  );
}

/// Material de leitura (PDF/livro) dividido em partes — espelha a aba
/// "Divisão de PDFs": gerador de 2 a 10 divisões com progresso por parte.
class Leitura {
  final String id;
  final String titulo;
  final String? materiaId;
  final int paginaInicio;
  final int paginaFim;
  final int partes;

  /// Uma flag por parte, tamanho sempre == [partes].
  final List<bool> partesConcluidas;

  /// Registro diário de leitura (campo tolerante: dados antigos = vazio).
  final List<SessaoLeitura> sessoes;

  const Leitura({
    required this.id,
    required this.titulo,
    this.materiaId,
    required this.paginaInicio,
    required this.paginaFim,
    required this.partes,
    required this.partesConcluidas,
    this.sessoes = const [],
  });

  int get totalPaginas => paginaFim - paginaInicio + 1;

  int get paginasRegistradas => sessoes.fold(0, (soma, s) => soma + s.paginas);

  int get minutosRegistrados =>
      sessoes.fold(0, (soma, s) => soma + (s.minutos ?? 0));

  /// Ritmo médio ponderado (só sessões com tempo); null sem dados —
  /// nunca inventa valor.
  double? get minutosPorPagina {
    var paginas = 0;
    var minutos = 0;
    for (final s in sessoes) {
      if (s.minutos != null && s.minutos! > 0 && s.paginas > 0) {
        paginas += s.paginas;
        minutos += s.minutos!;
      }
    }
    if (paginas == 0) return null;
    return minutos / paginas;
  }

  /// Projeção de tempo para as páginas restantes no ritmo atual.
  int? get minutosParaTerminar {
    final ritmo = minutosPorPagina;
    if (ritmo == null) return null;
    final restantes = (totalPaginas - paginasRegistradas).clamp(
      0,
      totalPaginas,
    );
    return (restantes * ritmo).round();
  }

  Leitura copyWith({
    String? titulo,
    List<bool>? partesConcluidas,
    List<SessaoLeitura>? sessoes,
  }) => Leitura(
    id: id,
    titulo: titulo ?? this.titulo,
    materiaId: materiaId,
    paginaInicio: paginaInicio,
    paginaFim: paginaFim,
    partes: partes,
    partesConcluidas: partesConcluidas ?? this.partesConcluidas,
    sessoes: sessoes ?? this.sessoes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'titulo': titulo,
    'materiaId': materiaId,
    'paginaInicio': paginaInicio,
    'paginaFim': paginaFim,
    'partes': partes,
    'partesConcluidas': partesConcluidas,
    'sessoes': sessoes.map((s) => s.toJson()).toList(),
  };

  factory Leitura.fromJson(Map<String, dynamic> json) {
    final partes = (json['partes'] as num).toInt();
    final concluidas =
        (json['partesConcluidas'] as List?)?.map((e) => e == true).toList() ??
        List.filled(partes, false);
    return Leitura(
      id: json['id'] as String,
      titulo: json['titulo'] as String,
      materiaId: json['materiaId'] as String?,
      paginaInicio: (json['paginaInicio'] as num).toInt(),
      paginaFim: (json['paginaFim'] as num).toInt(),
      partes: partes,
      partesConcluidas: concluidas.length == partes
          ? concluidas
          : List.filled(partes, false),
      sessoes: (json['sessoes'] as List? ?? const [])
          .map(
            (e) => SessaoLeitura.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }
}
