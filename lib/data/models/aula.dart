/// Aula de um material em PDF (ex.: "Aula 00 — Licitações"). Unidade
/// central do estudo teórico: acumula páginas lidas por sessão e, ao
/// atingir [paginasTotais], dispara a cadeia de revisões espaçadas.
class Aula {
  final String id;
  final String materiaId;
  final String nome;
  final int paginasTotais;

  /// Acumulado pelas sessões de estudo teórico (nunca passa do total).
  final int paginasLidas;
  final bool concluida;
  final DateTime? dataConclusao;

  const Aula._({
    required this.id,
    required this.materiaId,
    required this.nome,
    required this.paginasTotais,
    this.paginasLidas = 0,
    this.concluida = false,
    this.dataConclusao,
  });

  /// Invariantes garantidas na construção: total não-negativo e páginas
  /// lidas sempre em [0, total] — o comentário do campo ("nunca passa do
  /// total") vira enforcement, valendo também para import de backup, não só
  /// para o fluxo de sessão.
  factory Aula({
    required String id,
    required String materiaId,
    required String nome,
    required int paginasTotais,
    int paginasLidas = 0,
    bool concluida = false,
    DateTime? dataConclusao,
  }) {
    final total = paginasTotais < 0 ? 0 : paginasTotais;
    final lidas = paginasLidas < 0 ? 0 : (paginasLidas > total ? total : paginasLidas);
    return Aula._(
      id: id,
      materiaId: materiaId,
      nome: nome,
      paginasTotais: total,
      paginasLidas: lidas,
      concluida: concluida,
      dataConclusao: dataConclusao,
    );
  }

  double get progresso =>
      paginasTotais <= 0 ? 0 : (paginasLidas / paginasTotais).clamp(0.0, 1.0);

  int get paginasRestantes =>
      (paginasTotais - paginasLidas).clamp(0, paginasTotais);

  Aula copyWith({
    String? nome,
    int? paginasTotais,
    int? paginasLidas,
    bool? concluida,
    DateTime? dataConclusao,
  }) {
    return Aula(
      id: id,
      materiaId: materiaId,
      nome: nome ?? this.nome,
      paginasTotais: paginasTotais ?? this.paginasTotais,
      paginasLidas: paginasLidas ?? this.paginasLidas,
      concluida: concluida ?? this.concluida,
      dataConclusao: dataConclusao ?? this.dataConclusao,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'materiaId': materiaId,
        'nome': nome,
        'paginasTotais': paginasTotais,
        'paginasLidas': paginasLidas,
        'concluida': concluida,
        'dataConclusao': dataConclusao?.toIso8601String(),
      };

  factory Aula.fromJson(Map<String, dynamic> json) => Aula(
        id: json['id'] as String,
        materiaId: json['materiaId'] as String,
        nome: json['nome'] as String,
        paginasTotais: (json['paginasTotais'] as num?)?.toInt() ?? 0,
        paginasLidas: (json['paginasLidas'] as num?)?.toInt() ?? 0,
        concluida: json['concluida'] as bool? ?? false,
        dataConclusao: json['dataConclusao'] == null
            ? null
            : DateTime.parse(json['dataConclusao'] as String),
      );
}
