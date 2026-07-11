import 'ambiente.dart';

/// Matéria de estudo. Campos `peso`, `questoes` e `minimo` seguem a estrutura
/// da aba de pesos por edital (ex.: SEFAZ-RN) da planilha de referência.
class Materia {
  final String id;
  final String nome;

  /// Ambiente dono da matéria; dados antigos caem no ambiente "Geral".
  final String ambienteId;

  /// Índice 0-7 na paleta categórica fixa (cor segue a entidade, nunca a posição).
  final int corSlot;
  final int peso;
  final int? questoes;
  final int? minimo;

  /// Intimidade com a matéria, 1 (iniciante) a 5 (especialista).
  /// Cruzada com a taxa de acerto no diagnóstico do planejamento.
  final int intimidade;

  /// Minutos totais previstos para "fechar" a matéria; null = sem alvo.
  /// Base da fila de estudo (distribuição de semanas por matéria).
  final int? minutosAlvo;
  final bool arquivada;
  final DateTime criadaEm;

  /// Notas livres do usuário (texto simples).
  final String notas;

  const Materia({
    required this.id,
    required this.nome,
    this.ambienteId = Ambiente.geralId,
    required this.corSlot,
    this.peso = 1,
    this.questoes,
    this.minimo,
    this.intimidade = 3,
    this.minutosAlvo,
    this.arquivada = false,
    required this.criadaEm,
    this.notas = '',
  });

  Materia copyWith({
    String? nome,
    String? ambienteId,
    int? corSlot,
    int? peso,
    int? questoes,
    int? minimo,
    int? intimidade,
    int? minutosAlvo,
    bool limparMinutosAlvo = false,
    bool? arquivada,
    String? notas,
  }) {
    return Materia(
      id: id,
      nome: nome ?? this.nome,
      ambienteId: ambienteId ?? this.ambienteId,
      corSlot: corSlot ?? this.corSlot,
      peso: peso ?? this.peso,
      questoes: questoes ?? this.questoes,
      minimo: minimo ?? this.minimo,
      intimidade: intimidade ?? this.intimidade,
      minutosAlvo:
          limparMinutosAlvo ? null : (minutosAlvo ?? this.minutosAlvo),
      arquivada: arquivada ?? this.arquivada,
      criadaEm: criadaEm,
      notas: notas ?? this.notas,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'ambienteId': ambienteId,
        'corSlot': corSlot,
        'peso': peso,
        'questoes': questoes,
        'minimo': minimo,
        'intimidade': intimidade,
        'minutosAlvo': minutosAlvo,
        'arquivada': arquivada,
        'criadaEm': criadaEm.toIso8601String(),
        'notas': notas,
      };

  factory Materia.fromJson(Map<String, dynamic> json) => Materia(
        id: json['id'] as String,
        nome: json['nome'] as String,
        ambienteId: json['ambienteId'] as String? ?? Ambiente.geralId,
        corSlot: (json['corSlot'] as num?)?.toInt() ?? 0,
        peso: (json['peso'] as num?)?.toInt() ?? 1,
        questoes: (json['questoes'] as num?)?.toInt(),
        minimo: (json['minimo'] as num?)?.toInt(),
        intimidade:
            ((json['intimidade'] as num?)?.toInt() ?? 3).clamp(1, 5),
        minutosAlvo: (json['minutosAlvo'] as num?)?.toInt(),
        arquivada: json['arquivada'] as bool? ?? false,
        criadaEm: DateTime.parse(json['criadaEm'] as String),
        notas: json['notas'] as String? ?? '',
      );
}
