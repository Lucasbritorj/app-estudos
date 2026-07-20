import '../data/models/registro_hora.dart';

/// Cálculos puros do dashboard — sem dependência de Flutter, 100% testável.
/// Regras espelham a aba "Visão Geral" da planilha: hoje, ontem, média,
/// máximo, mínimo, streak, agregação semanal e por matéria.
class StatsService {
  static DateTime dataSemHora(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Segunda-feira da semana de [d] (semana de estudo começa na segunda).
  static DateTime inicioDaSemana(DateTime d) {
    final dia = dataSemHora(d);
    return DateTime(dia.year, dia.month, dia.day - (dia.weekday - 1));
  }

  static int minutosNoDia(List<RegistroHora> registros, DateTime dia) {
    final alvo = dataSemHora(dia);
    return registros
        .where((r) => dataSemHora(r.data) == alvo)
        .fold(0, (soma, r) => soma + r.minutos);
  }

  /// Soma minutos no intervalo fechado de dias [de, ate].
  static int minutosEntre(
    List<RegistroHora> registros,
    DateTime de,
    DateTime ate,
  ) {
    final ini = dataSemHora(de);
    final fim = dataSemHora(ate);
    return registros
        .where((r) {
          final d = dataSemHora(r.data);
          return !d.isBefore(ini) && !d.isAfter(fim);
        })
        .fold(0, (soma, r) => soma + r.minutos);
  }

  static int minutosNaSemana(List<RegistroHora> registros, DateTime hoje) {
    final ini = inicioDaSemana(hoje);
    return minutosEntre(
      registros,
      ini,
      DateTime(ini.year, ini.month, ini.day + 6),
    );
  }

  static int minutosNoMes(List<RegistroHora> registros, DateTime ref) =>
      minutosEntre(
        registros,
        DateTime(ref.year, ref.month, 1),
        DateTime(ref.year, ref.month + 1, 0),
      );

  static int minutosNoAno(List<RegistroHora> registros, int ano) =>
      minutosEntre(registros, DateTime(ano, 1, 1), DateTime(ano, 12, 31));

  /// Horas acumuladas por ano (aba "Visão Geral": 2024..2032 + total).
  /// Só anos com registro, em ordem crescente.
  static Map<int, int> minutosPorAno(List<RegistroHora> registros) {
    final porAno = <int, int>{};
    for (final r in registros) {
      porAno[r.data.year] = (porAno[r.data.year] ?? 0) + r.minutos;
    }
    final anos = porAno.keys.toList()..sort();
    return {for (final ano in anos) ano: porAno[ano]!};
  }

  /// Projeção de minutos até 31/12 (aba "Cálculos"): total do ano até hoje
  /// + ritmo recente × dias restantes. Ritmo recente = média diária dos
  /// últimos 28 dias corridos (dias sem estudo contam como zero).
  static int projecaoAno(List<RegistroHora> registros, DateTime hoje) {
    final h = dataSemHora(hoje);
    final totalAno = minutosEntre(registros, DateTime(h.year, 1, 1), h);
    const janela = 28;
    final inicioJanela = DateTime(h.year, h.month, h.day - (janela - 1));
    final minutosJanela = minutosEntre(registros, inicioJanela, h);
    final ritmoDiario = minutosJanela / janela;
    final diasRestantes = DateTime(h.year, 12, 31).difference(h).inDays;
    return totalAno + (ritmoDiario * diasRestantes).round();
  }

  static Map<String, int> minutosPorMateria(
    List<RegistroHora> registros, {
    DateTime? de,
    DateTime? ate,
  }) {
    final resultado = <String, int>{};
    for (final r in registros) {
      final d = dataSemHora(r.data);
      if (de != null && d.isBefore(dataSemHora(de))) continue;
      if (ate != null && d.isAfter(dataSemHora(ate))) continue;
      resultado[r.materiaId] = (resultado[r.materiaId] ?? 0) + r.minutos;
    }
    return resultado;
  }

  /// Dias consecutivos com pelo menos um registro, contando para trás.
  /// Hoje ainda sem registro não zera o streak — conta a partir de ontem.
  static int streakAtual(List<RegistroHora> registros, DateTime hoje) {
    final dias = registros.map((r) => dataSemHora(r.data)).toSet();
    var d = dataSemHora(hoje);
    if (!dias.contains(d)) {
      d = DateTime(d.year, d.month, d.day - 1);
    }
    var streak = 0;
    while (dias.contains(d)) {
      streak++;
      d = DateTime(d.year, d.month, d.day - 1);
    }
    return streak;
  }

  /// Maior sequência de dias consecutivos de estudo em TODO o histórico
  /// (recorde pessoal). Base de gamificação monótona: a conquista deriva do
  /// pico, então perder o streak atual nunca rebaixa o XP nem revoga badge —
  /// e continua 100% derivado dos registros (nada persistido).
  static int streakPico(List<RegistroHora> registros) {
    final dias = registros.map((r) => dataSemHora(r.data)).toSet();
    var pico = 0;
    for (final d in dias) {
      // Só conta a partir do início de um run (dia sem antecessor no set).
      if (dias.contains(DateTime(d.year, d.month, d.day - 1))) continue;
      var run = 0;
      var atual = d;
      while (dias.contains(atual)) {
        run++;
        atual = DateTime(atual.year, atual.month, atual.day + 1);
      }
      if (run > pico) pico = run;
    }
    return pico;
  }

  /// Dias de estudo exigidos na semana ANTERIOR para ganhar 1 congelamento.
  static const metaDiasParaCongelamento = 5;

  /// Streak com congelamento e recuperação — 100% derivado, como o resto.
  ///
  /// Regras (punição suave, retorno rápido):
  /// - Congelamento: um dia sem estudo NÃO quebra o streak se a semana
  ///   anterior (seg-dom) teve >= [metaDiasSemana] dias de estudo. Máximo de
  ///   1 congelamento por semana-calendário; dia congelado não soma [dias].
  /// - Recuperação 24h: quebrou por exatamente 1 dia (não congelável) e
  ///   voltou no dia seguinte → metade do streak perdido vira [recuperados]
  ///   (bônus de XP; o contador exibido recomeça mesmo).
  /// - [emRisco]: streak vivo mas hoje ainda sem registro — a chama treme.
  static ({int dias, int congelados, int recuperados, bool emRisco})
  streakDetalhado(
    List<RegistroHora> registros,
    DateTime hoje, {
    int metaDiasSemana = metaDiasParaCongelamento,
  }) {
    final s = _streakCompleto(registros, hoje, metaDiasSemana);
    return (
      dias: s.dias,
      congelados: s.diasCongelados.length,
      recuperados: s.recuperados,
      emRisco: s.emRisco,
    );
  }

  /// Datas exatas dos dias congelados do streak atual — o heatmap de
  /// constância marca o dia protegido em vez de deixá-lo vazio.
  static Set<DateTime> diasCongeladosDoStreak(
    List<RegistroHora> registros,
    DateTime hoje, {
    int metaDiasSemana = metaDiasParaCongelamento,
  }) => _streakCompleto(registros, hoje, metaDiasSemana).diasCongelados;

  /// Total de minutos por dia (datas truncadas) — base do heatmap.
  static Map<DateTime, int> minutosPorDia(List<RegistroHora> registros) {
    final porDia = <DateTime, int>{};
    for (final r in registros) {
      final d = dataSemHora(r.data);
      porDia[d] = (porDia[d] ?? 0) + r.minutos;
    }
    return porDia;
  }

  static ({
    int dias,
    Set<DateTime> diasCongelados,
    int recuperados,
    bool emRisco,
  })
  _streakCompleto(
    List<RegistroHora> registros,
    DateTime hoje,
    int metaDiasSemana,
  ) {
    final dias = registros.map((r) => dataSemHora(r.data)).toSet();
    final h = dataSemHora(hoje);
    final temHoje = dias.contains(h);

    DateTime anterior(DateTime d) => DateTime(d.year, d.month, d.day - 1);

    int diasNaSemana(DateTime inicioSemana) {
      var c = 0;
      for (var i = 0; i < 7; i++) {
        final d = DateTime(
          inicioSemana.year,
          inicioSemana.month,
          inicioSemana.day + i,
        );
        if (dias.contains(d)) c++;
      }
      return c;
    }

    var d = temHoje ? h : anterior(h);
    var streak = 0;
    final diasCongelados = <DateTime>{};
    final congeladoNaSemana = <DateTime>{};

    while (true) {
      if (dias.contains(d)) {
        streak++;
        d = anterior(d);
        continue;
      }
      final semana = inicioDaSemana(d);
      final semanaAnterior = DateTime(
        semana.year,
        semana.month,
        semana.day - 7,
      );
      final podeCongelar =
          !congeladoNaSemana.contains(semana) &&
          diasNaSemana(semanaAnterior) >= metaDiasSemana;
      if (podeCongelar) {
        congeladoNaSemana.add(semana);
        diasCongelados.add(d);
        d = anterior(d);
        continue;
      }
      break;
    }

    // Recuperação: o dia que quebrou (d) é único — logo antes dele havia
    // um run anterior. Metade dele volta como bônus, estável entre dias.
    var recuperados = 0;
    if (streak > 0) {
      final antesDoGap = anterior(d);
      if (dias.contains(antesDoGap)) {
        var runAnterior = 0;
        var p = antesDoGap;
        while (dias.contains(p)) {
          runAnterior++;
          p = anterior(p);
        }
        recuperados = runAnterior ~/ 2;
      }
    }

    return (
      dias: streak,
      diasCongelados: diasCongelados,
      recuperados: recuperados,
      emRisco: streak > 0 && !temHoje,
    );
  }

  /// Média/máximo/mínimo de minutos considerando apenas dias COM registro.
  static ({int media, int maximo, int minimo}) resumoDiario(
    List<RegistroHora> registros,
  ) {
    if (registros.isEmpty) return (media: 0, maximo: 0, minimo: 0);
    final porDia = <DateTime, int>{};
    for (final r in registros) {
      final d = dataSemHora(r.data);
      porDia[d] = (porDia[d] ?? 0) + r.minutos;
    }
    final valores = porDia.values.toList();
    final total = valores.fold(0, (a, b) => a + b);
    valores.sort();
    return (
      media: (total / valores.length).round(),
      maximo: valores.last,
      minimo: valores.first,
    );
  }

  /// Série cronológica dos últimos [dias] dias (inclui hoje), para gráfico
  /// de linha. Dias sem estudo entram como 0.
  static List<({DateTime dia, int minutos})> serieDiaria(
    List<RegistroHora> registros,
    DateTime hoje,
    int dias,
  ) {
    final fim = dataSemHora(hoje);
    final porDia = <DateTime, int>{};
    for (final r in registros) {
      final d = dataSemHora(r.data);
      porDia[d] = (porDia[d] ?? 0) + r.minutos;
    }
    return List.generate(dias, (i) {
      final d = DateTime(fim.year, fim.month, fim.day - (dias - 1 - i));
      return (dia: d, minutos: porDia[d] ?? 0);
    });
  }

  /// Minutos acumulados por dia da semana (1=segunda .. 7=domingo).
  /// Base do ranking "dia em que você mais estuda".
  static Map<int, int> minutosPorDiaSemana(List<RegistroHora> registros) {
    final resultado = <int, int>{};
    for (final r in registros) {
      resultado[r.data.weekday] = (resultado[r.data.weekday] ?? 0) + r.minutos;
    }
    return resultado;
  }

  /// Questões e acertos acumulados por matéria (só registros com questões).
  static Map<String, ({int questoes, int acertos})> desempenhoPorMateria(
    List<RegistroHora> registros,
  ) {
    final resultado = <String, ({int questoes, int acertos})>{};
    for (final r in registros) {
      if (r.questoes == null || r.questoes! <= 0) continue;
      final atual = resultado[r.materiaId] ?? (questoes: 0, acertos: 0);
      resultado[r.materiaId] = (
        questoes: atual.questoes + r.questoes!,
        acertos: atual.acertos + (r.acertos ?? 0),
      );
    }
    return resultado;
  }

  /// Minutos líquidos separados por natureza da sessão (teoria vs prática)
  /// — base das análises isoladas de tempo.
  static ({int teoria, int pratica}) minutosPorTipo(
    List<RegistroHora> registros,
  ) {
    var teoria = 0;
    var pratica = 0;
    for (final r in registros) {
      if (r.tipo == TipoEstudo.pratica) {
        pratica += r.minutos;
      } else {
        teoria += r.minutos;
      }
    }
    return (teoria: teoria, pratica: pratica);
  }

  /// Questões e acertos acumulados por tópico (só registros com questões
  /// E tópico). Base do Mapa de Estudos.
  static Map<String, ({int questoes, int acertos})> desempenhoPorTopico(
    List<RegistroHora> registros,
  ) {
    final resultado = <String, ({int questoes, int acertos})>{};
    for (final r in registros) {
      final topico = r.topicoId;
      if (topico == null || r.questoes == null || r.questoes! <= 0) continue;
      final atual = resultado[topico] ?? (questoes: 0, acertos: 0);
      resultado[topico] = (
        questoes: atual.questoes + r.questoes!,
        acertos: atual.acertos + (r.acertos ?? 0),
      );
    }
    return resultado;
  }

  /// Taxa de acerto geral ponderada; null sem questões registradas.
  static double? taxaAcertoGeral(List<RegistroHora> registros) {
    var questoes = 0;
    var acertos = 0;
    for (final r in registros) {
      if (r.questoes == null || r.questoes! <= 0) continue;
      questoes += r.questoes!;
      acertos += r.acertos ?? 0;
    }
    if (questoes == 0) return null;
    return acertos / questoes;
  }

  /// Ritmo agregado: total de páginas / total de horas, só sobre registros
  /// com páginas informadas (média ponderada, igual à planilha).
  static double? paginasPorHoraGeral(
    List<RegistroHora> registros, {
    String? materiaId,
  }) {
    var paginas = 0;
    var minutos = 0;
    for (final r in registros) {
      if (materiaId != null && r.materiaId != materiaId) continue;
      final p = r.paginasLidas;
      if (p != null && r.minutos > 0) {
        paginas += p;
        minutos += r.minutos;
      }
    }
    if (minutos == 0) return null;
    return paginas / (minutos / 60.0);
  }
}
