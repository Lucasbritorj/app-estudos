import 'ambiente.dart';
import 'bancas.dart';

/// Item da folha de respostas de uma prova em execução: uma questão, a
/// matéria dela (quando o setup define faixas), a resposta marcada e — só
/// depois de "Finalizar" — o gabarito.
class ItemProva {
  final int numero;
  final String? materiaId;

  /// 'A'..'E' (múltipla escolha) ou 'C'/'E' (certo-errado) — o modelo não
  /// restringe o alfabeto: cada banca tem o seu, então validar a letra aqui
  /// rejeitaria formato legítimo. Normalizada maiúscula e sem espaço, então
  /// 'a', ' A ' e 'A' caem na mesma chave na hora de comparar com o gabarito.
  final String? respostaMarcada;

  /// Preenchido na tela de correção. Item sem gabarito fica de fora da
  /// apuração (ver ProvaService.corrigir) — não é possível saber se ele
  /// acertou ou errou sem a resposta certa.
  final String? gabarito;

  /// Enunciado digitado à mão na correção (opcional). Sem isso,
  /// ProvaService.paraQuestoesErradas gera um rótulo genérico "Questão N —
  /// `<nome da prova>`" pro caderno de erros em vez de descartar a questão
  /// errada.
  final String? enunciado;

  /// Nota livre sobre o erro (por que errou) — copiada pra QuestaoErrada.
  final String comentario;

  const ItemProva._({
    required this.numero,
    this.materiaId,
    this.respostaMarcada,
    this.gabarito,
    this.enunciado,
    this.comentario = '',
  });

  /// Invariantes na borda (M-05): número sempre >= 1 (folha de respostas não
  /// tem questão 0 ou negativa) e respostas/gabarito normalizados
  /// (maiúsculo, sem espaço).
  factory ItemProva({
    required int numero,
    String? materiaId,
    String? respostaMarcada,
    String? gabarito,
    String? enunciado,
    String comentario = '',
  }) {
    return ItemProva._(
      numero: numero < 1 ? 1 : numero,
      materiaId: _ouNull(materiaId),
      respostaMarcada: _normalizarResposta(respostaMarcada),
      gabarito: _normalizarResposta(gabarito),
      enunciado: _ouNull(enunciado),
      comentario: comentario.trim(),
    );
  }

  static String? _ouNull(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static String? _normalizarResposta(String? v) {
    if (v == null) return null;
    final semEspaco = v.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return semEspaco.isEmpty ? null : semEspaco;
  }

  ItemProva copyWith({
    String? materiaId,
    bool limparMateria = false,
    String? respostaMarcada,
    bool limparResposta = false,
    String? gabarito,
    bool limparGabarito = false,
    String? enunciado,
    String? comentario,
  }) => ItemProva(
    numero: numero,
    materiaId: limparMateria ? null : (materiaId ?? this.materiaId),
    respostaMarcada: limparResposta
        ? null
        : (respostaMarcada ?? this.respostaMarcada),
    gabarito: limparGabarito ? null : (gabarito ?? this.gabarito),
    enunciado: enunciado ?? this.enunciado,
    comentario: comentario ?? this.comentario,
  );

  Map<String, dynamic> toJson() => {
    'numero': numero,
    'materiaId': materiaId,
    'respostaMarcada': respostaMarcada,
    'gabarito': gabarito,
    'enunciado': enunciado,
    'comentario': comentario,
  };

  factory ItemProva.fromJson(Map<String, dynamic> json) => ItemProva(
    numero: (json['numero'] as num).toInt(),
    materiaId: json['materiaId'] as String?,
    respostaMarcada: json['respostaMarcada'] as String?,
    gabarito: json['gabarito'] as String?,
    enunciado: json['enunciado'] as String?,
    comentario: json['comentario'] as String? ?? '',
  );
}

/// Prova cronometrada em andamento (ou já finalizada, aguardando correção).
///
/// Persistida num slot único no Hive (ver ExecucaoProvaController em
/// repositorios.dart) igual ao cronômetro: só existe UMA execução ativa por
/// vez — iniciar outra substitui a anterior.
class ExecucaoProva {
  final String id;
  final String nome;
  final String ambienteId;
  final String? banca;

  /// Relógio de parede do início — junto com [duracaoMinutos] define o fim
  /// real da prova. O tempo restante é SEMPRE recalculado por diferença de
  /// datas (nunca por Stopwatch em memória): fechar o app não pausa a
  /// prova, igual um concurso de verdade — ver ProvaService.tempoRestante.
  final DateTime iniciadaEm;

  /// Duração total planejada, em minutos.
  final int duracaoMinutos;
  final List<ItemProva> itens;

  /// Quando o candidato apertou "Finalizar" — null enquanto está rodando.
  /// Trava a folha de respostas e libera a tela de correção.
  final DateTime? finalizadaEm;

  const ExecucaoProva._({
    required this.id,
    required this.nome,
    required this.ambienteId,
    this.banca,
    required this.iniciadaEm,
    required this.duracaoMinutos,
    required this.itens,
    this.finalizadaEm,
  });

  /// Teto de sanidade análogo a RegistroHora.maxMinutosPorSessao — prova
  /// real não passa de 16h corridas.
  static const _duracaoMaximaMinutos = 16 * 60;

  /// Invariantes na borda: duração sempre positiva (sem isso o tempo
  /// restante travaria em zero desde o início — nunca haveria prova pra
  /// fazer) e números de item sempre positivos (garantido pela própria
  /// factory de ItemProva).
  factory ExecucaoProva({
    required String id,
    required String nome,
    String ambienteId = Ambiente.geralId,
    String? banca,
    required DateTime iniciadaEm,
    required int duracaoMinutos,
    List<ItemProva> itens = const [],
    DateTime? finalizadaEm,
  }) {
    final duracao = duracaoMinutos < 1
        ? 1
        : (duracaoMinutos > _duracaoMaximaMinutos
              ? _duracaoMaximaMinutos
              : duracaoMinutos);
    return ExecucaoProva._(
      id: id,
      nome: nome.trim(),
      ambienteId: ambienteId,
      banca: Bancas.normalizar(banca),
      iniciadaEm: iniciadaEm,
      duracaoMinutos: duracao,
      itens: List.unmodifiable(itens),
      finalizadaEm: finalizadaEm,
    );
  }

  /// Momento em que a prova termina pelo relógio, se ninguém finalizar antes.
  DateTime get fimPrevisto =>
      iniciadaEm.add(Duration(minutes: duracaoMinutos));

  /// Ainda rodando (folha aberta) — false depois de "Finalizar".
  bool get ativa => finalizadaEm == null;

  /// Substitui um item pelo número (marcar resposta / preencher gabarito).
  /// Sem efeito se o número não existir — o caller sempre itera em cima de
  /// [itens], então isso não deveria disparar na prática.
  ExecucaoProva comItemAtualizado(
    int numero,
    ItemProva Function(ItemProva) atualizar,
  ) {
    return copyWith(
      itens: [
        for (final item in itens)
          if (item.numero == numero) atualizar(item) else item,
      ],
    );
  }

  ExecucaoProva copyWith({
    String? nome,
    String? banca,
    List<ItemProva>? itens,
    DateTime? finalizadaEm,
  }) => ExecucaoProva(
    id: id,
    nome: nome ?? this.nome,
    ambienteId: ambienteId,
    banca: banca ?? this.banca,
    iniciadaEm: iniciadaEm,
    duracaoMinutos: duracaoMinutos,
    itens: itens ?? this.itens,
    finalizadaEm: finalizadaEm ?? this.finalizadaEm,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'ambienteId': ambienteId,
    'banca': banca,
    'iniciadaEm': iniciadaEm.toIso8601String(),
    'duracaoMinutos': duracaoMinutos,
    'itens': itens.map((i) => i.toJson()).toList(),
    'finalizadaEm': finalizadaEm?.toIso8601String(),
  };

  factory ExecucaoProva.fromJson(Map<String, dynamic> json) => ExecucaoProva(
    id: json['id'] as String,
    nome: json['nome'] as String,
    ambienteId: json['ambienteId'] as String? ?? Ambiente.geralId,
    banca: json['banca'] as String?,
    iniciadaEm: DateTime.parse(json['iniciadaEm'] as String),
    duracaoMinutos: (json['duracaoMinutos'] as num).toInt(),
    itens: (json['itens'] as List? ?? const [])
        .map((e) => ItemProva.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    finalizadaEm: json['finalizadaEm'] == null
        ? null
        : DateTime.parse(json['finalizadaEm'] as String),
  );
}
