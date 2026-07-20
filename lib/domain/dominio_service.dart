import 'dart:math';

import '../data/models/registro_hora.dart';

/// Medição Elo de um escopo (tópico/matéria): domínio em [0,1], amostra e
/// se a amostra basta para a medição ser confiável.
typedef MedicaoDominio = ({double dominio, int questoes, bool confiavel});

/// Estimativa de domínio por tópico via rating estilo Elo — projeção pura
/// sobre os registros (nada é gravado; tudo deriva dos eventos).
///
/// Modelo: rating em logits começa neutro (0 = 50% esperado contra questão
/// de dificuldade média). Cada sessão com questões puxa o rating na direção
/// do resultado observado; o passo é proporcional à quantidade de questões
/// da sessão (com teto, para uma sessão gigante não dominar o histórico).
///
/// Recência é TEMPORAL, não só ordinal: entre uma sessão e a próxima o rating
/// regride em direção ao neutro por [meiaVidaDias] (memória esquece com o
/// tempo, não com a contagem de eventos). Uma [referencia] opcional (hoje)
/// aplica o mesmo esquecimento desde a última sessão — matéria não praticada
/// há meses volta a ficar incerta. Antes o modelo só tinha ordem: um erro de
/// 6 meses atrás na mesma posição da sequência pesava igual a um de ontem.
///
/// Nota: como o domínio passa por sigmoide, o corte 0.75/0.85 (régua Nexus)
/// no ESPAÇO DE DOMÍNIO é mais estrito que a mesma taxa de acerto crua — o
/// rating converge para o limiar só assintoticamente com evidência repetida.
class DominioService {
  /// Questões por sessão que contam integralmente no passo (acima disso a
  /// confiança da sessão não cresce mais).
  static const questoesPorPassoCheio = 10;

  /// Ganho do passo — sessão cheia perfeita partindo do neutro move o
  /// domínio ~10 p.p.; 4-5 sessões cheias consistentes levam a ~80%.
  static const ganho = 0.8;

  /// Amostra mínima total para o domínio ser confiável (mesma régua do
  /// InsightsService.amostraMinimaQuestoes).
  static const amostraMinima = 10;

  /// Meia-vida (dias) da recência: a evidência perde metade do peso a cada
  /// [meiaVidaDias] sem prática. Calibrável; 60 dias = ~2 meses.
  static const meiaVidaDias = 60.0;

  static DateTime _dia(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Fator de esquecimento por [dias] decorridos: 0.5^(dias/meiaVida), em
  /// [0,1]. Multiplica o rating (puxa em direção ao neutro 0).
  static double _fatorRecencia(int dias) =>
      dias <= 0 ? 1.0 : pow(0.5, dias / meiaVidaDias).toDouble();

  /// Domínio estimado do tópico em [0,1]; null sem questões registradas
  /// (sem dados, sem número inventado). [referencia] (hoje) aplica o
  /// esquecimento desde a última sessão.
  static ({double dominio, int questoes, bool confiavel})? dominioDoTopico(
    List<RegistroHora> registros,
    String topicoId, {
    DateTime? referencia,
  }) => _projetar(
    registros.where((r) => r.topicoId == topicoId),
    referencia: referencia,
  );

  /// Mesma projeção agregada na matéria — alimenta o ciclo por utilidade
  /// do planejamento.
  static ({double dominio, int questoes, bool confiavel})? dominioDaMateria(
    List<RegistroHora> registros,
    String materiaId, {
    DateTime? referencia,
  }) => _projetar(
    registros.where((r) => r.materiaId == materiaId),
    referencia: referencia,
  );

  /// Projeção Elo de todas as matérias numa passada só: agrupa os registros
  /// por matéria (O(registros)) e projeta cada grupo — substitui o padrão
  /// de re-filtrar a lista inteira por matéria (O(matérias × registros)).
  static Map<String, MedicaoDominio?> dominioPorMateria(
    List<RegistroHora> registros,
    Iterable<String> materiaIds, {
    DateTime? referencia,
  }) {
    final porMateria = <String, List<RegistroHora>>{};
    for (final r in registros) {
      (porMateria[r.materiaId] ??= []).add(r);
    }
    return {
      for (final id in materiaIds)
        id: dominioDe(porMateria[id] ?? const [], referencia: referencia),
    };
  }

  /// Projeção Elo sobre um conjunto de sessões já filtrado — público para
  /// quem agrupa registros uma vez e projeta cada grupo (ex.: métricas do
  /// mapa por matéria) em vez de re-filtrar a lista inteira por tópico.
  static ({double dominio, int questoes, bool confiavel})? dominioDe(
    Iterable<RegistroHora> candidatos, {
    DateTime? referencia,
  }) {
    final sessoes = candidatos.where((r) => (r.questoes ?? 0) > 0).toList()
      ..sort((a, b) => a.data.compareTo(b.data));
    if (sessoes.isEmpty) return null;

    var rating = 0.0;
    var totalQuestoes = 0;
    DateTime? anterior;
    for (final s in sessoes) {
      // Esquecimento entre sessões: o que já estava no rating regride em
      // direção ao neutro conforme o tempo desde a última sessão. É o que
      // faz o recente pesar mais que o antigo no TEMPO, não só na ordem.
      if (anterior != null) {
        rating *= _fatorRecencia(_dia(s.data).difference(_dia(anterior)).inDays);
      }
      // Clamp defensivo: dado importado com acertos > questões não pode
      // empurrar o rating acima do que uma sessão perfeita empurraria.
      final observado = ((s.acertos ?? 0) / s.questoes!).clamp(0.0, 1.0);
      final esperado = _sigmoide(rating);
      final peso =
          min(s.questoes!, questoesPorPassoCheio) / questoesPorPassoCheio;
      rating += ganho * peso * (observado - esperado);
      totalQuestoes += s.questoes!;
      anterior = s.data;
    }
    // Staleness até hoje: matéria não praticada há muito tempo fica menos
    // "sabida" (rating regride ao neutro). Só quando [referencia] é dada.
    if (referencia != null && anterior != null) {
      rating *= _fatorRecencia(_dia(referencia).difference(_dia(anterior)).inDays);
    }
    return (
      dominio: _sigmoide(rating),
      questoes: totalQuestoes,
      confiavel: totalQuestoes >= amostraMinima,
    );
  }

  static ({double dominio, int questoes, bool confiavel})? _projetar(
    Iterable<RegistroHora> candidatos, {
    DateTime? referencia,
  }) => dominioDe(candidatos, referencia: referencia);

  static double _sigmoide(double x) => 1 / (1 + exp(-x));
}
