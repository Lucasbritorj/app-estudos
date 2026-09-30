import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../../data/local/hive_boxes.dart';
import '../../domain/plano_diario_service.dart';
import '../../data/repositories/repositorios.dart';

class PlanoDiarioRepositorio extends Notifier<Map<String, dynamic>> {
  static const chave = 'planoDiario';
  Future<void> _fila = Future<void>.value();
  Future<void> _serializar(Future<void> Function() operacao) {
    final resultado = _fila.then((_) => operacao());
    _fila = resultado.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return resultado;
  }

  @override
  Map<String, dynamic> build() {
    final box = Hive.box<Map>(HiveBoxes.config);
    final sub = box.watch(key: chave).listen((_) {
      state = Map<String, dynamic>.from(box.get(chave) ?? {});
    });
    ref.onDispose(sub.cancel);
    return Map<String, dynamic>.from(box.get(chave) ?? {});
  }

  Future<void> gravar(Map<String, dynamic> dados) async {
    validarPlanoDiario(dados);
    await Hive.box<Map>(HiveBoxes.config).put(chave, dados);
    state = dados;
  }

  Future<void> aceitar(
    Map<String, dynamic> config,
    PropostaDiaria proposta,
    DateTime hoje,
  ) => _serializar(() async {
    final dia = DateTime(hoje.year, hoje.month, hoje.day);
    final vinculos = Map<String, dynamic>.from(state['vinculos'] as Map? ?? {});
    final todos = (state['blocos'] as List? ?? [])
        .map((j) => BlocoDiario.fromJson(j as Map))
        .toList();
    final diasProtegidos = todos
        .where((b) => vinculos.containsKey(b.id))
        .map((b) => diaPlano(b.dia))
        .toSet();
    final antigos = todos
        .where(
          (b) =>
              b.dia.isBefore(dia) || diasProtegidos.contains(diaPlano(b.dia)),
        )
        .toList();
    final ids = antigos.map((b) => b.id).toSet();
    await gravar({
      ...config,
      'blocos': [
        ...antigos.map((b) => b.toJson()),
        ...proposta.blocos
            .where(
              (b) =>
                  !b.dia.isBefore(dia) &&
                  !ids.contains(b.id) &&
                  !diasProtegidos.contains(diaPlano(b.dia)),
            )
            .map((b) => b.toJson()),
      ],
      'avisos': proposta.avisos,
      'vinculos': vinculos,
    });
  });

  Future<void> vincular(
    String blocoId,
    String registroId,
  ) => _serializar(() async {
    final blocos = (state['blocos'] as List? ?? []).map(
      (j) => BlocoDiario.fromJson(j as Map),
    );
    final encontrados = blocos.where((b) => b.id == blocoId);
    final registros = ref
        .read(registrosProvider)
        .where((r) => r.id == registroId);
    if (encontrados.length != 1 || registros.length != 1) {
      throw StateError('Bloco ou sessão não existe mais. Atualize o plano.');
    }
    final bloco = encontrados.single;
    final registro = registros.single;
    if (registro.minutos <= 0 ||
        registro.materiaId != bloco.materiaId ||
        diaPlano(registro.data) != diaPlano(bloco.dia)) {
      throw StateError(
        'A sessão precisa pertencer à mesma matéria e dia do bloco.',
      );
    }
    final vinculos = Map<String, dynamic>.from(state['vinculos'] as Map? ?? {});
    if (vinculos[blocoId] == registroId) return;
    if (vinculos.values.contains(registroId)) {
      throw StateError('Sessão já associada a outro bloco.');
    }
    if (vinculos.containsKey(blocoId) &&
        ref.read(registrosProvider).any((r) => r.id == vinculos[blocoId])) {
      throw StateError('Bloco já possui uma sessão associada.');
    }
    await gravar({
      ...state,
      'vinculos': {...vinculos, blocoId: registroId},
    });
  });
}

final planoDiarioProvider =
    NotifierProvider<PlanoDiarioRepositorio, Map<String, dynamic>>(
      PlanoDiarioRepositorio.new,
    );
