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
    await _ref
        .read(aulasProvider.notifier)
        .removerOnde((a) => a.materiaId == materiaId);
    await _ref.read(materiasProvider.notifier).remover(materiaId);
  }
}

final materiaUseCaseProvider = Provider((ref) => MateriaUseCase(ref));
