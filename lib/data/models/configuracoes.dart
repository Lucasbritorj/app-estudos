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

  /// Onboarding multi-passo já visto? Falso na primeira execução (e em
  /// backups antigos, que não tinham o campo) — o gate mostra o tour uma vez.
  final bool onboardingConcluido;

  /// Sidebar (tela larga) colapsada em modo só-ícones? Falso por padrão (e em
  /// backups antigos, que não tinham o campo).
  final bool sidebarColapsada;

  /// Minutos creditados a uma revisão concluída COM questões quando o tempo
  /// não é informado. Antes era 0 fixo, o que criava uma sessão fantasma sem
  /// tempo (zerava o "mínimo diário" e inflava a contagem de sessões).
  /// É uma ESTIMATIVA: infla o total de horas em `valor × revisões`. Zero
  /// desliga o crédito e volta ao comportamento antigo.
  final int minutosPadraoRevisao;

  const Configuracoes({
    this.intervalosRevisao = const [7, 15, 30],
    this.horaNotificacao = 9,
    this.metaSemanalMinutos = 30 * 60,
    this.horaLembreteEstudo,
    this.ambienteAtivoId,
    this.onboardingConcluido = false,
    this.sidebarColapsada = false,
    this.minutosPadraoRevisao = 10,
  });

  Configuracoes copyWith({
    List<int>? intervalosRevisao,
    int? horaNotificacao,
    int? metaSemanalMinutos,
    int? horaLembreteEstudo,
    bool desligarLembreteEstudo = false,
    String? ambienteAtivoId,
    bool limparAmbienteAtivo = false,
    bool? onboardingConcluido,
    bool? sidebarColapsada,
    int? minutosPadraoRevisao,
  }) {
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
      onboardingConcluido: onboardingConcluido ?? this.onboardingConcluido,
      sidebarColapsada: sidebarColapsada ?? this.sidebarColapsada,
      minutosPadraoRevisao: minutosPadraoRevisao ?? this.minutosPadraoRevisao,
    );
  }

  Map<String, dynamic> toJson() => {
    'intervalosRevisao': intervalosRevisao,
    'horaNotificacao': horaNotificacao,
    'metaSemanalMinutos': metaSemanalMinutos,
    'horaLembreteEstudo': horaLembreteEstudo,
    'ambienteAtivoId': ambienteAtivoId,
    'onboardingConcluido': onboardingConcluido,
    'sidebarColapsada': sidebarColapsada,
    'minutosPadraoRevisao': minutosPadraoRevisao,
  };

  factory Configuracoes.fromJson(Map<String, dynamic> json) => Configuracoes(
    intervalosRevisao:
        (json['intervalosRevisao'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList() ??
        const [7, 15, 30],
    horaNotificacao: (json['horaNotificacao'] as num?)?.toInt() ?? 9,
    metaSemanalMinutos:
        (json['metaSemanalMinutos'] as num?)?.toInt() ?? 30 * 60,
    horaLembreteEstudo: (json['horaLembreteEstudo'] as num?)?.toInt(),
    ambienteAtivoId: json['ambienteAtivoId'] as String?,
    onboardingConcluido: json['onboardingConcluido'] as bool? ?? false,
    sidebarColapsada: json['sidebarColapsada'] as bool? ?? false,
    // Negativo viraria crédito de tempo negativo; teto de 1h por revisão.
    minutosPadraoRevisao:
        ((json['minutosPadraoRevisao'] as num?)?.toInt() ?? 10).clamp(0, 60),
  );
}
