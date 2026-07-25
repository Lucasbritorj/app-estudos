import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/configuracoes_repositorio.dart';
import '../data/repositories/planejamento_repositorio.dart';
import '../data/repositories/repositorios.dart';

/// Contagem de itens por coleção — base do diálogo de confirmação do wipe
/// (a UI monta "isso vai apagar N registros, M matérias..." a partir daqui).
/// Leitura pura do state em memória de cada repositório (sem tocar o Hive),
/// por isso é síncrona — nada de `Future`.
typedef ContagemDados = ({
  int registros,
  int materias,
  int topicos,
  int aulas,
  int revisoes,
  int resumos,
  int leituras,
  int simulados,
  int ambientes,
});

/// Apagar tudo (wipe out): reset total dos dados do usuário — cenário
/// "quero recomeçar do zero" em Configurações. Espelha o padrão de
/// `RevisaoUseCase`: orquestração fora da UI, testável sem widget.
class ApagarDadosUseCase {
  ApagarDadosUseCase(this._ref);
  final Ref _ref;

  /// Contagens atuais, para o diálogo de confirmação (fora deste escopo)
  /// mostrar o que será perdido antes do usuário confirmar a operação
  /// irreversível.
  ContagemDados contarRegistrosParaApagar() => (
    registros: _ref.read(registrosProvider).length,
    materias: _ref.read(materiasProvider).length,
    topicos: _ref.read(topicosProvider).length,
    aulas: _ref.read(aulasProvider).length,
    revisoes: _ref.read(revisoesProvider).length,
    resumos: _ref.read(resumosProvider).length,
    leituras: _ref.read(leiturasProvider).length,
    simulados: _ref.read(simuladosProvider).length,
    ambientes: _ref.read(ambientesProvider).length,
  );

  /// Apaga TODOS os dados do usuário. `substituirTudo([])` faz `box.clear()`
  /// — hard delete, SEM tombstone (diferente do `remover()` de Matéria/
  /// Registro, que só marca `excluidaEm` para sync). Não tem undo: quem
  /// chama isso já confirmou com o usuário.
  ///
  /// Ordem filhos→pais (revisão/registro dependem de matéria/tópico/aula;
  /// aula/tópico dependem de matéria; matéria depende de ambiente). O Hive
  /// não impõe integridade referencial — `substituirTudo` de qualquer uma
  /// isoladamente já funcionaria — mas assim nenhuma leitura no meio do
  /// processo pode ver um filho apontando pra um pai que já sumiu.
  Future<void> apagarTudo() async {
    await _ref.read(revisoesProvider.notifier).substituirTudo([]);
    await _ref.read(registrosProvider.notifier).substituirTudo([]);
    await _ref.read(aulasProvider.notifier).substituirTudo([]);
    await _ref.read(topicosProvider.notifier).substituirTudo([]);
    await _ref.read(resumosProvider.notifier).substituirTudo([]);
    await _ref.read(leiturasProvider.notifier).substituirTudo([]);
    await _ref.read(simuladosProvider.notifier).substituirTudo([]);
    await _ref.read(materiasProvider.notifier).substituirTudo([]);
    await _ref.read(ambientesProvider.notifier).substituirTudo([]);
    // NÃO é `substituir({})`: aquele é escopado por ambiente ativo (grava só
    // numa chave) e deixaria cronograma de outro ambiente (ou a chave global
    // legada) vivo — `apagarTudo` limpa o box inteiro. Ver PlanejamentoRepositorio.
    await _ref.read(planejamentoProvider.notifier).apagarTudo();
    await _ref
        .read(configuracoesProvider.notifier)
        .salvar(
          _ref
              .read(configuracoesProvider)
              .copyWith(limparAmbienteAtivo: true),
        );

    // NotificacoesRevisao só expõe sincronizar(revisao, hora) — cancela e
    // reagenda UMA revisão por vez; NotificacoesService não tem
    // cancelarTodas/cancelAll (checado antes de escrever isto). O wipe não
    // cancela notificações pendentes: ficam órfãs até expirar sozinhas
    // (best-effort, sem crash — NotificacoesService já tolera falha de
    // plataforma). Ver relatório da onda 1 para essa lacuna.
  }
}

final apagarDadosUseCaseProvider = Provider((ref) => ApagarDadosUseCase(ref));
