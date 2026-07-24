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
  /// Teto de minutos de UMA sessão (16h). Ver clamp na factory.
  static const maxMinutosPorSessao = 16 * 60;

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

  /// Última modificação do registro (metadado de sincronização futura:
  /// resolução last-write-wins). Dados antigos herdam `data`.
  final DateTime atualizadoEm;

  /// Tombstone: quando não-nulo, a sessão foi excluída — o registro fica
  /// no box para um sync futuro propagar a exclusão, mas some das contas.
  final DateTime? excluidoEm;

  const RegistroHora._({
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
    required this.atualizadoEm,
    this.excluidoEm,
  });

  /// Invariantes garantidas na construção — nenhuma via de entrada (form,
  /// import de backup, cálculo) consegue gravar valores impossíveis que
  /// contaminariam o Elo/desempenho: minutos e páginas não-negativos,
  /// questões não-negativas e acertos nunca acima das questões.
  factory RegistroHora({
    required String id,
    required DateTime data,
    required String materiaId,
    String? topicoId,
    String? aulaId,
    TipoEstudo tipo = TipoEstudo.teoria,
    String tarefa = '',
    required int minutos,
    int? paginaInicial,
    int? paginaFinal,
    int? paginasLidasManual,
    String? comentario,
    int? questoes,
    int? acertos,
    DateTime? atualizadoEm,
    DateTime? excluidoEm,
  }) {
    final questoesClamp = questoes == null
        ? null
        : (questoes < 0 ? 0 : questoes);
    // Acerto só existe contra questões; sem questões, não há taxa a apurar.
    final acertosClamp = acertos == null
        ? null
        : (questoesClamp == null ? null : acertos.clamp(0, questoesClamp));
    return RegistroHora._(
      id: id,
      data: data,
      materiaId: materiaId,
      topicoId: topicoId,
      aulaId: aulaId,
      tipo: tipo,
      tarefa: tarefa,
      // Teto de sanidade (M-09): sem ele um registro de 999999 min dava ~1M
      // de XP e todas as badges de horas de uma vez. 16h é o limite físico
      // plausível de UMA sessão; acima disso é erro de digitação ou fraude.
      minutos: minutos < 0 ? 0 : (minutos > maxMinutosPorSessao
          ? maxMinutosPorSessao
          : minutos),
      // Página negativa não existe — vira null para não contaminar
      // paginasLidas/ritmo.
      paginaInicial: (paginaInicial != null && paginaInicial < 0)
          ? null
          : paginaInicial,
      paginaFinal: (paginaFinal != null && paginaFinal < 0)
          ? null
          : paginaFinal,
      paginasLidasManual: paginasLidasManual == null
          ? null
          : (paginasLidasManual < 0 ? 0 : paginasLidasManual),
      comentario: comentario,
      questoes: questoesClamp,
      acertos: acertosClamp,
      atualizadoEm: atualizadoEm ?? data,
      excluidoEm: excluidoEm,
    );
  }

  /// Cópia com carimbo de modificação — usada pelo repositório ao salvar.
  RegistroHora comAtualizacao(DateTime agora) => _clone(atualizadoEm: agora);

  /// Cópia marcada como excluída (tombstone) — usada pelo repositório.
  RegistroHora comExclusao(DateTime agora) =>
      _clone(atualizadoEm: agora, excluidoEm: agora);

  RegistroHora _clone({required DateTime atualizadoEm, DateTime? excluidoEm}) {
    return RegistroHora._(
      id: id,
      data: data,
      materiaId: materiaId,
      topicoId: topicoId,
      aulaId: aulaId,
      tipo: tipo,
      tarefa: tarefa,
      minutos: minutos,
      paginaInicial: paginaInicial,
      paginaFinal: paginaFinal,
      paginasLidasManual: paginasLidasManual,
      comentario: comentario,
      questoes: questoes,
      acertos: acertos,
      atualizadoEm: atualizadoEm,
      excluidoEm: excluidoEm ?? this.excluidoEm,
    );
  }

  int? get paginasLidas {
    if (paginasLidasManual != null) return paginasLidasManual;
    // Intervalo invertido não é contagem — null (sem dado), nunca negativo.
    if (paginaInicial != null &&
        paginaFinal != null &&
        paginaFinal! >= paginaInicial!) {
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
    'atualizadoEm': atualizadoEm.toIso8601String(),
    'excluidoEm': excluidoEm?.toIso8601String(),
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
      atualizadoEm: DateTime.tryParse(json['atualizadoEm'] as String? ?? ''),
      excluidoEm: DateTime.tryParse(json['excluidoEm'] as String? ?? ''),
    );
  }
}
