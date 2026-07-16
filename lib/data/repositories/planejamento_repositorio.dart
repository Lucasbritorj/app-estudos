import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../local/hive_boxes.dart';
import 'configuracoes_repositorio.dart';

/// Minutos planejados por dia da semana (1 = segunda ... 7 = domingo),
/// escopados pelo ambiente ativo: cada ambiente tem seu cronograma (chave
/// `semana:<id>`); a visão consolidada usa a chave global legada 'semana'.
/// Sem escopo, os MESMOS minutos semanais eram prometidos integralmente a
/// cada ambiente — prontidão e sugestão contavam o tempo em dobro.
///
/// Leitura de ambiente sem cronograma próprio herda o global como default;
/// a primeira edição grava a chave escopada (snapshot independente).
class PlanejamentoRepositorio extends Notifier<Map<int, int>> {
  static const _chaveGlobal = 'semana';

  Box<Map> get _box => Hive.box<Map>(HiveBoxes.planejamento);

  String _chave(String? ambienteId) =>
      ambienteId == null ? _chaveGlobal : 'semana:$ambienteId';

  @override
  Map<int, int> build() {
    final ambienteId =
        ref.watch(configuracoesProvider.select((c) => c.ambienteAtivoId));
    final raw = _box.get(_chave(ambienteId)) ?? _box.get(_chaveGlobal);
    if (raw == null) return {};
    return raw.map(
        (k, v) => MapEntry(int.parse(k as String), (v as num).toInt()));
  }

  Future<void> _gravar(Map<int, int> novo) async {
    final ambienteId = ref.read(configuracoesProvider).ambienteAtivoId;
    await _box.put(
        _chave(ambienteId), novo.map((k, v) => MapEntry(k.toString(), v)));
    state = novo;
  }

  Future<void> substituir(Map<int, int> novo) => _gravar(novo);

  Future<void> definirDia(int diaDaSemana, int minutos) {
    final novo = {...state};
    if (minutos <= 0) {
      novo.remove(diaDaSemana);
    } else {
      novo[diaDaSemana] = minutos;
    }
    return _gravar(novo);
  }
}

final planejamentoProvider =
    NotifierProvider<PlanejamentoRepositorio, Map<int, int>>(
        PlanejamentoRepositorio.new);
