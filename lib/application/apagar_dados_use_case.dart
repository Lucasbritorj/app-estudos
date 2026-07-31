import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:hive_ce/hive.dart';

import '../core/notificacoes/notificacoes_service.dart';
import '../data/local/hive_boxes.dart';
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
  int questoesErradas,
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
    questoesErradas: _ref.read(questoesErradasProvider).length,
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
    await _ref.read(questoesErradasProvider.notifier).substituirTudo([]);
    // Cascata do caderno de erros (F1): sem isto o wipe apagava as questões
    // mas deixava as fotos órfãs no box de anexos — bytes que nenhuma tela
    // referencia mais, ocupando espaço em disco para sempre.
    await _ref.read(anexosQuestaoRepositorioProvider).substituirTudo(const {});
    // Boxes de slot único (sem repositório/Notifier): prova em andamento e
    // cronômetro. Sem isto o wipe deixava uma prova cronometrada viva, que
    // reaparecia na tela de simulados apontando para matérias já apagadas.
    await Hive.box<Map>(HiveBoxes.execucaoProva).clear();
    await Hive.box<Map>(HiveBoxes.cronometro).clear();
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

    // Sem isto o usuário apagava tudo e continuava recebendo lembrete de
    // revisão inexistente, sem tela onde desligar. `cancelarTodas` é
    // best-effort: tolera falha de plataforma sem derrubar o wipe.
    await NotificacoesService.cancelarTodas();
  }
}

final apagarDadosUseCaseProvider = Provider((ref) => ApagarDadosUseCase(ref));
