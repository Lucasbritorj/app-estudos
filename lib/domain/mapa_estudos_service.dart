import '../data/models/registro_hora.dart';
import '../data/models/topico.dart';
import 'dominio_service.dart';
import 'stats_service.dart';

enum StatusTopico { naoIniciado, emEstudo, concluido }

/// Status e métricas de um tópico para o Mapa de Estudos — puro, testável.
class MapaEstudosService {
  static StatusTopico statusDe(
      Topico topico, List<RegistroHora> registros) {
    if (topico.concluido) return StatusTopico.concluido;
    final estudado = registros.any((r) => r.topicoId == topico.id);
    return estudado ? StatusTopico.emEstudo : StatusTopico.naoIniciado;
  }

  static int minutosDoTopico(
          List<RegistroHora> registros, String topicoId) =>
      registros
          .where((r) => r.topicoId == topicoId)
          .fold(0, (soma, r) => soma + r.minutos);

  /// Taxa de acerto do tópico; null sem questões registradas.
  static double? taxaDoTopico(
      List<RegistroHora> registros, String topicoId) {
    final d = StatsService.desempenhoPorTopico(registros)[topicoId];
    if (d == null || d.questoes == 0) return null;
    return d.acertos / d.questoes;
  }

  /// Domínio estimado (Elo) do tópico — pondera evidência recente acima da
  /// antiga, diferente da taxa acumulada. Null sem questões registradas.
  static ({double dominio, int questoes, bool confiavel})? dominioDoTopico(
          List<RegistroHora> registros, String topicoId) =>
      DominioService.dominioDoTopico(registros, topicoId);

  // --- Grafo de conhecimento (fronteira de estudo) -------------------------

  /// Domínio confiável a partir do qual um pré-requisito libera dependentes
  /// sem precisar estar marcado como concluído.
  static const dominioLiberacao = 0.6;

  /// Pré-requisito satisfeito: concluído OU domínio confiável >= limiar.
  /// Domínio alto com pouca amostra NÃO libera — liberação exige evidência.
  static bool satisfeito(Topico topico, List<RegistroHora> registros) {
    if (topico.concluido) return true;
    final d = DominioService.dominioDoTopico(registros, topico.id);
    return d != null && d.confiavel && d.dominio >= dominioLiberacao;
  }

  /// Pré-requisitos de [topico] ainda não satisfeitos (vazio = liberado).
  /// Id de tópico apagado é ignorado — nunca trava para sempre.
  static List<Topico> bloqueadoPor(
      Topico topico, List<Topico> todos, List<RegistroHora> registros) {
    final porId = {for (final t in todos) t.id: t};
    return [
      for (final id in topico.prerequisitos)
        if (porId[id] != null && !satisfeito(porId[id]!, registros))
          porId[id]!,
    ];
  }

  /// Fronteira de estudo: tópicos não concluídos com todos os
  /// pré-requisitos satisfeitos, por peso desc (desempate por nome).
  static List<Topico> fronteira(
      List<Topico> topicos, List<RegistroHora> registros) {
    return [
      for (final t in topicos)
        if (!t.concluido && bloqueadoPor(t, topicos, registros).isEmpty) t,
    ]..sort((a, b) {
        final porPeso = b.peso.compareTo(a.peso);
        if (porPeso != 0) return porPeso;
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });
  }

  /// True se adicionar [prerequisitoId] como pré-requisito de [topicoId]
  /// criaria ciclo (auto-referência incluída) — o grafo deve seguir DAG.
  static bool criariaCiclo(
      List<Topico> topicos, String topicoId, String prerequisitoId) {
    if (topicoId == prerequisitoId) return true;
    final porId = {for (final t in topicos) t.id: t};
    // Há ciclo se [topicoId] já é alcançável a partir de [prerequisitoId]
    // seguindo as arestas de pré-requisito existentes.
    final visitados = <String>{};
    final pilha = [prerequisitoId];
    while (pilha.isNotEmpty) {
      final atual = pilha.removeLast();
      if (!visitados.add(atual)) continue;
      for (final p in porId[atual]?.prerequisitos ?? const <String>[]) {
        if (p == topicoId) return true;
        pilha.add(p);
      }
    }
    return false;
  }
}
