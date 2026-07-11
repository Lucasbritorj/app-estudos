import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';

/// Regras puras da cadeia de revisão espaçada.
class RevisaoService {
  /// Regra da planilha: revisão pendente conta a partir do ÚLTIMO estudo do
  /// tópico. Estudou de novo -> pendentes do tópico são reancoradas em
  /// [dataEstudo] + intervalo. Retorna só as que mudaram de data.
  static List<Revisao> reagendarPorEstudo(
      List<Revisao> revisoes, String topicoId, DateTime dataEstudo) {
    final base = DateTime(dataEstudo.year, dataEstudo.month, dataEstudo.day);
    final alteradas = <Revisao>[];
    for (final r in revisoes) {
      if (r.feita || r.topicoId != topicoId || r.intervaloDias <= 0) continue;
      final nova = DateTime(base.year, base.month, base.day + r.intervaloDias);
      if (nova != DateTime(r.dataAgendada.year, r.dataAgendada.month,
          r.dataAgendada.day)) {
        alteradas.add(r.copyWith(dataAgendada: nova));
      }
    }
    return alteradas;
  }
  /// Próximo intervalo da cadeia (ex.: 7 -> 15 -> 30 -> 60). Retorna o menor
  /// intervalo configurado maior que [atual]; null quando a cadeia termina.
  /// Revisão manual (intervalo 0) entra no início da cadeia.
  static int? proximoIntervalo(List<int> intervalosConfigurados, int atual) {
    final ordenados = [...intervalosConfigurados]..sort();
    for (final intervalo in ordenados) {
      if (intervalo > atual) return intervalo;
    }
    return null;
  }

  /// Taxa de acerto acumulada do tópico (ou da matéria, quando a revisão
  /// não tem tópico); null sem questões registradas.
  static double? taxaAcertoDe(List<RegistroHora> registros,
      {required String materiaId, String? topicoId}) {
    var questoes = 0;
    var acertos = 0;
    for (final r in registros) {
      final pertence =
          topicoId != null ? r.topicoId == topicoId : r.materiaId == materiaId;
      if (!pertence || r.questoes == null || r.questoes! <= 0) continue;
      questoes += r.questoes!;
      acertos += r.acertos ?? 0;
    }
    if (questoes == 0) return null;
    return acertos / questoes;
  }

  /// Passo adaptativo ao concluir uma revisão:
  /// - acerto < 75%: reforço em 3 dias, SEM avançar a cadeia;
  /// - 75% a 84%: repete o intervalo atual (consolida antes de espaçar);
  /// - >= 85% ou sem questões registradas: segue a cadeia normal.
  /// null = cadeia terminou (nada a agendar).
  static ({int dias, int intervalo, bool reforco})? proximoPasso(
      List<int> intervalosConfigurados, int atual, double? taxaAcerto) {
    if (taxaAcerto != null && taxaAcerto < 0.75) {
      return (dias: 3, intervalo: atual, reforco: true);
    }
    if (taxaAcerto != null && taxaAcerto < 0.85 && atual > 0) {
      return (dias: atual, intervalo: atual, reforco: false);
    }
    final proximo = proximoIntervalo(intervalosConfigurados, atual);
    if (proximo == null) return null;
    return (dias: proximo, intervalo: proximo, reforco: false);
  }
}
