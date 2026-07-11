import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ambiente.dart';
import '../models/materia.dart';
import '../models/registro_hora.dart';
import '../models/revisao.dart';
import 'configuracoes_repositorio.dart';
import 'repositorios.dart';

/// Escopo global de ambiente: null = visão consolidada ("Todos").
/// Ambiente apagado ou inexistente cai na visão consolidada — nunca em
/// tela vazia sem explicação.
final ambienteAtivoProvider = Provider<Ambiente?>((ref) {
  final id = ref.watch(configuracoesProvider).ambienteAtivoId;
  if (id == null) return null;
  return ref.watch(ambientesProvider).where((a) => a.id == id).firstOrNull;
});

/// Matérias do ambiente ativo (todas quando consolidado).
final materiasDoAmbienteProvider = Provider<List<Materia>>((ref) {
  final materias = ref.watch(materiasProvider);
  final ativo = ref.watch(ambienteAtivoProvider);
  if (ativo == null) return materias;
  return materias.where((m) => m.ambienteId == ativo.id).toList();
});

/// IDs das matérias no escopo ativo — base dos filtros por relação.
final _materiaIdsDoAmbienteProvider = Provider<Set<String>?>((ref) {
  final ativo = ref.watch(ambienteAtivoProvider);
  if (ativo == null) return null;
  return ref
      .watch(materiasProvider)
      .where((m) => m.ambienteId == ativo.id)
      .map((m) => m.id)
      .toSet();
});

/// Registros herdando escopo pela matéria.
final registrosDoAmbienteProvider = Provider<List<RegistroHora>>((ref) {
  final registros = ref.watch(registrosProvider);
  final ids = ref.watch(_materiaIdsDoAmbienteProvider);
  if (ids == null) return registros;
  return registros.where((r) => ids.contains(r.materiaId)).toList();
});

/// Revisões herdando escopo pela matéria.
final revisoesDoAmbienteProvider = Provider<List<Revisao>>((ref) {
  final revisoes = ref.watch(revisoesProvider);
  final ids = ref.watch(_materiaIdsDoAmbienteProvider);
  if (ids == null) return revisoes;
  return revisoes.where((r) => ids.contains(r.materiaId)).toList();
});
