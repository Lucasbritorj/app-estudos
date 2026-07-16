import '../data/models/registro_hora.dart';
import '../data/models/topico.dart';
import 'dominio_service.dart';
import 'stats_service.dart';

enum StatusTopico { naoIniciado, emEstudo, concluido }

/// Métricas pré-computadas de um tópico para o Mapa — calculadas uma vez
/// por matéria (metricasPorTopico), nunca por linha da árvore.
class MetricasTopico {
  final StatusTopico status;
  final int minutos;
  final double? taxa;
  final ({double dominio, int questoes, bool confiavel})? dominio;
  final List<Topico> bloqueadoPor;

  const MetricasTopico({
    required this.status,
    required this.minutos,
    required this.taxa,
    required this.dominio,
    required this.bloqueadoPor,
  });
}

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

  /// Métricas de todos os tópicos de uma matéria numa passada só:
  /// O(registros + tópicos·prerequisitos) em vez de O(tópicos × registros)
  /// do cálculo por linha. [topicos] = tópicos da matéria; [registros] =
  /// lista completa (agrupada internamente por tópico).
  static Map<String, MetricasTopico> metricasPorTopico(
      List<Topico> topicos, List<RegistroHora> registros) {
    final porTopico = <String, List<RegistroHora>>{};
    final minutos = <String, int>{};
    final ids = {for (final t in topicos) t.id};
    for (final r in registros) {
      final id = r.topicoId;
      if (id == null || !ids.contains(id)) continue;
      (porTopico[id] ??= []).add(r);
      minutos[id] = (minutos[id] ?? 0) + r.minutos;
    }

    final dominios = <String, ({double dominio, int questoes, bool confiavel})?>{
      for (final t in topicos)
        t.id: DominioService.dominioDe(porTopico[t.id] ?? const []),
    };

    bool satisfeitoLocal(Topico t) {
      if (t.concluido) return true;
      final d = dominios[t.id];
      return d != null && d.confiavel && d.dominio >= dominioLiberacao;
    }

    final porId = {for (final t in topicos) t.id: t};
    return {
      for (final t in topicos)
        t.id: MetricasTopico(
          status: t.concluido
              ? StatusTopico.concluido
              : (porTopico[t.id]?.isNotEmpty ?? false)
                  ? StatusTopico.emEstudo
                  : StatusTopico.naoIniciado,
          minutos: minutos[t.id] ?? 0,
          taxa: _taxaDe(porTopico[t.id]),
          dominio: dominios[t.id],
          bloqueadoPor: [
            for (final id in t.prerequisitos)
              if (porId[id] != null && !satisfeitoLocal(porId[id]!))
                porId[id]!,
          ],
        ),
    };
  }

  static double? _taxaDe(List<RegistroHora>? sessoes) {
    if (sessoes == null) return null;
    var questoes = 0;
    var acertos = 0;
    for (final r in sessoes) {
      if ((r.questoes ?? 0) <= 0) continue;
      questoes += r.questoes!;
      acertos += r.acertos ?? 0;
    }
    if (questoes == 0) return null;
    return acertos / questoes;
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
