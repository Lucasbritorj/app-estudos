import 'package:hive_ce_flutter/hive_flutter.dart';

import '../catalogo/catalogo_materias.dart';
import '../models/ambiente.dart';
import '../models/resumo.dart';

/// Boxes Hive: cada registro é um Map JSON — sem codegen de adapters.
class HiveBoxes {
  static const ambientes = 'ambientes';
  static const materias = 'materias';
  static const topicos = 'topicos';
  static const aulas = 'aulas';
  static const registros = 'registros';
  static const revisoes = 'revisoes';
  static const config = 'config';
  static const planejamento = 'planejamento';
  static const leituras = 'leituras';
  static const simulados = 'simulados';
  static const resumos = 'resumos';

  static Future<void> openAll() async {
    await Future.wait([
      Hive.openBox<Map>(ambientes),
      Hive.openBox<Map>(materias),
      Hive.openBox<Map>(topicos),
      Hive.openBox<Map>(aulas),
      Hive.openBox<Map>(registros),
      Hive.openBox<Map>(revisoes),
      Hive.openBox<Map>(config),
      Hive.openBox<Map>(planejamento),
      Hive.openBox<Map>(leituras),
      Hive.openBox<Map>(simulados),
      Hive.openBox<Map>(resumos),
    ]);
  }

  /// Seed das páginas de resumo (idempotente, por chave): matéria do
  /// catálogo sem página ganha uma vazia; página existente NUNCA é tocada —
  /// texto do usuário sobrevive a qualquer boot/atualização do catálogo.
  static Future<void> seedResumos() async {
    final box = Hive.box<Map>(resumos);
    for (final m in catalogoMaterias) {
      if (box.containsKey(m.sigla)) continue;
      await box.put(
        m.sigla,
        Resumo(sigla: m.sigla, nome: m.nome, doCatalogo: true).toJson(),
      );
    }
  }

  /// Migração de boot (idempotente): garante o ambiente "Geral" quando o box
  /// está vazio e grava `ambienteId` explícito nas matérias antigas — sem
  /// isso, apagar o "Geral" deixaria matérias pré-Ambientes órfãs, porque o
  /// default do fromJson só existe em memória.
  static Future<void> migrarAmbientes() async {
    final boxAmbientes = Hive.box<Map>(ambientes);
    if (boxAmbientes.isEmpty) {
      await boxAmbientes.put(
        Ambiente.geralId,
        Ambiente(
          id: Ambiente.geralId,
          nome: 'Geral',
          criadoEm: DateTime.now(),
        ).toJson(),
      );
    }
    final boxMaterias = Hive.box<Map>(materias);
    for (final key in boxMaterias.keys.toList()) {
      final raw = boxMaterias.get(key);
      if (raw == null || raw['ambienteId'] != null) continue;
      final corrigida = Map<String, dynamic>.from(raw);
      corrigida['ambienteId'] = Ambiente.geralId;
      await boxMaterias.put(key, corrigida);
    }
  }
}
