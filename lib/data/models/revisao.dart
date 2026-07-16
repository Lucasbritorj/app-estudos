enum RevisaoStatus { aFazer, atrasada, feita }

/// Revisão espaçada agendada (intervalos configuráveis: 7, 15, 30, 60 dias...).
/// "Atrasada" é derivado da data, nunca gravado.
class Revisao {
  final String id;
  final String materiaId;
  final String? topicoId;

  /// Aula concluída que originou esta cadeia de revisão.
  final String? aulaId;
  final String titulo;
  final DateTime dataAgendada;
  final int intervaloDias;
  final bool feita;
  final DateTime? dataConclusao;

  /// Estado FSRS-lite herdado da conclusão anterior da cadeia. Null em
  /// revisões antigas ou recém-criadas: a primeira conclusão semeia a
  /// estabilidade a partir de [intervaloDias].
  final double? estabilidade;
  final double? dificuldade;

  const Revisao({
    required this.id,
    required this.materiaId,
    this.topicoId,
    this.aulaId,
    required this.titulo,
    required this.dataAgendada,
    required this.intervaloDias,
    this.feita = false,
    this.dataConclusao,
    this.estabilidade,
    this.dificuldade,
  });

  RevisaoStatus statusEm(DateTime hoje) {
    if (feita) return RevisaoStatus.feita;
    final d = DateTime(dataAgendada.year, dataAgendada.month, dataAgendada.day);
    final h = DateTime(hoje.year, hoje.month, hoje.day);
    return d.isBefore(h) ? RevisaoStatus.atrasada : RevisaoStatus.aFazer;
  }

  Revisao copyWith(
          {bool? feita, DateTime? dataConclusao, DateTime? dataAgendada}) =>
      Revisao(
        id: id,
        materiaId: materiaId,
        topicoId: topicoId,
        aulaId: aulaId,
        titulo: titulo,
        dataAgendada: dataAgendada ?? this.dataAgendada,
        intervaloDias: intervaloDias,
        feita: feita ?? this.feita,
        dataConclusao: dataConclusao ?? this.dataConclusao,
        estabilidade: estabilidade,
        dificuldade: dificuldade,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'materiaId': materiaId,
        'topicoId': topicoId,
        'aulaId': aulaId,
        'titulo': titulo,
        'dataAgendada': dataAgendada.toIso8601String(),
        'intervaloDias': intervaloDias,
        'feita': feita,
        'dataConclusao': dataConclusao?.toIso8601String(),
        'estabilidade': estabilidade,
        'dificuldade': dificuldade,
      };

  factory Revisao.fromJson(Map<String, dynamic> json) => Revisao(
        id: json['id'] as String,
        materiaId: json['materiaId'] as String,
        topicoId: json['topicoId'] as String?,
        aulaId: json['aulaId'] as String?,
        titulo: json['titulo'] as String? ?? '',
        dataAgendada: DateTime.parse(json['dataAgendada'] as String),
        intervaloDias: (json['intervaloDias'] as num).toInt(),
        feita: json['feita'] as bool? ?? false,
        dataConclusao: json['dataConclusao'] == null
            ? null
            : DateTime.parse(json['dataConclusao'] as String),
        estabilidade: (json['estabilidade'] as num?)?.toDouble(),
        dificuldade: (json['dificuldade'] as num?)?.toDouble(),
      );
}
