import '../data/models/materia.dart';

/// Diagnóstico do cruzamento Intimidade (1-5) × taxa de acerto.
enum DiagnosticoMateria {
  /// Intimidade alta (>=4) mas acerto < 75%: acha que sabe, não sabe.
  falsoDominio,

  /// Intimidade 1: prioridade de leitura/teoria antes de exercícios.
  teoriaPrioritaria,

  /// Intimidade alta E acerto >= 85%: manter no mínimo, só revisão.
  dominada,

  /// Sem sinal especial: segue o peso do edital.
  regular,
}

/// Cálculos puros do planejamento — geração de ciclo por peso do edital.
class PlanejamentoService {
  /// Cruza intimidade declarada com acerto medido. [taxaAcerto] null
  /// (sem questões registradas) nunca gera falso domínio nem dominada —
  /// diagnóstico exige evidência.
  static DiagnosticoMateria diagnostico(int intimidade, double? taxaAcerto) {
    if (intimidade <= 1) return DiagnosticoMateria.teoriaPrioritaria;
    if (taxaAcerto == null) return DiagnosticoMateria.regular;
    if (intimidade >= 4 && taxaAcerto < 0.75) {
      return DiagnosticoMateria.falsoDominio;
    }
    if (intimidade >= 4 && taxaAcerto >= 0.85) {
      return DiagnosticoMateria.dominada;
    }
    return DiagnosticoMateria.regular;
  }

  /// Multiplicador de carga horária no ciclo, por diagnóstico:
  /// falso domínio +50% (revisão pesada), teoria +30% (base a construir),
  /// dominada -30% (só manutenção), regular 1x.
  static double fatorDeCarga(DiagnosticoMateria diagnostico) =>
      switch (diagnostico) {
        DiagnosticoMateria.falsoDominio => 1.5,
        DiagnosticoMateria.teoriaPrioritaria => 1.3,
        DiagnosticoMateria.dominada => 0.7,
        DiagnosticoMateria.regular => 1.0,
      };

  /// Ciclo ajustado: peso do edital × fator do diagnóstico
  /// (intimidade × acerto por matéria em [taxasPorMateria]).
  static Map<String, int> distribuirAjustado(int minutosTotais,
      List<Materia> materias, Map<String, double?> taxasPorMateria) {
    final ativas = materias.where((m) => !m.arquivada).toList();
    final pesos = <String, double>{
      for (final m in ativas)
        m.id: m.peso *
            fatorDeCarga(diagnostico(m.intimidade, taxasPorMateria[m.id])),
    };
    return _distribuir(minutosTotais, pesos);
  }
  static int totalPlanejado(Map<int, int> minutosPorDiaDaSemana) =>
      minutosPorDiaDaSemana.values.fold(0, (a, b) => a + b);

  /// Minutos planejados no intervalo fechado [de, ate], somando o cronograma
  /// por dia da semana sobre cada dia do período (planejado do mês/ano da
  /// aba "Visão Geral" deriva do cronograma da aba "Cronograma").
  static int planejadoEntre(
      Map<int, int> minutosPorDiaDaSemana, DateTime de, DateTime ate) {
    var ini = DateTime(de.year, de.month, de.day);
    final fim = DateTime(ate.year, ate.month, ate.day);
    if (fim.isBefore(ini)) return 0;

    // Conta ocorrências de cada dia da semana no período.
    final totalDias = fim.difference(ini).inDays + 1;
    final base = totalDias ~/ 7;
    final ocorrencias = <int, int>{for (var d = 1; d <= 7; d++) d: base};
    for (var i = 0; i < totalDias % 7; i++) {
      final dia = DateTime(ini.year, ini.month, ini.day + i).weekday;
      ocorrencias[dia] = ocorrencias[dia]! + 1;
    }
    var total = 0;
    minutosPorDiaDaSemana.forEach((dia, minutos) {
      total += minutos * (ocorrencias[dia] ?? 0);
    });
    return total;
  }

  /// Distribui [minutosTotais] entre matérias ativas proporcional ao peso,
  /// com método do maior resto: a soma distribuída bate exata com o total.
  static Map<String, int> distribuirPorPeso(
      int minutosTotais, List<Materia> materias) {
    final ativas = materias.where((m) => !m.arquivada).toList();
    return _distribuir(minutosTotais, {
      for (final m in ativas) m.id: m.peso.toDouble(),
    });
  }

  /// Fila de estudo: matérias com alvo de horas, ordenadas por prioridade
  /// (peso desc, depois menor intimidade — quem sabe menos vem antes).
  /// ETA acumulada: a semana inteira vai para a matéria da vez; quando ela
  /// fecha, a próxima da fila entra. Matéria sem alvo fica fora da fila.
  /// Alvo pode "estourar" a semana de propósito — a fila mostra em quantas
  /// semanas cada uma fecha no ritmo da meta.
  static List<
      ({
        Materia materia,
        int restanteMinutos,
        double semanasAteConcluir,
        bool concluida,
      })> filaDeEstudo({
    required List<Materia> materias,
    required Map<String, int> feitoPorMateria,
    required int minutosSemanais,
  }) {
    final comAlvo = materias
        .where((m) => !m.arquivada && (m.minutosAlvo ?? 0) > 0)
        .toList()
      ..sort((a, b) {
        final porPeso = b.peso.compareTo(a.peso);
        if (porPeso != 0) return porPeso;
        final porIntimidade = a.intimidade.compareTo(b.intimidade);
        if (porIntimidade != 0) return porIntimidade;
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });

    final fila = <({
      Materia materia,
      int restanteMinutos,
      double semanasAteConcluir,
      bool concluida,
    })>[];
    var acumuladoMinutos = 0;
    for (final materia in comAlvo) {
      final restante = (materia.minutosAlvo! -
              (feitoPorMateria[materia.id] ?? 0))
          .clamp(0, materia.minutosAlvo!);
      acumuladoMinutos += restante;
      fila.add((
        materia: materia,
        restanteMinutos: restante,
        semanasAteConcluir: minutosSemanais <= 0
            ? double.infinity
            : acumuladoMinutos / minutosSemanais,
        concluida: restante == 0,
      ));
    }
    return fila;
  }

  static Map<String, int> _distribuir(
      int minutosTotais, Map<String, double> pesos) {
    final somaPesos = pesos.values.fold(0.0, (soma, p) => soma + p);
    if (minutosTotais <= 0 || pesos.isEmpty || somaPesos <= 0) return {};

    final exatos = <String, double>{
      for (final e in pesos.entries)
        e.key: minutosTotais * e.value / somaPesos,
    };
    final resultado = <String, int>{
      for (final e in exatos.entries) e.key: e.value.floor(),
    };
    var faltam = minutosTotais - resultado.values.fold(0, (a, b) => a + b);

    final porResto = exatos.entries.toList()
      ..sort((a, b) => (b.value - b.value.floor())
          .compareTo(a.value - a.value.floor()));
    for (var i = 0; faltam > 0; i = (i + 1) % porResto.length) {
      resultado[porResto[i].key] = resultado[porResto[i].key]! + 1;
      faltam--;
    }
    return resultado;
  }
}
