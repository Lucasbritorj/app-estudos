import 'dart:math';

import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';

/// Regras puras da cadeia de revisão espaçada.
class RevisaoService {
  /// Regra da planilha: revisão pendente conta a partir do ÚLTIMO estudo do
  /// tópico. Estudou de novo -> pendentes do tópico são reancoradas em
  /// [dataEstudo] + intervalo. Retorna só as que mudaram de data.
  static List<Revisao> reagendarPorEstudo(
    List<Revisao> revisoes,
    String topicoId,
    DateTime dataEstudo,
  ) {
    final base = DateTime(dataEstudo.year, dataEstudo.month, dataEstudo.day);
    final alteradas = <Revisao>[];
    for (final r in revisoes) {
      if (r.feita || r.topicoId != topicoId || r.intervaloDias <= 0) continue;
      final nova = DateTime(base.year, base.month, base.day + r.intervaloDias);
      if (nova !=
          DateTime(
            r.dataAgendada.year,
            r.dataAgendada.month,
            r.dataAgendada.day,
          )) {
        alteradas.add(r.copyWith(dataAgendada: nova));
      }
    }
    return alteradas;
  }

  /// Forecast de carga: quantas revisões PENDENTES caem em cada um dos
  /// próximos [dias] dias a partir de [hoje]. Atrasadas (agendadas antes de
  /// hoje) e as de hoje entram no dia 0 — é a fila que o usuário enfrenta
  /// agora. Base do gráfico "o que vem aí" (antecipar picos, evitar backlog).
  static List<({DateTime dia, int quantidade})> forecastCarga(
    List<Revisao> revisoes,
    DateTime hoje, {
    int dias = 30,
  }) {
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    final contagem = <DateTime, int>{};
    for (final r in revisoes) {
      if (r.feita) continue;
      final agendada = DateTime(
        r.dataAgendada.year,
        r.dataAgendada.month,
        r.dataAgendada.day,
      );
      final alvo = agendada.isBefore(base) ? base : agendada;
      final offset = alvo.difference(base).inDays;
      if (offset < 0 || offset >= dias) continue;
      contagem[alvo] = (contagem[alvo] ?? 0) + 1;
    }
    return List.generate(dias, (i) {
      final dia = DateTime(base.year, base.month, base.day + i);
      return (dia: dia, quantidade: contagem[dia] ?? 0);
    });
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

  /// Taxa de acerto das últimas [ultimasSessoes] sessões com questões do
  /// tópico (ou da matéria, quando a revisão não tem tópico); null sem
  /// questões registradas. A janela de recência decide o passo da revisão
  /// pelo desempenho ATUAL — na taxa acumulada, um período ruim de meses
  /// atrás segurava o intervalo para sempre, mesmo recuperado.
  static double? taxaAcertoDe(
    List<RegistroHora> registros, {
    required String materiaId,
    String? topicoId,
    int ultimasSessoes = 10,
  }) {
    final sessoes = [
      for (final r in registros)
        if ((topicoId != null
                ? r.topicoId == topicoId
                : r.materiaId == materiaId) &&
            (r.questoes ?? 0) > 0)
          r,
    ]..sort((a, b) => b.data.compareTo(a.data));

    var questoes = 0;
    var acertos = 0;
    for (final r in sessoes.take(ultimasSessoes)) {
      questoes += r.questoes!;
      acertos += r.acertos ?? 0;
    }
    if (questoes == 0) return null;
    return acertos / questoes;
  }

  // --- FSRS-lite -----------------------------------------------------------
  // Curva de potência do FSRS: R(t) = 1 / (1 + t / (9S)). Em t = S a
  // retrievabilidade é 90% — o intervalo com retenção alvo de 90% é a
  // própria estabilidade, então o próximo intervalo = nova estabilidade.

  static const _dificuldadeInicial = 5.0;

  /// Semente de estabilidade para revisão manual (intervalo 0) sem estado.
  static const _sementeManualDias = 3.0;

  /// Crescimento em condição neutra (dificuldade 5, revisada em dia), ANTES
  /// do freio de estabilidade. Com o freio, a progressão fica sub-geométrica
  /// (ex.: 7→13→~21…), não uma PA geométrica pura que super-espaça.
  static const _crescimentoBase = 0.9;

  /// Freio de estabilidade (equivalente ao w9 do FSRS real): o ganho encolhe
  /// conforme a estabilidade cresce — `crescimento *= S^(-w9)`. Sem ele,
  /// cards já fortes dobravam o intervalo indefinidamente (super-espaçamento).
  static const _freioEstabilidade = 0.15;

  /// Reversão à média da dificuldade: a cada passo D é puxado de volta ao
  /// neutro ([_dificuldadeInicial]). Evita D encravar em 10 (a dinâmica
  /// antiga só somava no lapso/difícil, nunca amortecia).
  static const _taxaReversaoDificuldade = 0.1;

  /// Retenção-alvo padrão (probabilidade de lembrar no vencimento). Em 0.9 o
  /// intervalo é a própria estabilidade; reduzir alonga os intervalos (menos
  /// revisões, mais esquecimento tolerado). Exposto como knob calibrável.
  static const retencaoAlvoPadrao = 0.9;

  /// Intervalo acima disso encerra a cadeia: memória consolidada, tópico
  /// fica só na manutenção do mapa.
  static const tetoDiasFsrs = 120;

  static double _reverterDificuldade(double d) =>
      (d + _taxaReversaoDificuldade * (_dificuldadeInicial - d)).clamp(
        1.0,
        10.0,
      );

  /// Dias de intervalo por unidade de estabilidade para atingir [retencao] na
  /// curva R(t)=1/(1+t/9S): t = 9·S·(1/R − 1). Em R=0.9 dá 1.0 (intervalo=S).
  static double _fatorIntervalo(double retencao) => 9 * (1 / retencao - 1);

  /// Passo adaptativo FSRS-lite ao concluir uma revisão. O estado
  /// (estabilidade em dias, dificuldade 1-10) viaja gravado na própria
  /// revisão; revisão sem estado (antiga ou início de cadeia) usa
  /// [intervaloAtual] como semente — migração transparente.
  ///
  /// Mesma régua de desempenho da cadeia clássica:
  /// - < 75%: lapso — estabilidade cai para 40% (mínimo 1d), reforço curto;
  /// - 75-84%: cresce na metade do ritmo e a dificuldade sobe;
  /// - >= 85% ou sem questões: cresce pleno; revisar perto do esquecimento
  ///   (retrievabilidade baixa) consolida mais — efeito de espaçamento.
  /// null = intervalo estourou [tetoDiasFsrs]: cadeia encerra.
  static ({
    int dias,
    int intervalo,
    bool reforco,
    double estabilidade,
    double dificuldade,
  })?
  proximoPassoFsrs({
    double? estabilidade,
    double? dificuldade,
    required int intervaloAtual,
    int diasDeAtraso = 0,
    required double? taxaAcerto,
    double retencaoAlvo = retencaoAlvoPadrao,
  }) {
    final s =
        estabilidade ??
        (intervaloAtual > 0 ? intervaloAtual.toDouble() : _sementeManualDias);
    final d = ((dificuldade ?? _dificuldadeInicial).clamp(
      1.0,
      10.0,
    )).toDouble();

    // Dias efetivamente decorridos desde o estudo que ancorou a revisão.
    final base = intervaloAtual > 0 ? intervaloAtual : s.round();
    final decorrido = max(1, base + max(0, diasDeAtraso));
    final r = 1 / (1 + decorrido / (9 * s));

    final errou = taxaAcerto != null && taxaAcerto < 0.75;
    final dificil =
        taxaAcerto != null && taxaAcerto >= 0.75 && taxaAcerto < 0.85;

    final double novaS;
    final double novaD;
    if (errou) {
      novaS = max(1.0, s * 0.4);
      novaD = _reverterDificuldade(d + 1.0);
    } else {
      final bonusEsquecimento = 1 + 2.0 * (1 - r);
      final fatorFacilidade = (11 - d) / 6; // dificuldade 5 -> 1.0
      var crescimento = _crescimentoBase * fatorFacilidade * bonusEsquecimento;
      // Freio S^(-w9): ganho de estabilidade encolhe conforme S cresce.
      crescimento *= pow(s, -_freioEstabilidade).toDouble();
      if (dificil) {
        crescimento *= 0.5;
        novaD = _reverterDificuldade(d + 0.5);
      } else {
        novaD = _reverterDificuldade(d - 0.3);
      }
      novaS = s * (1 + crescimento);
    }

    // Intervalo agendado = estabilidade convertida pela retenção-alvo.
    final diasCalculados = (novaS * _fatorIntervalo(retencaoAlvo)).round();
    if (!errou && diasCalculados > tetoDiasFsrs) return null;
    final dias = diasCalculados.clamp(1, tetoDiasFsrs);
    return (
      dias: dias,
      intervalo: dias,
      reforco: errou,
      estabilidade: novaS,
      dificuldade: novaD,
    );
  }
}
