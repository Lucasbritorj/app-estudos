import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notificacoes/notificacoes_service.dart';
import '../data/repositories/repositorios.dart';

/// Exclusão de matéria com cascata explícita — num doc-store sem FK, a
/// integridade referencial é responsabilidade da aplicação.
class MateriaUseCase {
  MateriaUseCase(this._ref);
  final Ref _ref;

  /// Remove a matéria e os dependentes estruturais: tópicos, aulas e
  /// revisões PENDENTES (com seus lembretes no SO). Ficam de propósito:
  /// - registros de horas: são o log histórico (a UI promete isso);
  /// - revisões feitas: contam XP na gamificação — apagar rebaixaria nível.
  ///
  /// As aulas saem daqui por `removerOnde`, sem passar por
  /// [AulaUseCase.excluirEmCascata] — chamá-la em laço releria os providers a
  /// cada iteração e faria N passadas sobre as revisões. Em troca, a limpeza
  /// de `RegistroHora.aulaId` que ela faz precisa ser repetida aqui (D-04).
  Future<void> excluirEmCascata(String materiaId) async {
    final pendentes = _ref
        .read(revisoesProvider)
        .where((r) => r.materiaId == materiaId && !r.feita)
        .toList();
    for (final r in pendentes) {
      await NotificacoesService.cancelar(r.id);
    }
    await _ref
        .read(revisoesProvider.notifier)
        .removerOnde((r) => r.materiaId == materiaId && !r.feita);
    await _ref
        .read(topicosProvider.notifier)
        .removerOnde((t) => t.materiaId == materiaId);
    // D-04 pela porta da matéria: as aulas somem logo abaixo, e sem isto o
    // `aulaId` dos registros ficaria apontando para uma aula inexistente —
    // exatamente o defeito que `AulaUseCase` fecha no caminho direto. Como o
    // registro é log histórico e nunca é apagado, a referência morta
    // sobreviveria para sempre. Lido ANTES do `removerOnde`, senão a lista de
    // ids já veio vazia.
    final idsDasAulas = _ref
        .read(aulasProvider)
        .where((a) => a.materiaId == materiaId)
        .map((a) => a.id)
        .toSet();
    if (idsDasAulas.isNotEmpty) {
      final orfaos = _ref
          .read(registrosProvider)
          .where((r) => r.aulaId != null && idsDasAulas.contains(r.aulaId))
          .toList();
      final agora = DateTime.now();
      for (final r in orfaos) {
        await _ref.read(registrosProvider.notifier).salvar(r.semAula(agora));
      }
    }

    await _ref
        .read(aulasProvider.notifier)
        .removerOnde((a) => a.materiaId == materiaId);
    await _ref.read(materiasProvider.notifier).remover(materiaId);
  }
}

final materiaUseCaseProvider = Provider((ref) => MateriaUseCase(ref));
