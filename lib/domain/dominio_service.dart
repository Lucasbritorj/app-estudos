import 'dart:math';

import '../data/models/registro_hora.dart';

/// Estimativa de domínio por tópico via rating estilo Elo — projeção pura
/// sobre os registros (nada é gravado; tudo deriva dos eventos).
///
/// Modelo: rating em logits começa neutro (0 = 50% esperado contra questão
/// de dificuldade média). Cada sessão com questões puxa o rating na direção
/// do resultado observado; o passo é proporcional à quantidade de questões
/// da sessão (com teto, para uma sessão gigante não dominar o histórico).
/// Evidência recente pesa mais que antiga porque o esperado já incorporou
/// o passado — substitui o proxy de taxa acumulada, que tratava um erro de
/// 6 meses atrás com o mesmo peso de um erro de ontem.
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

  /// Domínio estimado do tópico em [0,1]; null sem questões registradas
  /// (sem dados, sem número inventado).
  static ({double dominio, int questoes, bool confiavel})? dominioDoTopico(
          List<RegistroHora> registros, String topicoId) =>
      _projetar(registros.where((r) => r.topicoId == topicoId));

  /// Mesma projeção agregada na matéria — alimenta o ciclo por utilidade
  /// do planejamento.
  static ({double dominio, int questoes, bool confiavel})? dominioDaMateria(
          List<RegistroHora> registros, String materiaId) =>
      _projetar(registros.where((r) => r.materiaId == materiaId));

  static ({double dominio, int questoes, bool confiavel})? _projetar(
      Iterable<RegistroHora> candidatos) {
    final sessoes = candidatos.where((r) => (r.questoes ?? 0) > 0).toList()
      ..sort((a, b) => a.data.compareTo(b.data));
    if (sessoes.isEmpty) return null;

    var rating = 0.0;
    var totalQuestoes = 0;
    for (final s in sessoes) {
      final observado = (s.acertos ?? 0) / s.questoes!;
      final esperado = _sigmoide(rating);
      final peso =
          min(s.questoes!, questoesPorPassoCheio) / questoesPorPassoCheio;
      rating += ganho * peso * (observado - esperado);
      totalQuestoes += s.questoes!;
    }
    return (
      dominio: _sigmoide(rating),
      questoes: totalQuestoes,
      confiavel: totalQuestoes >= amostraMinima,
    );
  }

  static double _sigmoide(double x) => 1 / (1 + exp(-x));
}
