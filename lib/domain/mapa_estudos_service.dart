import '../data/models/registro_hora.dart';
import '../data/models/topico.dart';
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
}
