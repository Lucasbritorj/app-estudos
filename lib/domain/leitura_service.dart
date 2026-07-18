import '../data/models/leitura.dart';

/// Gerador de divisões de leitura — cálculo puro, testável.
class LeituraService {
  /// Divide o intervalo fechado [inicio, fim] em [partes] blocos contíguos
  /// de tamanhos equilibrados (diferença máxima de 1 página; as primeiras
  /// partes ficam com a página extra).
  static List<({int inicio, int fim})> dividir(
    int inicio,
    int fim,
    int partes,
  ) {
    final total = fim - inicio + 1;
    if (total <= 0 || partes <= 0) return const [];
    final n = partes > total ? total : partes;
    final base = total ~/ n;
    final resto = total % n;

    final blocos = <({int inicio, int fim})>[];
    var cursor = inicio;
    for (var i = 0; i < n; i++) {
      final tamanho = base + (i < resto ? 1 : 0);
      blocos.add((inicio: cursor, fim: cursor + tamanho - 1));
      cursor += tamanho;
    }
    return blocos;
  }

  static int paginasConcluidas(Leitura leitura) {
    final blocos = dividir(
      leitura.paginaInicio,
      leitura.paginaFim,
      leitura.partes,
    );
    var paginas = 0;
    for (var i = 0; i < blocos.length; i++) {
      if (i < leitura.partesConcluidas.length && leitura.partesConcluidas[i]) {
        paginas += blocos[i].fim - blocos[i].inicio + 1;
      }
    }
    return paginas;
  }

  static double progresso(Leitura leitura) => leitura.totalPaginas == 0
      ? 0
      : paginasConcluidas(leitura) / leitura.totalPaginas;

  /// Páginas ainda não concluídas nas leituras da matéria.
  static int paginasRestantesDaMateria(
    List<Leitura> leituras,
    String materiaId,
  ) {
    var restantes = 0;
    for (final l in leituras) {
      if (l.materiaId != materiaId) continue;
      restantes += l.totalPaginas - paginasConcluidas(l);
    }
    return restantes;
  }

  /// Progresso agregado (0..1) das leituras da matéria; null sem leituras.
  static double? progressoDaMateria(List<Leitura> leituras, String materiaId) {
    var total = 0;
    var feitas = 0;
    for (final l in leituras) {
      if (l.materiaId != materiaId) continue;
      total += l.totalPaginas;
      feitas += paginasConcluidas(l);
    }
    if (total == 0) return null;
    return feitas / total;
  }

  /// Projeção da planilha: páginas restantes ÷ ritmo (pág/h líquida) =
  /// minutos para terminar. null sem ritmo medido — nunca inventa valor.
  static int? minutosParaTerminar(
    int paginasRestantes,
    double? paginasPorHora,
  ) {
    if (paginasPorHora == null || paginasPorHora <= 0) return null;
    if (paginasRestantes <= 0) return 0;
    return (paginasRestantes / paginasPorHora * 60).round();
  }
}
