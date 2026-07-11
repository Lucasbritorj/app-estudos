/// Tópico de uma matéria. Hierarquia via `parentId` (null = raiz).
class Topico {
  final String id;
  final String materiaId;
  final String? parentId;
  final String nome;
  final int peso;
  final bool concluido;

  /// Notas livres do usuário (texto simples).
  final String notas;

  const Topico({
    required this.id,
    required this.materiaId,
    this.parentId,
    required this.nome,
    this.peso = 1,
    this.concluido = false,
    this.notas = '',
  });

  Topico copyWith(
      {String? nome,
      int? peso,
      bool? concluido,
      String? parentId,
      String? notas}) {
    return Topico(
      id: id,
      materiaId: materiaId,
      parentId: parentId ?? this.parentId,
      nome: nome ?? this.nome,
      peso: peso ?? this.peso,
      concluido: concluido ?? this.concluido,
      notas: notas ?? this.notas,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'materiaId': materiaId,
        'parentId': parentId,
        'nome': nome,
        'peso': peso,
        'concluido': concluido,
        'notas': notas,
      };

  factory Topico.fromJson(Map<String, dynamic> json) => Topico(
        id: json['id'] as String,
        materiaId: json['materiaId'] as String,
        parentId: json['parentId'] as String?,
        nome: json['nome'] as String,
        peso: (json['peso'] as num?)?.toInt() ?? 1,
        concluido: json['concluido'] as bool? ?? false,
        notas: json['notas'] as String? ?? '',
      );
}
