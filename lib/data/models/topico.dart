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

  /// Arestas de dependência do grafo de conhecimento: ids de tópicos que
  /// precisam estar dominados/concluídos antes deste. O grafo deve ser um
  /// DAG — validar com MapaEstudosService.criariaCiclo antes de adicionar.
  final List<String> prerequisitos;

  const Topico({
    required this.id,
    required this.materiaId,
    this.parentId,
    required this.nome,
    this.peso = 1,
    this.concluido = false,
    this.notas = '',
    this.prerequisitos = const [],
  });

  Topico copyWith({
    String? nome,
    int? peso,
    bool? concluido,
    String? parentId,
    /// Promove a tópico raiz. Sem isto, `parentId: null` cai no `??` e mantém
    /// o pai antigo — o que deixaria o filho apontando para um pai excluído
    /// (mesma convenção de `Materia.limparMinutosAlvo`).
    bool limparParent = false,
    String? notas,
    List<String>? prerequisitos,
  }) {
    return Topico(
      id: id,
      materiaId: materiaId,
      parentId: limparParent ? null : (parentId ?? this.parentId),
      nome: nome ?? this.nome,
      peso: peso ?? this.peso,
      concluido: concluido ?? this.concluido,
      notas: notas ?? this.notas,
      prerequisitos: prerequisitos ?? this.prerequisitos,
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
    'prerequisitos': prerequisitos,
  };

  factory Topico.fromJson(Map<String, dynamic> json) {
    // Peso >= 1: mesma invariante de Materia — backup não rebaixa.
    final peso = (json['peso'] as num?)?.toInt() ?? 1;
    return Topico(
      id: json['id'] as String,
      materiaId: json['materiaId'] as String,
      parentId: json['parentId'] as String?,
      nome: json['nome'] as String,
      peso: peso < 1 ? 1 : peso,
      concluido: json['concluido'] as bool? ?? false,
      notas: json['notas'] as String? ?? '',
      prerequisitos: [
        for (final id in json['prerequisitos'] as List? ?? const [])
          id as String,
      ],
    );
  }
}
