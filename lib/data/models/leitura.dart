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

  const Leitura({
    required this.id,
    required this.titulo,
    this.materiaId,
    required this.paginaInicio,
    required this.paginaFim,
    required this.partes,
    required this.partesConcluidas,
  });

  int get totalPaginas => paginaFim - paginaInicio + 1;

  Leitura copyWith({String? titulo, List<bool>? partesConcluidas}) => Leitura(
        id: id,
        titulo: titulo ?? this.titulo,
        materiaId: materiaId,
        paginaInicio: paginaInicio,
        paginaFim: paginaFim,
        partes: partes,
        partesConcluidas: partesConcluidas ?? this.partesConcluidas,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titulo': titulo,
        'materiaId': materiaId,
        'paginaInicio': paginaInicio,
        'paginaFim': paginaFim,
        'partes': partes,
        'partesConcluidas': partesConcluidas,
      };

  factory Leitura.fromJson(Map<String, dynamic> json) {
    final partes = (json['partes'] as num).toInt();
    final concluidas = (json['partesConcluidas'] as List?)
            ?.map((e) => e == true)
            .toList() ??
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
    );
  }
}
