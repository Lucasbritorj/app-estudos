import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'notificacoes_revisao.dart';

import '../core/notificacoes/notificacoes_service.dart';
import '../data/local/hive_boxes.dart';
import '../data/repositories/configuracoes_repositorio.dart';
import '../data/repositories/conclusoes_revisao_repositorio.dart';
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
    extensoes: {
      for (final chave in ['planoDiario', 'concursos'])
        if (Hive.box<Map>(HiveBoxes.config).get(chave) case final Map valor)
          chave: valor,
    },
    conclusoesRevisao: Hive.isBoxOpen('conclusoes_revisao')
        ? Hive.box<Map>('conclusoes_revisao').values.toList()
        : const [],
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
  Future<void> restaurarSubstituindo(BackupImportado backup) =>
      ConclusoesRevisaoRepositorio.exclusivo(
        () => _restaurarSubstituindo(backup),
      );

  Future<void> _restaurarSubstituindo(BackupImportado backup) async {
    if (backup.parcial) {
      throw StateError(
        'Backup de um único ambiente não pode substituir tudo — use mesclar.',
      );
    }
    final conflitos = conflitosDaSubstituicao(backup);
    if (conflitos.isNotEmpty) {
      throw StateError(
        '${conflitos.join('; ')}. Use Importar e mesclar para preservar os vínculos.',
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

  /// Detecta vínculos válidos hoje que a substituição quebraria em coleções
  /// preservadas pelo formato legado. Órfãos anteriores continuam recuperáveis
  /// pela tela já existente e não impedem restaurar um snapshot de recuperação.
  List<String> conflitosDaSubstituicao(BackupImportado backup) {
    final atuais = _ref.read(materiasProvider).map((m) => m.id).toSet();
    final futuras = backup.materias.map((m) => m.id).toSet();
    final topicosAtuais = _ref.read(topicosProvider).map((t) => t.id).toSet();
    final topicosFuturos = backup.topicos.map((t) => t.id).toSet();
    bool perdeMateria(String id) =>
        atuais.contains(id) && !futuras.contains(id);
    final conflitos = <String>[];
    if (!backup.mencionou('questoesErradas')) {
      final afetadas = _ref
          .read(questoesErradasProvider)
          .where(
            (q) =>
                perdeMateria(q.materiaId) ||
                (q.topicoId != null &&
                    topicosAtuais.contains(q.topicoId) &&
                    !topicosFuturos.contains(q.topicoId)),
          )
          .length;
      if (afetadas > 0) {
        conflitos.add(
          '$afetadas questões preservadas perderiam matéria ou tópico',
        );
      }
    }
    if (!backup.mencionou('aulas')) {
      final afetadas = _ref
          .read(aulasProvider)
          .where((a) => perdeMateria(a.materiaId))
          .length;
      if (afetadas > 0) {
        conflitos.add('$afetadas aulas preservadas perderiam matéria');
      }
    }
    return conflitos;
  }

  /// Volta ao estado anterior à última restauração e consome o snapshot.
  /// Devolve false quando não há nada para desfazer.
  Future<bool> desfazerUltimaRestauracao() =>
      ConclusoesRevisaoRepositorio.exclusivo(_desfazerUltimaRestauracao);

  Future<bool> _desfazerUltimaRestauracao() async {
    final snapshot = snapshotGuardado;
    if (snapshot == null) return false;
    await _aplicarSubstituindo(ImportService.parseBackup(snapshot.json));
    await descartarSnapshot();
    return true;
  }

  /// Mescla dados e recibos sob o mesmo lock das conclusões. Preferências e
  /// planejamento pessoais permanecem locais, conforme a ação anunciada na UI.
  Future<void> mesclar(
    BackupImportado backup,
  ) => ConclusoesRevisaoRepositorio.exclusivo(() async {
    await _ref
        .read(ambientesProvider.notifier)
        .mesclar(backup.ambientesOuGeral(DateTime.now()));
    await _ref.read(materiasProvider.notifier).mesclar(backup.materias);
    await _ref.read(topicosProvider.notifier).mesclar(backup.topicos);
    await _ref.read(aulasProvider.notifier).mesclar(backup.aulas);
    await _ref.read(registrosProvider.notifier).mesclar(backup.registros);
    // Recibos locais são definitivos: um snapshot antigo não pode reabrir
    // a revisão concluída nem recriá-la após exclusão intencional pelo usuário.
    // recuperar() não reaplica recibos já aplicados, justamente para respeitar
    // essa exclusão; portanto a proteção precisa acontecer antes da mesclagem.
    final journal = ConclusoesRevisaoRepositorio.box;
    final concluidas = {
      ...journal.keys,
      ...backup.conclusoesRevisao.map((recibo) => recibo['id']),
    };
    await _ref
        .read(revisoesProvider.notifier)
        .mesclar(
          backup.revisoes
              .where(
                (revisao) =>
                    !concluidas.contains(revisao.id) ||
                    // Recibo importado bloqueia versão pendente, mas permite
                    // restaurar a versão concluída contida no próprio backup.
                    (revisao.feita && !journal.containsKey(revisao.id)),
              )
              .toList(),
        );
    await _ref.read(leiturasProvider.notifier).mesclar(backup.leituras);
    await _ref.read(simuladosProvider.notifier).mesclar(backup.simulados);
    await _ref.read(resumosProvider.notifier).mesclar(backup.resumos);
    await _ref
        .read(questoesErradasProvider.notifier)
        .mesclar(backup.questoesErradas);
    await _ref.read(anexosQuestaoRepositorioProvider).mesclar(backup.anexos);
    for (final recibo in backup.conclusoesRevisao) {
      if (!journal.containsKey(recibo['id'])) {
        await journal.put(recibo['id'], recibo);
      }
    }
    await ConclusoesRevisaoRepositorio.recuperar();
    _ref.invalidate(registrosProvider);
    _ref.invalidate(revisoesProvider);
  });

  /// Ordem filhos→pais, igual a [ApagarDadosUseCase.apagarTudo]: nenhuma
  /// leitura no meio do processo vê filho apontando para pai que já sumiu.
  Future<void> _aplicarSubstituindo(BackupImportado backup) async {
    final agora = DateTime.now();
    // `ambientes` fica FORA da regra do D-01 de propósito: sua ausência já tem
    // tratamento próprio e não-destrutivo em `ambientesOuGeral`, que injeta o
    // "Geral" — que é onde as matérias de um backup pré-Ambientes caem via
    // `fromJson`. Pular a substituição aqui deixaria essas matérias apontando
    // para um ambiente que não existe.
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
    // Núcleo da versão 1 do formato: estas chaves existem em TODO backup que o
    // app já gerou, então substituem sempre. Pular uma delas por ausência
    // deixaria filho apontando para pai trocado (tópico órfão de matéria nova)
    // — inconsistência pior que o wipe.
    await _ref.read(materiasProvider.notifier).substituirTudo(backup.materias);
    await _ref.read(topicosProvider.notifier).substituirTudo(backup.topicos);
    await _ref
        .read(registrosProvider.notifier)
        .substituirTudo(backup.registros);
    await _ref.read(revisoesProvider.notifier).substituirTudo(backup.revisoes);
    await _ref.read(leiturasProvider.notifier).substituirTudo(backup.leituras);

    // D-01 — coleções que entraram no formato DEPOIS da versão 1. Um backup
    // gerado antes delas não tem a chave, e `lista()` devolve `[]`: substituir
    // com isso apagava resumos, caderno de erros e fotos de quem restaurava,
    // em silêncio. Mesmo cuidado que `configuracoes` já tinha por ser nulável.
    //
    // A regra é sobre o que o ARQUIVO diz, não sobre o que ele tem:
    // `"resumos": []` é o arquivo falando vazio e zera; chave ausente é o
    // arquivo calado e não decide nada.
    if (backup.mencionou('aulas')) {
      await _ref.read(aulasProvider.notifier).substituirTudo(backup.aulas);
    }
    if (backup.mencionou('simulados')) {
      await _ref
          .read(simuladosProvider.notifier)
          .substituirTudo(backup.simulados);
    }
    if (backup.mencionou('resumos')) {
      await _ref.read(resumosProvider.notifier).substituirTudo(backup.resumos);
    }
    if (backup.mencionou('questoesErradas')) {
      await _ref
          .read(questoesErradasProvider.notifier)
          .substituirTudo(backup.questoesErradas);
    }
    if (backup.mencionou('anexos')) {
      await _ref
          .read(anexosQuestaoRepositorioProvider)
          .substituirTudo(backup.anexos);
    }
    // `planejamento` também é do núcleo v1 e `jsonCompleto` sempre o escreve
    // (mapa vazio quando não há cronograma), então segue substituindo sempre.
    await _ref
        .read(planejamentoProvider.notifier)
        .substituir(backup.planejamento);
    if (backup.mencionou('extensoes')) {
      final configBox = Hive.box<Map>(HiveBoxes.config);
      for (final chave in ['planoDiario', 'concursos']) {
        final valor = backup.extensoes[chave];
        if (valor == null) {
          await configBox.delete(chave);
        } else {
          await configBox.put(chave, valor);
        }
      }
    }
    if (Hive.isBoxOpen('conclusoes_revisao')) {
      final journal = Hive.box<Map>('conclusoes_revisao');
      await journal.clear();
      if (backup.mencionou('conclusoesRevisao')) {
        await journal.putAll({
          for (final item in backup.conclusoesRevisao) item['id']: item,
        });
      }
      await ConclusoesRevisaoRepositorio.recuperar();
      _ref.invalidate(registrosProvider);
      _ref.invalidate(revisoesProvider);
    }

    // Preferências só são tocadas quando o arquivo as traz: backup antigo (sem
    // a chave) não pode zerar a meta semanal de quem está restaurando.
    final preferencias = backup.configuracoes;
    if (preferencias != null) {
      await _ref
          .read(configuracoesProvider.notifier)
          .salvar(preferencias.copyWith(limparAmbienteAtivo: true));
    }

    // As revisões restauradas têm ids novos: os lembretes agendados apontavam
    // para o conjunto antigo e ficariam órfãos no sistema operacional.
    await NotificacoesService.cancelarTodas();
    final configRestaurada = _ref.read(configuracoesProvider);
    await NotificacoesService.agendarLembreteDiario(
      configRestaurada.horaLembreteEstudo,
    );
    for (final revisao in _ref.read(revisoesProvider)) {
      await NotificacoesRevisao.sincronizar(
        revisao,
        configRestaurada.horaNotificacao,
      );
    }
  }
}

final backupUseCaseProvider = Provider((ref) => BackupUseCase(ref));
