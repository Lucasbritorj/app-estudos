import 'bancas.dart';

/// Resultado de UMA matéria dentro de um simulado/prova. Erros e taxa são
/// derivados — nunca inputados (enforcement por derivação).
class ResultadoMateria {
  final String materiaId;
  final int questoes;
  final int acertos;

  const ResultadoMateria._({
    required this.materiaId,
    required this.questoes,
    required this.acertos,
  });

  /// Invariantes na borda do modelo (M-05), espelhando [RegistroHora]: o
  /// formulário já validava, mas o import de backup construía direto e
  /// deixava passar `acertos > questoes` (taxa de 300% no card) ou valores
  /// negativos corrompendo os totais.
  factory ResultadoMateria({
    required String materiaId,
    required int questoes,
    required int acertos,
  }) {
    final q = questoes < 0 ? 0 : questoes;
    return ResultadoMateria._(
      materiaId: materiaId,
      questoes: q,
      acertos: acertos.clamp(0, q),
    );
  }

  int get erros => questoes - acertos;
  double? get taxa => questoes <= 0 ? null : acertos / questoes;

  Map<String, dynamic> toJson() => {
    'materiaId': materiaId,
    'questoes': questoes,
    'acertos': acertos,
  };

  factory ResultadoMateria.fromJson(Map<String, dynamic> json) =>
      ResultadoMateria(
        materiaId: json['materiaId'] as String,
        questoes: (json['questoes'] as num).toInt(),
        acertos: (json['acertos'] as num).toInt(),
      );
}

enum TipoSimulado { simulado, prova }

/// Simulado ou prova real: o usuário informa tempo, questões e acertos por
/// matéria; totais, taxa, erros e tempo/questão o app calcula.
class Simulado {
  final String id;
  final String ambienteId;
  final TipoSimulado tipo;
  final String nome;

  /// Cargo — relevante em prova real ("Auditor SEFAZ-RN").
  final String cargo;

  /// Banca organizadora, normalizada ([Bancas.normalizar]). Campo próprio em
  /// vez de texto solto dentro de [cargo]: é a dimensão que cruza com as
  /// sessões de questões no ranking por banca.
  final String? banca;
  final DateTime data;

  /// Duração total gasta, em minutos; null = não cronometrado.
  final int? tempoMinutos;
  final List<ResultadoMateria> resultados;
  final String comentario;

  Simulado({
    required this.id,
    required this.ambienteId,
    required this.tipo,
    required this.nome,
    this.cargo = '',
    String? banca,
    required this.data,
    this.tempoMinutos,
    this.resultados = const [],
    this.comentario = '',
  }) : banca = Bancas.normalizar(banca);

  int get totalQuestoes => resultados.fold(0, (soma, r) => soma + r.questoes);
  int get totalAcertos => resultados.fold(0, (soma, r) => soma + r.acertos);
  int get totalErros => totalQuestoes - totalAcertos;
  double? get taxaGeral =>
      totalQuestoes <= 0 ? null : totalAcertos / totalQuestoes;

  /// Minutos por questão; null sem tempo ou sem questões.
  double? get minutosPorQuestao {
    final t = tempoMinutos;
    if (t == null || t <= 0 || totalQuestoes <= 0) return null;
    return t / totalQuestoes;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ambienteId': ambienteId,
    'tipo': tipo.name,
    'nome': nome,
    'cargo': cargo,
    'banca': banca,
    'data': data.toIso8601String(),
    'tempoMinutos': tempoMinutos,
    'resultados': resultados.map((r) => r.toJson()).toList(),
    'comentario': comentario,
  };

  factory Simulado.fromJson(Map<String, dynamic> json) => Simulado(
    id: json['id'] as String,
    ambienteId: json['ambienteId'] as String? ?? 'geral',
    tipo:
        TipoSimulado.values.asNameMap()[json['tipo']] ?? TipoSimulado.simulado,
    nome: json['nome'] as String,
    cargo: json['cargo'] as String? ?? '',
    banca: json['banca'] as String?,
    data: DateTime.parse(json['data'] as String),
    tempoMinutos: (json['tempoMinutos'] as num?)?.toInt(),
    resultados: (json['resultados'] as List? ?? const [])
        .map(
          (e) => ResultadoMateria.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList(),
    comentario: json['comentario'] as String? ?? '',
  );
}
