/// Ambiente de estudo: contêiner modular de matérias/estatísticas
/// (ex.: "Concurso SEFAZ-RN 2026", "Curso Python", "ENEM 2026").
/// Toda matéria pertence a exatamente um ambiente; registros, revisões e
/// aulas herdam o ambiente através da matéria.
class Ambiente {
  /// Ambiente criado pela migração para dados anteriores ao conceito.
  static const geralId = 'geral';

  final String id;
  final String nome;

  /// Índice na paleta categórica fixa (mesma regra das matérias).
  final int corSlot;
  final bool arquivado;
  final DateTime criadoEm;

  const Ambiente({
    required this.id,
    required this.nome,
    this.corSlot = 0,
    this.arquivado = false,
    required this.criadoEm,
  });

  Ambiente copyWith({String? nome, int? corSlot, bool? arquivado}) {
    return Ambiente(
      id: id,
      nome: nome ?? this.nome,
      corSlot: corSlot ?? this.corSlot,
      arquivado: arquivado ?? this.arquivado,
      criadoEm: criadoEm,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'corSlot': corSlot,
        'arquivado': arquivado,
        'criadoEm': criadoEm.toIso8601String(),
      };

  factory Ambiente.fromJson(Map<String, dynamic> json) => Ambiente(
        id: json['id'] as String,
        nome: json['nome'] as String,
        corSlot: (json['corSlot'] as num?)?.toInt() ?? 0,
        arquivado: json['arquivado'] as bool? ?? false,
        criadoEm: DateTime.parse(json['criadoEm'] as String),
      );
}
