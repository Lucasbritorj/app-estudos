import '../data/models/aula.dart';
import '../data/models/registro_hora.dart';

/// Motor de ritmo de leitura por Aula — cálculo puro, testável.
class AulaService {
  /// Aplica uma sessão de estudo teórico à aula: acumula páginas (teto no
  /// total) e marca conclusão quando paginasLidas >= paginasTotais.
  /// [concluiuAgora] é true SÓ na transição — é o gatilho da cadeia de
  /// revisões; sessões seguintes na aula já concluída não redisparam.
  static ({Aula aula, bool concluiuAgora}) aplicarSessao(
      Aula aula, int paginasNaSessao, DateTime dataSessao) {
    if (paginasNaSessao <= 0) return (aula: aula, concluiuAgora: false);
    final lidas =
        (aula.paginasLidas + paginasNaSessao).clamp(0, aula.paginasTotais);
    final completou = aula.paginasTotais > 0 && lidas >= aula.paginasTotais;
    final concluiuAgora = completou && !aula.concluida;
    return (
      aula: aula.copyWith(
        paginasLidas: lidas,
        concluida: aula.concluida || completou,
        dataConclusao: concluiuAgora
            ? DateTime(dataSessao.year, dataSessao.month, dataSessao.day)
            : aula.dataConclusao,
      ),
      concluiuAgora: concluiuAgora,
    );
  }

  /// Ritmo médio da aula: total de páginas / total de horas líquidas das
  /// sessões teóricas da aula. null sem sessão com páginas — nunca inventa.
  static double? ritmoDaAula(List<RegistroHora> registros, String aulaId) {
    var paginas = 0;
    var minutos = 0;
    for (final r in registros) {
      if (r.aulaId != aulaId || r.tipo != TipoEstudo.teoria) continue;
      final p = r.paginasLidas;
      if (p != null && r.minutos > 0) {
        paginas += p;
        minutos += r.minutos;
      }
    }
    if (minutos == 0) return null;
    return paginas / (minutos / 60.0);
  }

  /// Projeção para terminar a aula no ritmo atual; null sem ritmo.
  static int? minutosParaTerminar(
      Aula aula, List<RegistroHora> registros) {
    final ritmo = ritmoDaAula(registros, aula.id);
    if (ritmo == null || ritmo <= 0) return null;
    if (aula.paginasRestantes <= 0) return 0;
    return (aula.paginasRestantes / ritmo * 60).round();
  }

  /// Tempo médio por página (minutos); inverso do ritmo, null sem dados.
  static double? minutosPorPagina(
      List<RegistroHora> registros, String aulaId) {
    final ritmo = ritmoDaAula(registros, aulaId);
    if (ritmo == null || ritmo <= 0) return null;
    return 60 / ritmo;
  }

  /// Minutos líquidos totais investidos na aula (sessões teóricas).
  static int minutosInvestidos(
      List<RegistroHora> registros, String aulaId) {
    return registros
        .where((r) => r.aulaId == aulaId && r.tipo == TipoEstudo.teoria)
        .fold(0, (soma, r) => soma + r.minutos);
  }
}
