import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../local/hive_boxes.dart';

/// Minutos planejados por dia da semana (1 = segunda ... 7 = domingo).
class PlanejamentoRepositorio extends Notifier<Map<int, int>> {
  static const _chave = 'semana';

  Box<Map> get _box => Hive.box<Map>(HiveBoxes.planejamento);

  @override
  Map<int, int> build() {
    final raw = _box.get(_chave);
    if (raw == null) return {};
    return raw.map((k, v) =>
        MapEntry(int.parse(k as String), (v as num).toInt()));
  }

  Future<void> substituir(Map<int, int> novo) async {
    await _box.put(_chave, novo.map((k, v) => MapEntry(k.toString(), v)));
    state = novo;
  }

  Future<void> definirDia(int diaDaSemana, int minutos) async {
    final novo = {...state};
    if (minutos <= 0) {
      novo.remove(diaDaSemana);
    } else {
      novo[diaDaSemana] = minutos;
    }
    await _box.put(
        _chave, novo.map((k, v) => MapEntry(k.toString(), v)));
    state = novo;
  }
}

final planejamentoProvider =
    NotifierProvider<PlanejamentoRepositorio, Map<int, int>>(
        PlanejamentoRepositorio.new);
