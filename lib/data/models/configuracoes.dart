/// Preferências do usuário: intervalos de revisão espaçada, lembretes
/// e meta semanal de estudo (planilha: 30h padrão, configurável).
class Configuracoes {
  final List<int> intervalosRevisao;
  final int horaNotificacao;

  /// Meta semanal em minutos (padrão 30h). Usada quando não há cronograma
  /// por dia da semana; o cronograma, quando preenchido, tem prioridade.
  final int metaSemanalMinutos;

  /// Hora do lembrete diário de estudo (0-23); null = desligado.
  final int? horaLembreteEstudo;

  /// Ambiente selecionado no seletor global; null = visão consolidada
  /// ("Todos os ambientes").
  final String? ambienteAtivoId;

  const Configuracoes({
    this.intervalosRevisao = const [7, 15, 30],
    this.horaNotificacao = 9,
    this.metaSemanalMinutos = 30 * 60,
    this.horaLembreteEstudo,
    this.ambienteAtivoId,
  });

  Configuracoes copyWith(
      {List<int>? intervalosRevisao,
      int? horaNotificacao,
      int? metaSemanalMinutos,
      int? horaLembreteEstudo,
      bool desligarLembreteEstudo = false,
      String? ambienteAtivoId,
      bool limparAmbienteAtivo = false}) {
    return Configuracoes(
      intervalosRevisao: intervalosRevisao ?? this.intervalosRevisao,
      horaNotificacao: horaNotificacao ?? this.horaNotificacao,
      metaSemanalMinutos: metaSemanalMinutos ?? this.metaSemanalMinutos,
      horaLembreteEstudo: desligarLembreteEstudo
          ? null
          : (horaLembreteEstudo ?? this.horaLembreteEstudo),
      ambienteAtivoId: limparAmbienteAtivo
          ? null
          : (ambienteAtivoId ?? this.ambienteAtivoId),
    );
  }

  Map<String, dynamic> toJson() => {
        'intervalosRevisao': intervalosRevisao,
        'horaNotificacao': horaNotificacao,
        'metaSemanalMinutos': metaSemanalMinutos,
        'horaLembreteEstudo': horaLembreteEstudo,
        'ambienteAtivoId': ambienteAtivoId,
      };

  factory Configuracoes.fromJson(Map<String, dynamic> json) => Configuracoes(
        intervalosRevisao: (json['intervalosRevisao'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [7, 15, 30],
        horaNotificacao: (json['horaNotificacao'] as num?)?.toInt() ?? 9,
        metaSemanalMinutos:
            (json['metaSemanalMinutos'] as num?)?.toInt() ?? 30 * 60,
        horaLembreteEstudo: (json['horaLembreteEstudo'] as num?)?.toInt(),
        ambienteAtivoId: json['ambienteAtivoId'] as String?,
      );
}
