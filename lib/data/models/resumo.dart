/// Página única de resumo por matéria (estilo Obsidian): identificada pela
/// sigla-tag (#DC), texto em markdown-lite (parseNotas) e data da última
/// edição. Páginas do catálogo nascem vazias no seed do boot.
class Resumo {
  /// Sigla-tag e id da página (ex.: 'DC').
  final String sigla;

  /// Nome completo da matéria — aparece no tooltip da tag.
  final String nome;

  /// Conteúdo consolidado (markdown-lite: **b**, ==destaque==, "- ").
  final String texto;

  /// Última edição; null = nunca editado (página seed intocada).
  final DateTime? atualizadoEm;

  /// true quando a página veio do catálogo de concursos.
  final bool doCatalogo;

  const Resumo({
    required this.sigla,
    required this.nome,
    this.texto = '',
    this.atualizadoEm,
    this.doCatalogo = false,
  });

  Resumo copyWith({String? texto, DateTime? atualizadoEm}) => Resumo(
        sigla: sigla,
        nome: nome,
        texto: texto ?? this.texto,
        atualizadoEm: atualizadoEm ?? this.atualizadoEm,
        doCatalogo: doCatalogo,
      );

  Map<String, dynamic> toJson() => {
        'sigla': sigla,
        'nome': nome,
        'texto': texto,
        'atualizadoEm': atualizadoEm?.toIso8601String(),
        'doCatalogo': doCatalogo,
      };

  factory Resumo.fromJson(Map<String, dynamic> json) => Resumo(
        sigla: json['sigla'] as String,
        nome: json['nome'] as String? ?? json['sigla'] as String,
        texto: json['texto'] as String? ?? '',
        atualizadoEm: json['atualizadoEm'] == null
            ? null
            : DateTime.parse(json['atualizadoEm'] as String),
        doCatalogo: json['doCatalogo'] as bool? ?? false,
      );
}
