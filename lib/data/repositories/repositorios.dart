import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../local/hive_boxes.dart';
import '../models/ambiente.dart';
import '../models/aula.dart';
import '../models/leitura.dart';
import '../models/materia.dart';
import '../models/registro_hora.dart';
import '../models/resumo.dart';
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

  // Metadados de sincronização futura. Repositórios de entidades
  // sincronizáveis sobrescrevem os três: salvar passa a carimbar a última
  // modificação e remover vira tombstone (o registro fica no box com marca
  // de exclusão — um sync futuro precisa propagar deletes — mas some do
  // state). O default preserva o comportamento clássico: sem carimbo,
  // hard delete.
  T Function(T item, DateTime agora)? get carimbarAtualizacao => null;
  T Function(T item, DateTime agora)? get marcarExclusao => null;
  bool estaExcluido(T item) => false;

  Box<Map> get _box => Hive.box<Map>(boxName);

  @override
  List<T> build() => _carregar();

  List<T> _carregar() {
    final itens = _box.values
        .map((raw) => fromJson(Map<String, dynamic>.from(raw)))
        .where((item) => !estaExcluido(item))
        .toList();
    itens.sort(comparar);
    return itens;
  }

  // Escritas pontuais atualizam a projeção em memória de forma incremental:
  // o box é a fonte persistida, mas re-deserializar/reordenar a coleção
  // inteira a cada salvar custava O(box) por escrita. _carregar() fica para
  // o build() e para restaurações completas.

  Future<void> salvar(T item) async {
    final carimbar = carimbarAtualizacao;
    final gravado = carimbar == null ? item : carimbar(item, DateTime.now());
    await _box.put(idDe(gravado), toJson(gravado));
    final id = idDe(gravado);
    state = [
      for (final e in state)
        if (idDe(e) != id) e,
      gravado,
    ]..sort(comparar);
  }

  Future<void> remover(String id) async {
    final marcar = marcarExclusao;
    if (marcar == null) {
      await _box.delete(id);
    } else {
      // Tombstone: regrava o registro marcado em vez de apagar.
      final vivos = state.where((e) => idDe(e) == id).toList();
      if (vivos.isNotEmpty) {
        await _box.put(id, toJson(marcar(vivos.first, DateTime.now())));
      } else {
        await _box.delete(id);
      }
    }
    state = [
      for (final e in state)
        if (idDe(e) != id) e,
    ];
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
    final novos = {for (final item in itens) idDe(item): item};
    state = [
      for (final e in state)
        if (!novos.containsKey(idDe(e))) e,
      ...novos.values,
    ]..sort(comparar);
  }

  /// Remoção em lote por predicado (cascatas): um deleteAll/putAll, uma
  /// atualização de state. Entidades com tombstone marcam em vez de apagar.
  Future<void> removerOnde(bool Function(T) teste) async {
    final alvos = [
      for (final e in state)
        if (teste(e)) e,
    ];
    if (alvos.isEmpty) return;
    final marcar = marcarExclusao;
    if (marcar == null) {
      await _box.deleteAll([for (final e in alvos) idDe(e)]);
    } else {
      final agora = DateTime.now();
      await _box.putAll({
        for (final e in alvos) idDe(e): toJson(marcar(e, agora)),
      });
    }
    final removidos = {for (final e in alvos) idDe(e)};
    state = [
      for (final e in state)
        if (!removidos.contains(idDe(e))) e,
    ];
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

  @override
  Materia Function(Materia, DateTime) get carimbarAtualizacao =>
      (m, agora) => m.comAtualizacao(agora);
  @override
  Materia Function(Materia, DateTime) get marcarExclusao =>
      (m, agora) => m.comExclusao(agora);
  @override
  bool estaExcluido(Materia item) => item.excluidaEm != null;

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

  @override
  RegistroHora Function(RegistroHora, DateTime) get carimbarAtualizacao =>
      (r, agora) => r.comAtualizacao(agora);
  @override
  RegistroHora Function(RegistroHora, DateTime) get marcarExclusao =>
      (r, agora) => r.comExclusao(agora);
  @override
  bool estaExcluido(RegistroHora item) => item.excluidoEm != null;
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

class ResumosRepositorio extends _HiveRepositorio<Resumo> {
  @override
  String get boxName => HiveBoxes.resumos;
  @override
  Resumo fromJson(Map<String, dynamic> json) => Resumo.fromJson(json);
  @override
  Map<String, dynamic> toJson(Resumo item) => item.toJson();
  @override
  String idDe(Resumo item) => item.sigla;
  @override
  int comparar(Resumo a, Resumo b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  /// Grava o texto da página carimbando a data de edição.
  Future<void> salvarTexto(Resumo pagina, String texto) =>
      salvar(pagina.copyWith(texto: texto, atualizadoEm: DateTime.now()));
}

final resumosProvider = NotifierProvider<ResumosRepositorio, List<Resumo>>(
  ResumosRepositorio.new,
);

final simuladosProvider =
    NotifierProvider<SimuladosRepositorio, List<Simulado>>(
      SimuladosRepositorio.new,
    );
final ambientesProvider =
    NotifierProvider<AmbientesRepositorio, List<Ambiente>>(
      AmbientesRepositorio.new,
    );
final materiasProvider = NotifierProvider<MateriasRepositorio, List<Materia>>(
  MateriasRepositorio.new,
);
final leiturasProvider = NotifierProvider<LeiturasRepositorio, List<Leitura>>(
  LeiturasRepositorio.new,
);
final topicosProvider = NotifierProvider<TopicosRepositorio, List<Topico>>(
  TopicosRepositorio.new,
);
final aulasProvider = NotifierProvider<AulasRepositorio, List<Aula>>(
  AulasRepositorio.new,
);
final registrosProvider =
    NotifierProvider<RegistrosRepositorio, List<RegistroHora>>(
      RegistrosRepositorio.new,
    );
final revisoesProvider = NotifierProvider<RevisoesRepositorio, List<Revisao>>(
  RevisoesRepositorio.new,
);
