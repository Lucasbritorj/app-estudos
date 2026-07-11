/// Natureza da sessão: teoria (PDF/leitura) ou prática (questões).
/// Gravada por registro para permitir análises isoladas de tempo.
enum TipoEstudo { teoria, pratica }

/// Registro de sessão de estudo — espelha a aba "Registro de horas":
/// Data, Matéria, Tópico, Tarefa/Aula, Páginas inicial/final, Tempo,
/// Comentário, Páginas lidas, Páginas/hora.
///
/// Convenção assumida (planilha original indisponível): páginas lidas é
/// contagem INCLUSIVA — ler da pág. 10 à 20 = 11 páginas.
class RegistroHora {
  final String id;
  final DateTime data;
  final String materiaId;
  final String? topicoId;

  /// Aula do material em PDF a que a sessão pertence (estudo por aulas).
  final String? aulaId;
  final TipoEstudo tipo;
  final String tarefa;

  /// Minutos líquidos (cronômetro desconta pausas).
  final int minutos;
  final int? paginaInicial;
  final int? paginaFinal;

  /// Sobrescreve o cálculo por intervalo quando informado manualmente.
  final int? paginasLidasManual;
  final String? comentario;

  /// Exercícios feitos na sessão (aba de desempenho da planilha).
  final int? questoes;
  final int? acertos;

  const RegistroHora({
    required this.id,
    required this.data,
    required this.materiaId,
    this.topicoId,
    this.aulaId,
    this.tipo = TipoEstudo.teoria,
    this.tarefa = '',
    required this.minutos,
    this.paginaInicial,
    this.paginaFinal,
    this.paginasLidasManual,
    this.comentario,
    this.questoes,
    this.acertos,
  });

  int? get paginasLidas {
    if (paginasLidasManual != null) return paginasLidasManual;
    if (paginaInicial != null && paginaFinal != null) {
      return paginaFinal! - paginaInicial! + 1;
    }
    return null;
  }

  double? get paginasPorHora {
    final paginas = paginasLidas;
    if (paginas == null || minutos <= 0) return null;
    return paginas / (minutos / 60.0);
  }

  /// Taxa de acerto da sessão (0..1); null sem questões registradas.
  double? get taxaAcerto {
    if (questoes == null || questoes! <= 0 || acertos == null) return null;
    return acertos! / questoes!;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'data': data.toIso8601String(),
        'materiaId': materiaId,
        'topicoId': topicoId,
        'aulaId': aulaId,
        'tipo': tipo.name,
        'tarefa': tarefa,
        'minutos': minutos,
        'paginaInicial': paginaInicial,
        'paginaFinal': paginaFinal,
        'paginasLidasManual': paginasLidasManual,
        'comentario': comentario,
        'questoes': questoes,
        'acertos': acertos,
      };

  factory RegistroHora.fromJson(Map<String, dynamic> json) {
    final questoes = (json['questoes'] as num?)?.toInt();
    // Migração de registros antigos sem tipo: sessão só de questões era
    // prática; qualquer outra, teoria.
    final tipoGravado = json['tipo'] as String?;
    final tipo = tipoGravado != null
        ? (tipoGravado == 'pratica' ? TipoEstudo.pratica : TipoEstudo.teoria)
        : ((questoes ?? 0) > 0 &&
                json['paginaInicial'] == null &&
                json['paginasLidasManual'] == null
            ? TipoEstudo.pratica
            : TipoEstudo.teoria);
    return RegistroHora(
      id: json['id'] as String,
      data: DateTime.parse(json['data'] as String),
      materiaId: json['materiaId'] as String,
      topicoId: json['topicoId'] as String?,
      aulaId: json['aulaId'] as String?,
      tipo: tipo,
      tarefa: json['tarefa'] as String? ?? '',
      minutos: (json['minutos'] as num).toInt(),
      paginaInicial: (json['paginaInicial'] as num?)?.toInt(),
      paginaFinal: (json['paginaFinal'] as num?)?.toInt(),
      paginasLidasManual: (json['paginasLidasManual'] as num?)?.toInt(),
      comentario: json['comentario'] as String?,
      questoes: questoes,
      acertos: (json['acertos'] as num?)?.toInt(),
    );
  }
}
