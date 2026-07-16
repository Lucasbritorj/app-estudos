import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/models/aula.dart';
import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';
import '../data/repositories/configuracoes_repositorio.dart';
import '../data/repositories/repositorios.dart';
import '../domain/aula_service.dart';
import '../domain/revisao_service.dart';
import 'notificacoes_revisao.dart';

/// Resultado estruturado do registro de sessão — a UI decide o texto.
typedef ResultadoSessao = ({
  Aula? aulaAtualizada,
  bool aulaConcluiuAgora,
  Revisao? primeiraRevisao,
  int revisoesReancoradas,
});

/// Orquestra o fluxo de gravação de uma sessão de estudo: registro →
/// progresso da aula → cadeia de revisões → reancoragem → notificações.
/// Era o corpo de RegistroForm._salvar; aqui é unidade testável sem UI.
class SessaoEstudoUseCase {
  SessaoEstudoUseCase(this._ref);
  final Ref _ref;

  Future<ResultadoSessao> registrar(RegistroHora registro) async {
    await _ref.read(registrosProvider.notifier).salvar(registro);
    final config = _ref.read(configuracoesProvider);

    // Estudo teórico com aula: acumula páginas; concluir a aula é O gatilho
    // da cadeia de revisões (Revisão 1 nasce da data de conclusão do PDF).
    Aula? aulaAtualizada;
    var concluiuAgora = false;
    Revisao? primeira;
    final paginas =
        registro.tipo == TipoEstudo.teoria ? (registro.paginasLidas ?? 0) : 0;
    final aula = registro.aulaId == null
        ? null
        : _ref
            .read(aulasProvider)
            .where((a) => a.id == registro.aulaId)
            .firstOrNull;
    if (aula != null && paginas > 0) {
      final resultado =
          AulaService.aplicarSessao(aula, paginas, registro.data);
      aulaAtualizada = resultado.aula;
      concluiuAgora = resultado.concluiuAgora;
      await _ref.read(aulasProvider.notifier).salvar(resultado.aula);
      if (resultado.concluiuAgora) {
        final materia = _ref
            .read(materiasProvider)
            .where((m) => m.id == registro.materiaId)
            .firstOrNull;
        primeira = await criarCadeiaParaAula(
            resultado.aula, materia?.nome ?? 'Estudo');
      }
    }

    // Revisões pendentes do tópico reancoram no último estudo (prática).
    var reancoradas = const <Revisao>[];
    if (registro.topicoId != null) {
      reancoradas = RevisaoService.reagendarPorEstudo(
          _ref.read(revisoesProvider), registro.topicoId!, registro.data);
      // Lote: N revisões reancoradas custam uma escrita, não N recargas.
      await _ref.read(revisoesProvider.notifier).mesclar(reancoradas);
      for (final r in reancoradas) {
        await NotificacoesRevisao.sincronizar(r, config.horaNotificacao);
      }
    }

    return (
      aulaAtualizada: aulaAtualizada,
      aulaConcluiuAgora: concluiuAgora,
      primeiraRevisao: primeira,
      revisoesReancoradas: reancoradas.length,
    );
  }

  /// Gatilho da cadeia de revisões: dispara quando uma Aula é CONCLUÍDA
  /// (paginasLidas >= paginasTotais), nunca por sessão avulsa. Agenda só a
  /// Revisão 1 (menor intervalo configurado, ex.: 7d) a partir da data de
  /// conclusão do PDF — as seguintes nascem ao concluir cada revisão.
  Future<Revisao?> criarCadeiaParaAula(Aula aula, String materiaNome) async {
    final config = _ref.read(configuracoesProvider);
    final primeiro =
        RevisaoService.proximoIntervalo(config.intervalosRevisao, 0);
    if (primeiro == null) return null;

    // Uma cadeia por aula: se já existe revisão pendente da aula, não duplica.
    final jaExiste = _ref
        .read(revisoesProvider)
        .any((r) => r.aulaId == aula.id && !r.feita);
    if (jaExiste) return null;

    final base = aula.dataConclusao ?? DateTime.now();
    final revisao = Revisao(
      id: const Uuid().v4(),
      materiaId: aula.materiaId,
      aulaId: aula.id,
      titulo: '$materiaNome — ${aula.nome} (${primeiro}d)',
      dataAgendada: DateTime(base.year, base.month, base.day + primeiro),
      intervaloDias: primeiro,
    );
    await _ref.read(revisoesProvider.notifier).salvar(revisao);
    await NotificacoesRevisao.sincronizar(revisao, config.horaNotificacao);
    return revisao;
  }
}

final sessaoEstudoUseCaseProvider =
    Provider((ref) => SessaoEstudoUseCase(ref));
