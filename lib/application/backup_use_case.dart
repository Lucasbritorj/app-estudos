import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../core/notificacoes/notificacoes_service.dart';
import '../data/local/hive_boxes.dart';
import '../data/repositories/configuracoes_repositorio.dart';
import '../data/repositories/planejamento_repositorio.dart';
import '../data/repositories/repositorios.dart';
import '../domain/export_service.dart';
import '../domain/import_service.dart';

/// Restauração de backup com rede de proteção.
///
/// Substituir tudo escreve em 11 boxes em sequência, e o Hive não tem transação
/// entre boxes: uma falha no meio (crash, bateria, disco cheio) deixava metade
/// dos dados do backup e metade dos antigos, sem volta. Aqui o estado atual é
/// serializado ANTES de qualquer escrita; se a restauração explodir, ele é
/// reaplicado, e enquanto o snapshot existir o usuário pode desfazer à mão.
class BackupUseCase {
  BackupUseCase(this._ref);
  final Ref _ref;

  /// Chave única do slot de snapshot (o box guarda um só).
  static const _chaveSnapshot = 'ultimo';

  Box<Map> get _box => Hive.box<Map>(HiveBoxes.rollback);

  /// JSON com TUDO que está gravado agora — o mesmo formato do backup manual,
  /// então o snapshot também serve como arquivo de recuperação.
  String snapshotAtual() => ExportService.jsonCompleto(
    ambientes: _ref.read(ambientesProvider),
    materias: _ref.read(materiasProvider),
    topicos: _ref.read(topicosProvider),
    aulas: _ref.read(aulasProvider),
    registros: _ref.read(registrosProvider),
    revisoes: _ref.read(revisoesProvider),
    leituras: _ref.read(leiturasProvider),
    planejamento: _ref.read(planejamentoProvider),
    simulados: _ref.read(simuladosProvider),
    resumos: _ref.read(resumosProvider),
    questoesErradas: _ref.read(questoesErradasProvider),
    // Fotos do enunciado entram no snapshot: sem elas o "Desfazer" devolveria
    // as questões sem as imagens, que é perda silenciosa do dado mais caro de
    // reproduzir (o usuário fotografou a página uma vez).
    anexos: _ref.read(anexosQuestaoRepositorioProvider).todos(),
    configuracoes: _ref.read(configuracoesProvider),
  );

  /// Snapshot guardado, se houver.
  ({String json, DateTime criadoEm})? get snapshotGuardado {
    final bruto = _box.get(_chaveSnapshot);
    if (bruto == null) return null;
    final json = bruto['json'];
    final criadoEm = DateTime.tryParse(bruto['criadoEm']?.toString() ?? '');
    if (json is! String || criadoEm == null) return null;
    return (json: json, criadoEm: criadoEm);
  }

  bool get podeDesfazer => snapshotGuardado != null;

  Future<void> descartarSnapshot() => _box.delete(_chaveSnapshot);

  /// Substitui todos os dados pelo conteúdo de [backup].
  ///
  /// Grava o snapshot antes; em qualquer exceção, reaplica o snapshot e
  /// repropaga o erro — a UI mostra a falha sabendo que os dados voltaram.
  /// Backup parcial (de um ambiente) é recusado aqui, não só na tela: as
  /// coleções globais dele vêm vazias por escopo e apagariam leituras,
  /// resumos e cronograma.
  Future<void> restaurarSubstituindo(BackupImportado backup) async {
    if (backup.parcial) {
      throw StateError(
        'Backup de um único ambiente não pode substituir tudo — use mesclar.',
      );
    }
    final snapshot = snapshotAtual();
    await _box.put(_chaveSnapshot, {
      'json': snapshot,
      'criadoEm': DateTime.now().toIso8601String(),
    });
    try {
      await _aplicarSubstituindo(backup);
    } catch (_) {
      // Melhor esforço: se a volta também falhar, o snapshot continua no box
      // e o botão "Desfazer" segue disponível.
      try {
        await _aplicarSubstituindo(ImportService.parseBackup(snapshot));
      } catch (_) {}
      rethrow;
    }
  }

  /// Volta ao estado anterior à última restauração e consome o snapshot.
  /// Devolve false quando não há nada para desfazer.
  Future<bool> desfazerUltimaRestauracao() async {
    final snapshot = snapshotGuardado;
    if (snapshot == null) return false;
    await _aplicarSubstituindo(ImportService.parseBackup(snapshot.json));
    await descartarSnapshot();
    return true;
  }

  /// Ordem filhos→pais, igual a [ApagarDadosUseCase.apagarTudo]: nenhuma
  /// leitura no meio do processo vê filho apontando para pai que já sumiu.
  Future<void> _aplicarSubstituindo(BackupImportado backup) async {
    final agora = DateTime.now();
    await _ref
        .read(ambientesProvider.notifier)
        .substituirTudo(backup.ambientesOuGeral(agora));
    // O ambiente ativo pode não existir mais no backup restaurado.
    final configAtual = _ref.read(configuracoesProvider);
    if (configAtual.ambienteAtivoId != null) {
      await _ref
          .read(configuracoesProvider.notifier)
          .salvar(configAtual.copyWith(limparAmbienteAtivo: true));
    }
    await _ref.read(materiasProvider.notifier).substituirTudo(backup.materias);
    await _ref.read(topicosProvider.notifier).substituirTudo(backup.topicos);
    await _ref.read(aulasProvider.notifier).substituirTudo(backup.aulas);
    await _ref
        .read(registrosProvider.notifier)
        .substituirTudo(backup.registros);
    await _ref.read(revisoesProvider.notifier).substituirTudo(backup.revisoes);
    await _ref.read(leiturasProvider.notifier).substituirTudo(backup.leituras);
    await _ref
        .read(simuladosProvider.notifier)
        .substituirTudo(backup.simulados);
    await _ref.read(resumosProvider.notifier).substituirTudo(backup.resumos);
    await _ref
        .read(questoesErradasProvider.notifier)
        .substituirTudo(backup.questoesErradas);
    await _ref
        .read(anexosQuestaoRepositorioProvider)
        .substituirTudo(backup.anexos);
    await _ref
        .read(planejamentoProvider.notifier)
        .substituir(backup.planejamento);

    // Preferências só são tocadas quando o arquivo as traz: backup antigo (sem
    // a chave) não pode zerar a meta semanal de quem está restaurando.
    final preferencias = backup.configuracoes;
    if (preferencias != null) {
      await _ref
          .read(configuracoesProvider.notifier)
          .salvar(preferencias.copyWith(limparAmbienteAtivo: true));
      await NotificacoesService.agendarLembreteDiario(
        preferencias.horaLembreteEstudo,
      );
    }

    // As revisões restauradas têm ids novos: os lembretes agendados apontavam
    // para o conjunto antigo e ficariam órfãos no sistema operacional.
    await NotificacoesService.cancelarTodas();
  }
}

final backupUseCaseProvider = Provider((ref) => BackupUseCase(ref));
