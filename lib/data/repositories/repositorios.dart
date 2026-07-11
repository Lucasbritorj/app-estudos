import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../local/hive_boxes.dart';
import '../models/ambiente.dart';
import '../models/aula.dart';
import '../models/leitura.dart';
import '../models/materia.dart';
import '../models/registro_hora.dart';
import '../models/revisao.dart';
import '../models/simulado.dart';
import '../models/topico.dart';

/// Repository pattern sobre Hive: o box é a fonte persistida, o state do
/// Notifier é a projeção em memória que a UI observa.
abstract class _HiveRepositorio<T> extends Notifier<List<T>> {
  String get boxName;
  T fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson(T item);
  String idDe(T item);
  int comparar(T a, T b);

  Box<Map> get _box => Hive.box<Map>(boxName);

  @override
  List<T> build() => _carregar();

  List<T> _carregar() {
    final itens = _box.values
        .map((raw) => fromJson(Map<String, dynamic>.from(raw)))
        .toList();
    itens.sort(comparar);
    return itens;
  }

  Future<void> salvar(T item) async {
    await _box.put(idDe(item), toJson(item));
    state = _carregar();
  }

  Future<void> remover(String id) async {
    await _box.delete(id);
    state = _carregar();
  }

  /// Restaura backup: apaga tudo e grava a coleção importada.
  Future<void> substituirTudo(List<T> itens) async {
    await _box.clear();
    await _box.putAll({for (final item in itens) idDe(item): toJson(item)});
    state = _carregar();
  }

  /// Import incremental: grava/sobrescreve os itens SEM apagar o resto.
  Future<void> mesclar(List<T> itens) async {
    if (itens.isEmpty) return;
    await _box.putAll({for (final item in itens) idDe(item): toJson(item)});
    state = _carregar();
  }
}

class AmbientesRepositorio extends _HiveRepositorio<Ambiente> {
  @override
  String get boxName => HiveBoxes.ambientes;
  @override
  Ambiente fromJson(Map<String, dynamic> json) => Ambiente.fromJson(json);
  @override
  Map<String, dynamic> toJson(Ambiente item) => item.toJson();
  @override
  String idDe(Ambiente item) => item.id;
  @override
  int comparar(Ambiente a, Ambiente b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  int proximoCorSlot() {
    final usados = state.map((a) => a.corSlot).toList();
    for (var slot = 0; slot < 8; slot++) {
      if (!usados.contains(slot)) return slot;
    }
    return state.length % 8;
  }
}

class MateriasRepositorio extends _HiveRepositorio<Materia> {
  @override
  String get boxName => HiveBoxes.materias;
  @override
  Materia fromJson(Map<String, dynamic> json) => Materia.fromJson(json);
  @override
  Map<String, dynamic> toJson(Materia item) => item.toJson();
  @override
  String idDe(Materia item) => item.id;
  @override
  int comparar(Materia a, Materia b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  /// Próximo slot de cor livre na ordem fixa da paleta (0-7, com repetição
  /// se passar de 8 matérias).
  int proximoCorSlot() {
    final usados = state.map((m) => m.corSlot).toList();
    for (var slot = 0; slot < 8; slot++) {
      if (!usados.contains(slot)) return slot;
    }
    return state.length % 8;
  }
}

class TopicosRepositorio extends _HiveRepositorio<Topico> {
  @override
  String get boxName => HiveBoxes.topicos;
  @override
  Topico fromJson(Map<String, dynamic> json) => Topico.fromJson(json);
  @override
  Map<String, dynamic> toJson(Topico item) => item.toJson();
  @override
  String idDe(Topico item) => item.id;
  @override
  int comparar(Topico a, Topico b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  List<Topico> daMateria(String materiaId) =>
      state.where((t) => t.materiaId == materiaId).toList();
}

class AulasRepositorio extends _HiveRepositorio<Aula> {
  @override
  String get boxName => HiveBoxes.aulas;
  @override
  Aula fromJson(Map<String, dynamic> json) => Aula.fromJson(json);
  @override
  Map<String, dynamic> toJson(Aula item) => item.toJson();
  @override
  String idDe(Aula item) => item.id;
  @override
  int comparar(Aula a, Aula b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  List<Aula> daMateria(String materiaId) =>
      state.where((a) => a.materiaId == materiaId).toList();
}

class RegistrosRepositorio extends _HiveRepositorio<RegistroHora> {
  @override
  String get boxName => HiveBoxes.registros;
  @override
  RegistroHora fromJson(Map<String, dynamic> json) =>
      RegistroHora.fromJson(json);
  @override
  Map<String, dynamic> toJson(RegistroHora item) => item.toJson();
  @override
  String idDe(RegistroHora item) => item.id;
  @override
  int comparar(RegistroHora a, RegistroHora b) => b.data.compareTo(a.data);
}

class RevisoesRepositorio extends _HiveRepositorio<Revisao> {
  @override
  String get boxName => HiveBoxes.revisoes;
  @override
  Revisao fromJson(Map<String, dynamic> json) => Revisao.fromJson(json);
  @override
  Map<String, dynamic> toJson(Revisao item) => item.toJson();
  @override
  String idDe(Revisao item) => item.id;
  @override
  int comparar(Revisao a, Revisao b) =>
      a.dataAgendada.compareTo(b.dataAgendada);
}

class LeiturasRepositorio extends _HiveRepositorio<Leitura> {
  @override
  String get boxName => HiveBoxes.leituras;
  @override
  Leitura fromJson(Map<String, dynamic> json) => Leitura.fromJson(json);
  @override
  Map<String, dynamic> toJson(Leitura item) => item.toJson();
  @override
  String idDe(Leitura item) => item.id;
  @override
  int comparar(Leitura a, Leitura b) =>
      a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
}

class SimuladosRepositorio extends _HiveRepositorio<Simulado> {
  @override
  String get boxName => HiveBoxes.simulados;
  @override
  Simulado fromJson(Map<String, dynamic> json) => Simulado.fromJson(json);
  @override
  Map<String, dynamic> toJson(Simulado item) => item.toJson();
  @override
  String idDe(Simulado item) => item.id;
  @override
  int comparar(Simulado a, Simulado b) => b.data.compareTo(a.data);
}

final simuladosProvider =
    NotifierProvider<SimuladosRepositorio, List<Simulado>>(
        SimuladosRepositorio.new);
final ambientesProvider =
    NotifierProvider<AmbientesRepositorio, List<Ambiente>>(
        AmbientesRepositorio.new);
final materiasProvider =
    NotifierProvider<MateriasRepositorio, List<Materia>>(
        MateriasRepositorio.new);
final leiturasProvider =
    NotifierProvider<LeiturasRepositorio, List<Leitura>>(
        LeiturasRepositorio.new);
final topicosProvider =
    NotifierProvider<TopicosRepositorio, List<Topico>>(TopicosRepositorio.new);
final aulasProvider =
    NotifierProvider<AulasRepositorio, List<Aula>>(AulasRepositorio.new);
final registrosProvider =
    NotifierProvider<RegistrosRepositorio, List<RegistroHora>>(
        RegistrosRepositorio.new);
final revisoesProvider =
    NotifierProvider<RevisoesRepositorio, List<Revisao>>(
        RevisoesRepositorio.new);
