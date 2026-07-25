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
    final ambienteId = ref.watch(
      configuracoesProvider.select((c) => c.ambienteAtivoId),
    );
    final raw = _box.get(_chave(ambienteId)) ?? _box.get(_chaveGlobal);
    if (raw == null) return {};
    // Formato novo: {'dias': {...}, 'atualizadoEm': iso} (metadado de
    // sincronização futura). Formato legado: o mapa de dias direto —
    // leitura tolerante, a próxima gravação migra sozinha.
    final dias = raw.containsKey('dias')
        ? Map<dynamic, dynamic>.from(raw['dias'] as Map)
        : raw;
    return dias.map(
      (k, v) => MapEntry(int.parse(k as String), (v as num).toInt()),
    );
  }

  Future<void> _gravar(Map<int, int> novo) async {
    final ambienteId = ref.read(configuracoesProvider).ambienteAtivoId;
    await _box.put(_chave(ambienteId), {
      'dias': novo.map((k, v) => MapEntry(k.toString(), v)),
      'atualizadoEm': DateTime.now().toIso8601String(),
    });
    state = novo;
  }

  Future<void> substituir(Map<int, int> novo) => _gravar(novo);

  /// Wipe out: limpa o box INTEIRO — a chave global 'semana' E toda chave
  /// escopada `semana:<id>` de qualquer ambiente, não só a do ambiente
  /// ativo agora. `substituir({})` sozinho NÃO serve pra isso: `_gravar`
  /// escreve só na chave do ambiente ativo no momento da chamada, deixando
  /// as outras (ex.: a global, se o ativo for outro; ou outros ambientes)
  /// vivas — e como a leitura cai de volta pra elas quando o ambiente ativo
  /// muda (fallback documentado no build()), o cronograma "apagado"
  /// reaparecia sozinho depois de limparAmbienteAtivo.
  Future<void> apagarTudo() async {
    await _box.clear();
    state = {};
  }

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
      PlanejamentoRepositorio.new,
    );
