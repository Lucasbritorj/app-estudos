import '../core/notificacoes/notificacoes_service.dart';
import '../data/models/revisao.dart';

/// Ponto único da coreografia de lembrete de revisão: toda mudança de data
/// ou estado passa por aqui — cancela o agendamento anterior e agenda o novo
/// somente se a revisão continua pendente. Antes essa dupla
/// cancelar/agendar estava copiada em quatro fluxos diferentes.
class NotificacoesRevisao {
  static Future<void> sincronizar(Revisao revisao, int hora) async {
    await NotificacoesService.cancelar(revisao.id);
    if (!revisao.feita) {
      await NotificacoesService.agendarRevisao(
        id: revisao.id,
        titulo: revisao.titulo,
        dia: revisao.dataAgendada,
        hora: hora,
      );
    }
  }
}
