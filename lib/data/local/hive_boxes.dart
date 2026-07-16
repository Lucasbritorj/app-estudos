import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../catalogo/catalogo_materias.dart';
import '../models/ambiente.dart';
import '../models/aula.dart';
import '../models/configuracoes.dart';
import '../models/resumo.dart';
import '../models/revisao.dart';
import '../../domain/revisao_service.dart';

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

  /// Sessão de cronômetro em andamento — persistida para sobreviver a
  /// reload da aba/kill do app (relógio de parede, não Stopwatch em memória).
  static const cronometro = 'cronometro';

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
      Hive.openBox<Map>(cronometro),
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

  /// Versão de schema atual. Cada incremento corresponde a um passo em
  /// [migrar]; a versão gravada evita repagar migrações a cada boot.
  static const schemaVersion = 2;
  static const _chaveSchema = 'schemaVersion';

  /// Pipeline de migração versionado: roda só os passos pendentes uma vez.
  /// Boot normal (versão em dia) tem custo O(1) — sem varrer box nenhum.
  /// A ordem é explícita e cada passo é idempotente por segurança.
  static Future<void> migrar() async {
    final boxConfig = Hive.box<Map>(config);
    final versao = (boxConfig.get(_chaveSchema)?['v'] as num?)?.toInt() ?? 0;
    if (versao >= schemaVersion) return;

    if (versao < 1) await migrarAmbientes();
    if (versao < 2) await repararOrfaos();

    await boxConfig.put(_chaveSchema, {'v': schemaVersion});
  }

  /// Religa invariantes quebradas por crash entre escritas multi-box (Hive
  /// não tem transação): aula concluída que não gerou NENHUMA revisão de
  /// cadeia recebe a Revisão 1 retroativa. Conservador — só recria quando
  /// não há revisão alguma referenciando a aula, então cadeia legítima
  /// (mesmo toda concluída) nunca é duplicada.
  static Future<void> repararOrfaos() async {
    final boxRevisoes = Hive.box<Map>(revisoes);
    final aulasComRevisao = <String>{};
    for (final raw in boxRevisoes.values) {
      final aulaId = raw['aulaId'] as String?;
      if (aulaId != null) aulasComRevisao.add(aulaId);
    }

    final rawConfig = Hive.box<Map>(config).get('config');
    final intervalos = rawConfig == null
        ? const Configuracoes().intervalosRevisao
        : Configuracoes.fromJson(Map<String, dynamic>.from(rawConfig))
            .intervalosRevisao;
    final primeiro = RevisaoService.proximoIntervalo(intervalos, 0);
    if (primeiro == null) return;

    final boxMaterias = Hive.box<Map>(materias);
    String nomeMateria(String id) {
      final raw = boxMaterias.get(id);
      return raw == null ? 'Estudo' : (raw['nome'] as String? ?? 'Estudo');
    }

    for (final raw in Hive.box<Map>(aulas).values) {
      final aula = Aula.fromJson(Map<String, dynamic>.from(raw));
      if (!aula.concluida || aula.dataConclusao == null) continue;
      if (aulasComRevisao.contains(aula.id)) continue;

      final base = aula.dataConclusao!;
      final revisao = Revisao(
        id: const Uuid().v4(),
        materiaId: aula.materiaId,
        aulaId: aula.id,
        titulo: '${nomeMateria(aula.materiaId)} — ${aula.nome} (${primeiro}d)',
        dataAgendada: DateTime(base.year, base.month, base.day + primeiro),
        intervaloDias: primeiro,
      );
      await boxRevisoes.put(revisao.id, revisao.toJson());
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
