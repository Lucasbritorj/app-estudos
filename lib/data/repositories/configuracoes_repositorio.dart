import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../local/hive_boxes.dart';
import '../models/configuracoes.dart';

class ConfiguracoesRepositorio extends Notifier<Configuracoes> {
  static const _chave = 'config';

  Box<Map> get _box => Hive.box<Map>(HiveBoxes.config);

  @override
  Configuracoes build() {
    final raw = _box.get(_chave);
    if (raw == null) return const Configuracoes();
    return Configuracoes.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<void> salvar(Configuracoes config) async {
    await _box.put(_chave, config.toJson());
    state = config;
  }
}

final configuracoesProvider =
    NotifierProvider<ConfiguracoesRepositorio, Configuracoes>(
        ConfiguracoesRepositorio.new);
