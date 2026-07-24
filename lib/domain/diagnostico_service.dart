/// Diagnóstico do dia: lê os agregados que o dashboard já calcula e devolve
/// um veredito único — honesto, direto e acionável — sobre o estado real da
/// preparação. A régua é dura de propósito: o objetivo é aprovação, não
/// conforto. Nenhuma frase elogia o que os números não sustentam.
///
/// Puro e determinístico (mesmos inputs → mesmo texto): testável sem Flutter
/// e sem sorteio de frases — a variação vem do ESTADO do usuário, não de RNG.
library;

/// Nível do veredito, do pior para o melhor. `semDados` é neutro: sem massa
/// mínima de registro não há diagnóstico honesto possível.
enum NivelDiagnostico { semDados, critico, atencao, constante, forte }

typedef Diagnostico = ({
  NivelDiagnostico nivel,
  String titulo,
  String mensagem,
  List<String> evidencias,
  String acao,
});

class DiagnosticoService {
  /// Piso para um dia contar como "estudo real" na régua de constância.
  /// Sessões-token de 1 min contam nas horas, mas não enganam o diagnóstico
  /// (mesma filosofia da auditoria de métricas: streak honesto).
  static const pisoMinutosDia = 15;

  /// Janela da régua de constância (dias corridos).
  static const janelaConstancia = 14;

  /// Abaixo disso não há diagnóstico: qualquer veredito seria chute.
  static const minutosMinimosParaDiagnostico = 60;

  static Diagnostico gerar({
    required int totalMinutos,
    required int minutosHoje,
    required int minutosSemana,
    required int metaSemana,
    required int streak,
    required bool streakEmRisco,
    required int atrasadas,
    required int diasEstudados14,
    double? trueRetention,
    double? taxaAcertoGeral,
    double? prontidaoAjustada,
    int? diasAteProva,
    int falsoDominio = 0,
    String? materiaSugerida,
    int deficitMinutos = 0,
  }) {
    if (totalMinutos < minutosMinimosParaDiagnostico) {
      return (
        nivel: NivelDiagnostico.semDados,
        titulo: 'Ainda sem base para diagnóstico',
        mensagem:
            'Menos de uma hora registrada. Nenhum veredito honesto nasce '
            'daqui — registre suas sessões reais por alguns dias e o '
            'diagnóstico começa a valer alguma coisa.',
        evidencias: const [],
        acao: 'Registrar a próxima sessão de estudo (de verdade, no relógio)',
      );
    }

    // ----- Pilares: cada um vota crítico / atenção / ok / forte -------------
    var criticos = 0;
    var atencoes = 0;
    var fortes = 0;
    final evidencias = <String>[];

    // Constância — a variável que melhor separa aprovado de desistente.
    evidencias.add(
      'Constância: $diasEstudados14 de $janelaConstancia dias com estudo '
      'real (≥ $pisoMinutosDia min)',
    );
    if (diasEstudados14 <= 5) {
      criticos++;
    } else if (diasEstudados14 <= 9) {
      atencoes++;
    } else {
      fortes++;
    }

    // Backlog de revisões — atraso aqui é conhecimento pago evaporando.
    if (atrasadas > 0) {
      evidencias.add(
        '$atrasadas ${atrasadas == 1 ? 'revisão atrasada' : 'revisões atrasadas'} '
        'na fila',
      );
      if (atrasadas > 5) {
        criticos++;
      } else {
        atencoes++;
      }
    } else {
      fortes++;
    }

    // Volume vs meta da semana (só quando existe meta).
    double? pctMeta;
    if (metaSemana > 0) {
      pctMeta = minutosSemana / metaSemana;
      evidencias.add(
        'Semana: ${_pct(pctMeta)} da meta '
        '(${_horas(minutosSemana)} de ${_horas(metaSemana)})',
      );
      if (pctMeta < 0.5) {
        criticos++;
      } else if (pctMeta < 0.9) {
        atencoes++;
      } else {
        fortes++;
      }
    }

    // Retenção nas revisões — mede se o que foi estudado está ficando.
    if (trueRetention != null) {
      evidencias.add('Retenção nas revisões: ${_pct(trueRetention)}');
      if (trueRetention < 0.75) {
        criticos++;
      } else if (trueRetention < 0.85) {
        atencoes++;
      } else {
        fortes++;
      }
    }

    // Desempenho geral em questões.
    if (taxaAcertoGeral != null) {
      evidencias.add('Acerto geral em questões: ${_pct(taxaAcertoGeral)}');
      if (taxaAcertoGeral < 0.6) {
        criticos++;
      } else if (taxaAcertoGeral < 0.75) {
        atencoes++;
      } else {
        fortes++;
      }
    }

    if (falsoDominio > 0) {
      atencoes++;
      evidencias.add(
        '$falsoDominio ${falsoDominio == 1 ? 'matéria' : 'matérias'} com '
        'falso domínio (intimidade alta, acerto baixo)',
      );
    }

    // Prova marcada: a régua aperta conforme a data chega.
    if (diasAteProva != null && diasAteProva >= 0 && prontidaoAjustada != null) {
      evidencias.add(
        'Prontidão ajustada: ${_pct(prontidaoAjustada)} a '
        '$diasAteProva ${diasAteProva == 1 ? 'dia' : 'dias'} da prova',
      );
      if (prontidaoAjustada < 0.6 && diasAteProva <= 45) {
        criticos++;
      } else if (prontidaoAjustada < 0.75 && diasAteProva <= 90) {
        atencoes++;
      }
    }

    // ----- Veredito ---------------------------------------------------------
    final NivelDiagnostico nivel;
    if (criticos > 0) {
      nivel = NivelDiagnostico.critico;
    } else if (atencoes > 0) {
      nivel = NivelDiagnostico.atencao;
    } else if (fortes >= 3) {
      nivel = NivelDiagnostico.forte;
    } else {
      nivel = NivelDiagnostico.constante;
    }

    final mensagem = _mensagem(
      nivel: nivel,
      minutosHoje: minutosHoje,
      atrasadas: atrasadas,
      diasEstudados14: diasEstudados14,
      pctMeta: pctMeta,
      streak: streak,
      streakEmRisco: streakEmRisco,
      diasAteProva: diasAteProva,
    );

    final acao = _acao(
      atrasadas: atrasadas,
      materiaSugerida: materiaSugerida,
      deficitMinutos: deficitMinutos,
      trueRetention: trueRetention,
      minutosHoje: minutosHoje,
      streakEmRisco: streakEmRisco,
    );

    return (
      nivel: nivel,
      titulo: switch (nivel) {
        NivelDiagnostico.critico => 'Fora do ritmo — e a conta chegou',
        NivelDiagnostico.atencao => 'No jogo, mas com furos',
        NivelDiagnostico.constante => 'Ritmo constante',
        NivelDiagnostico.forte => 'Ritmo de aprovação',
        NivelDiagnostico.semDados => 'Ainda sem base para diagnóstico',
      },
      mensagem: mensagem,
      evidencias: evidencias,
      acao: acao,
    );
  }

  // ----- Copy: honesto, provocador, sem bajulação e sem humilhação ---------

  static String _mensagem({
    required NivelDiagnostico nivel,
    required int minutosHoje,
    required int atrasadas,
    required int diasEstudados14,
    required double? pctMeta,
    required int streak,
    required bool streakEmRisco,
    required int? diasAteProva,
  }) {
    switch (nivel) {
      case NivelDiagnostico.critico:
        final partes = <String>[];
        if (minutosHoje == 0) {
          partes.add('Hoje ainda está zerado.');
        }
        if (atrasadas > 5) {
          partes.add(
            '$atrasadas revisões atrasadas significam conhecimento que você '
            'já pagou caro para adquirir evaporando em silêncio.',
          );
        }
        if (diasEstudados14 <= 5) {
          partes.add(
            'Estudo real em $diasEstudados14 dos últimos $janelaConstancia '
            'dias não é preparação — é intenção.',
          );
        }
        if (pctMeta != null && pctMeta < 0.5) {
          partes.add('A semana está em ${_pct(pctMeta)} da meta.');
        }
        partes.add(
          'A banca não pergunta se a sua semana foi difícil. Ninguém '
          'constrói aprovação num dia — mas toda reprovação é construída '
          'em dias como hoje. Comece pequeno, agora: a primeira sessão '
          'destrava as outras.',
        );
        return partes.join(' ');

      case NivelDiagnostico.atencao:
        final partes = <String>[
          'Você está no jogo — isso já te separa da maioria. Mas os furos '
          'abaixo são exatamente onde reprovação se esconde.',
        ];
        if (streakEmRisco) {
          partes.add(
            'Seu streak de $streak dias vence hoje: não deixe um dia vazio '
            'cobrar o que custou semanas para construir.',
          );
        }
        if (diasAteProva != null && diasAteProva > 0) {
          partes.add(
            'Faltam $diasAteProva dias. Corrigir furo pequeno agora é '
            'barato; na véspera, é impossível.',
          );
        }
        return partes.join(' ');

      case NivelDiagnostico.constante:
        return 'Ritmo real, sem furo grave — é assim que aprovação se '
            'constrói, um dia repetido de cada vez. O próximo salto não é '
            'estudar mais: é apertar a qualidade (questões, revisão em dia, '
            'constância sem buracos).';

      case NivelDiagnostico.forte:
        return 'Os números sustentam: constância alta, revisões em dia e '
            'desempenho consistente. Isso não é sorte nem talento — é o '
            'método funcionando. O risco agora é o excesso de confiança: '
            'mantenha a régua e deixe o edital ditar o resto.';

      case NivelDiagnostico.semDados:
        return '';
    }
  }

  static String _acao({
    required int atrasadas,
    required String? materiaSugerida,
    required int deficitMinutos,
    required double? trueRetention,
    required int minutosHoje,
    required bool streakEmRisco,
  }) {
    if (atrasadas > 0) {
      return 'Zerar as $atrasadas ${atrasadas == 1 ? 'revisão atrasada' : 'revisões atrasadas'} '
          '— comece pela mais antiga, antes de estudar conteúdo novo';
    }
    if (materiaSugerida != null && deficitMinutos > 0) {
      return 'Estudar $materiaSugerida por ${_horas(deficitMinutos)} '
          '(é o maior déficit do seu ciclo)';
    }
    if (trueRetention != null && trueRetention < 0.85) {
      return 'Fechar as próximas revisões COM questões — retenção só '
          'melhora com recall testado, não com releitura';
    }
    if (minutosHoje == 0 && streakEmRisco) {
      return 'Uma sessão de 25 min hoje protege seu streak — agora';
    }
    return 'Manter o ritmo: registrar a sessão de hoje e fechar as '
        'revisões do dia';
  }

  static String _pct(double v) => '${(v * 100).round()}%';

  static String _horas(int minutos) {
    final h = minutos ~/ 60;
    final m = minutos % 60;
    if (h == 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }
}
