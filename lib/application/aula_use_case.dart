import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notificacoes/notificacoes_service.dart';
import '../data/repositories/repositorios.dart';

/// Exclusão de aula com cascata explícita (D-04) — num doc-store sem FK, a
/// integridade referencial é responsabilidade da aplicação. Sem isto,
/// `RegistroHora.aulaId` e `Revisao.aulaId` ficavam apontando para uma aula
/// que não existe mais. Espelha `MateriaUseCase.excluirEmCascata`.
class AulaUseCase {
  AulaUseCase(this._ref);
  final Ref _ref;

  /// Remove a aula e resolve os dependentes:
  /// - revisões PENDENTES da cadeia desta aula: removidas (com lembrete
  ///   cancelado no SO) — a cadeia existe PARA revisar o que a aula
  ///   ensinou; sem a aula, revisão pendente é órfã de verdade, nada a
  ///   reter. Revisões FEITAS ficam de propósito (contam XP na
  ///   gamificação — apagar rebaixaria nível, mesmo critério de
  ///   MateriaUseCase).
  /// - registros de horas: NUNCA excluídos — são o log histórico que a UI
  ///   promete preservar (mesmo quando a matéria inteira é excluída). Só o
  ///   vínculo com a aula é limpo (`semAula`), pra não sobreviver um
  ///   `aulaId` que não resolve mais nada.
  Future<void> excluirEmCascata(String aulaId) async {
    final pendentes = _ref
        .read(revisoesProvider)
        .where((r) => r.aulaId == aulaId && !r.feita)
        .toList();
    for (final r in pendentes) {
      await NotificacoesService.cancelar(r.id);
    }
    await _ref
        .read(revisoesProvider.notifier)
        .removerOnde((r) => r.aulaId == aulaId && !r.feita);

    final orfaos = _ref
        .read(registrosProvider)
        .where((r) => r.aulaId == aulaId)
        .toList();
    final agora = DateTime.now();
    for (final r in orfaos) {
      await _ref.read(registrosProvider.notifier).salvar(r.semAula(agora));
    }

    await _ref.read(aulasProvider.notifier).remover(aulaId);
  }
}

final aulaUseCaseProvider = Provider((ref) => AulaUseCase(ref));
