/// Parâmetros compartilhados do ciclo por utilidade. Planejamento (alocação
/// real) e Prontidão (projeção até a prova) DEVEM usar os mesmos valores —
/// a promessa "seguindo o ciclo, chega no projetado" vale por construção
/// enquanto ambos lerem daqui.
abstract final class ParametrosCiclo {
  /// Granularidade da mochila gulosa: cada bloco vai para a matéria de
  /// maior utilidade marginal.
  static const blocoMinutos = 15;

  /// Quanto um bloco inteiro eleva o domínio efetivo (satura em 1.0).
  static const passoPorBloco = 0.02;

  /// Piso de utilidade por peso para matéria dominada: garante manutenção
  /// (spaced repetition não deixa memória a zero). Só passa a valer quando
  /// (1 − domínio) cai abaixo dele, ou seja, domínio ≳ 0.92 — matéria
  /// realmente dominada ganha uma fatia mínima em vez de tempo zero.
  static const pisoManutencao = 0.08;
}
