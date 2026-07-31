import 'bancas.dart';

/// Origem da questão errada — de onde ela entrou no caderno.
enum OrigemQuestao { manual, simulado, sessao }

/// Uma questão que o candidato errou, guardada para refazer.
///
/// O app já contava acertos/questões por sessão, mas contagem não ensina: o
/// que ensina é reencontrar a MESMA questão dias depois e ver se o erro
/// persiste. Esta é a unidade do caderno de erros — a prática de estudo com
/// maior retorno por hora em concurso, porque ataca exatamente o conjunto de
/// itens que já se provou fora de domínio.
///
/// O agendamento reusa o motor FSRS-lite das revisões (mesma curva, mesmo
/// teto), com o estado viajando gravado na própria questão. Errar de novo
/// derruba a estabilidade e traz a questão de volta rápido; acertar espaça.
class QuestaoErrada {
  /// Acertos consecutivos que aposentam a questão do caderno. Dois em datas
  /// diferentes: um acerto isolado pode ser sorte em item de 5 alternativas
  /// (20% no chute), dois espaçados já são evidência de domínio.
  static const acertosParaDominar = 2;

  final String id;
  final String materiaId;
  final String? topicoId;

  /// Enunciado (ou resumo dele). É o corpo da questão: sem isso o caderno
  /// vira outra contagem.
  final String enunciado;

  /// O que o candidato marcou e qual era a correta — opcionais porque muita
  /// questão de concurso é certo/errado ou o candidato só quer o enunciado.
  final String? respostaMarcada;
  final String? respostaCorreta;

  /// Por que errou (não sabia / interpretei mal / troquei conceito / chutei).
  /// Campo mais valioso do caderno: o padrão do erro é o que corrige a rota.
  final String comentario;

  final String? banca;
  final int? ano;
  final String? orgao;

  final OrigemQuestao origem;

  /// Simulado que originou a questão, quando veio de uma prova executada.
  final String? simuladoId;

  final DateTime criadaEm;

  /// Quando a questão volta para a fila. Data (sem hora).
  final DateTime proximaTentativa;

  /// Tentativas de refazer, na ordem (true = acertou).
  final List<bool> tentativas;

  /// Estado FSRS-lite herdado da última tentativa (ver RevisaoService).
  final double? estabilidade;
  final double? dificuldade;

  /// Aposentada do caderno: dominada ([acertosParaDominar] acertos seguidos)
  /// ou arquivada à mão. Sai da fila mas fica no histórico e nas estatísticas.
  final bool arquivada;

  /// Tem foto do enunciado anexada (F1). Só a flag — os BYTES moram num box
  /// Hive separado (`HiveBoxes.anexos`, ver `AnexosQuestaoRepositorio`),
  /// nunca aqui: esta classe é relida inteira a cada rebuild de provider
  /// (fila do dia, ranking, estatísticas todos observam `state` completo),
  /// e uma foto — mesmo comprimida — pesa ordens de grandeza mais que
  /// qualquer outro campo somado.
  ///
  /// Optou-se por `bool` em vez de `String? anexoId`: a chave do box de
  /// anexos É o `id` desta questão (contrato de 1 anexo por questão), então
  /// um id à parte só duplicaria esse mesmo valor sob outro nome — mais
  /// bytes no backup JSON e um jeito a mais de os dois campos dessincronizar
  /// (ex.: `anexoId` sobrevivendo a uma migração que esqueceu de zerá-lo).
  final bool temAnexo;

  const QuestaoErrada._({
    required this.id,
    required this.materiaId,
    this.topicoId,
    required this.enunciado,
    this.respostaMarcada,
    this.respostaCorreta,
    this.comentario = '',
    this.banca,
    this.ano,
    this.orgao,
    this.origem = OrigemQuestao.manual,
    this.simuladoId,
    required this.criadaEm,
    required this.proximaTentativa,
    this.tentativas = const [],
    this.estabilidade,
    this.dificuldade,
    this.arquivada = false,
    this.temAnexo = false,
  });

  /// Invariantes na borda (mesma filosofia de [RegistroHora]): ano de prova
  /// plausível, enunciado sem espaço solto, banca normalizada, datas sem hora.
  factory QuestaoErrada({
    required String id,
    required String materiaId,
    String? topicoId,
    required String enunciado,
    String? respostaMarcada,
    String? respostaCorreta,
    String comentario = '',
    String? banca,
    int? ano,
    String? orgao,
    OrigemQuestao origem = OrigemQuestao.manual,
    String? simuladoId,
    required DateTime criadaEm,
    DateTime? proximaTentativa,
    List<bool> tentativas = const [],
    double? estabilidade,
    double? dificuldade,
    bool arquivada = false,
    bool temAnexo = false,
  }) {
    DateTime dia(DateTime d) => DateTime(d.year, d.month, d.day);
    final criada = dia(criadaEm);
    return QuestaoErrada._(
      id: id,
      materiaId: materiaId,
      topicoId: topicoId,
      enunciado: enunciado.trim(),
      respostaMarcada: _ouNull(respostaMarcada),
      respostaCorreta: _ouNull(respostaCorreta),
      comentario: comentario.trim(),
      banca: Bancas.normalizar(banca),
      // 1990-2100: fora disso é digitação errada e sujaria filtro por ano.
      ano: (ano != null && ano >= 1990 && ano <= 2100) ? ano : null,
      orgao: _ouNull(orgao),
      origem: origem,
      simuladoId: simuladoId,
      criadaEm: criada,
      // Nasce na fila de hoje: errou agora, refaz hoje ou amanhã.
      proximaTentativa: dia(proximaTentativa ?? criadaEm),
      tentativas: List.unmodifiable(tentativas),
      estabilidade: (estabilidade != null && estabilidade.isFinite && estabilidade > 0)
          ? estabilidade
          : null,
      dificuldade: (dificuldade != null && dificuldade.isFinite)
          ? dificuldade.clamp(1.0, 10.0).toDouble()
          : null,
      arquivada: arquivada,
      temAnexo: temAnexo,
    );
  }

  static String? _ouNull(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Acertos consecutivos ao final da lista de tentativas.
  int get acertosSeguidos {
    var n = 0;
    for (final acertou in tentativas.reversed) {
      if (!acertou) break;
      n++;
    }
    return n;
  }

  int get totalTentativas => tentativas.length;
  int get totalAcertos => tentativas.where((t) => t).length;

  /// Taxa de acerto ao refazer; null enquanto nunca foi refeita.
  double? get taxaRefazendo =>
      tentativas.isEmpty ? null : totalAcertos / tentativas.length;

  /// Já vencida (fila de hoje) e ainda ativa.
  bool venceEm(DateTime hoje) {
    if (arquivada) return false;
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    return !proximaTentativa.isAfter(h);
  }

  QuestaoErrada copyWith({
    String? materiaId,
    String? topicoId,
    bool limparTopico = false,
    String? enunciado,
    String? respostaMarcada,
    String? respostaCorreta,
    String? comentario,
    String? banca,
    int? ano,
    /// Apaga o ano preenchido. Sem isto, `ano: null` cairia no `??` e
    /// manteria o valor antigo — `ano` é `int?` e o dialog manda `null`
    /// tanto para "não mexi" quanto para "apaguei o campo", exatamente a
    /// mesma ambiguidade que `Materia.limparMinutosAlvo`,
    /// `Topico.limparParent` e `Ambiente.limparDataProva` resolvem para os
    /// respectivos campos opcionais.
    bool limparAno = false,
    String? orgao,
    DateTime? proximaTentativa,
    List<bool>? tentativas,
    double? estabilidade,
    double? dificuldade,
    bool? arquivada,
    bool? temAnexo,
  }) => QuestaoErrada(
    id: id,
    materiaId: materiaId ?? this.materiaId,
    topicoId: limparTopico ? null : (topicoId ?? this.topicoId),
    enunciado: enunciado ?? this.enunciado,
    respostaMarcada: respostaMarcada ?? this.respostaMarcada,
    respostaCorreta: respostaCorreta ?? this.respostaCorreta,
    comentario: comentario ?? this.comentario,
    banca: banca ?? this.banca,
    ano: limparAno ? null : (ano ?? this.ano),
    orgao: orgao ?? this.orgao,
    origem: origem,
    simuladoId: simuladoId,
    criadaEm: criadaEm,
    proximaTentativa: proximaTentativa ?? this.proximaTentativa,
    tentativas: tentativas ?? this.tentativas,
    estabilidade: estabilidade ?? this.estabilidade,
    dificuldade: dificuldade ?? this.dificuldade,
    arquivada: arquivada ?? this.arquivada,
    temAnexo: temAnexo ?? this.temAnexo,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'materiaId': materiaId,
    'topicoId': topicoId,
    'enunciado': enunciado,
    'respostaMarcada': respostaMarcada,
    'respostaCorreta': respostaCorreta,
    'comentario': comentario,
    'banca': banca,
    'ano': ano,
    'orgao': orgao,
    'origem': origem.name,
    'simuladoId': simuladoId,
    'criadaEm': criadaEm.toIso8601String(),
    'proximaTentativa': proximaTentativa.toIso8601String(),
    'tentativas': tentativas,
    'estabilidade': estabilidade,
    'dificuldade': dificuldade,
    'arquivada': arquivada,
    'temAnexo': temAnexo,
  };

  factory QuestaoErrada.fromJson(Map<String, dynamic> json) => QuestaoErrada(
    id: json['id'] as String,
    materiaId: json['materiaId'] as String,
    topicoId: json['topicoId'] as String?,
    enunciado: json['enunciado'] as String? ?? '',
    respostaMarcada: json['respostaMarcada'] as String?,
    respostaCorreta: json['respostaCorreta'] as String?,
    comentario: json['comentario'] as String? ?? '',
    banca: json['banca'] as String?,
    ano: (json['ano'] as num?)?.toInt(),
    orgao: json['orgao'] as String?,
    origem:
        OrigemQuestao.values.asNameMap()[json['origem']] ??
        OrigemQuestao.manual,
    simuladoId: json['simuladoId'] as String?,
    criadaEm: DateTime.parse(json['criadaEm'] as String),
    proximaTentativa: json['proximaTentativa'] == null
        ? null
        : DateTime.parse(json['proximaTentativa'] as String),
    tentativas: [
      for (final t in json['tentativas'] as List? ?? const []) t == true,
    ],
    estabilidade: (json['estabilidade'] as num?)?.toDouble(),
    dificuldade: (json['dificuldade'] as num?)?.toDouble(),
    arquivada: json['arquivada'] as bool? ?? false,
    // Backup anterior ao F1 não tem a chave — sem anexo é o default seguro
    // (pior caso: o app acha que a foto sumiu, nunca o contrário).
    temAnexo: json['temAnexo'] as bool? ?? false,
  );
}
