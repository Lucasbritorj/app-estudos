import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notificacoes/notificacoes_service.dart';
import '../data/models/topico.dart';
import '../data/repositories/repositorios.dart';

/// Exclusão de tópico com cascata explícita — num doc-store sem FK, a
/// integridade referencial é responsabilidade da aplicação. Espelha
/// `MateriaUseCase` e `AulaUseCase`; antes, excluir tópico era um
/// `repositorio.remover(id)` cru na tela e deixava para trás:
/// - revisão PENDENTE do tópico viva, agendada e notificando no SO, com a
///   cadeia FSRS gerando sucessoras para algo que não existe mais;
/// - subtópicos com `parentId` pendurado (a árvore os promovia a raiz,
///   achatando a hierarquia sem o usuário pedir);
/// - arestas de pré-requisito apontando para o tópico apagado.
class TopicoUseCase {
  TopicoUseCase(this._ref);
  final Ref _ref;

  /// Remove o tópico e resolve os dependentes:
  /// - subtópicos diretos sobem para o pai do excluído (a hierarquia encolhe
  ///   um nível em vez de desabar para a raiz);
  /// - pré-requisitos que apontavam para ele são removidos das arestas;
  /// - revisões PENDENTES do tópico saem (com lembrete cancelado). Revisões
  ///   FEITAS ficam: contam XP, e apagá-las rebaixaria o nível — mesmo
  ///   critério de `MateriaUseCase`;
  /// - registros de horas NUNCA são excluídos: são o log histórico que a UI
  ///   promete preservar. O `topicoId` pendurado é inerte — todo consumidor
  ///   (mapa, fronteira, métricas) já filtra por id existente, e o export do
  ///   modelo estrela emite a dimensão sintética.
  Future<void> excluirEmCascata(String topicoId) async {
    final topicos = _ref.read(topicosProvider);
    final alvo = topicos.where((t) => t.id == topicoId).firstOrNull;
    if (alvo == null) return;

    final pendentes = _ref
        .read(revisoesProvider)
        .where((r) => r.topicoId == topicoId && !r.feita)
        .toList();
    for (final r in pendentes) {
      await NotificacoesService.cancelar(r.id);
    }
    await _ref
        .read(revisoesProvider.notifier)
        .removerOnde((r) => r.topicoId == topicoId && !r.feita);

    final repositorio = _ref.read(topicosProvider.notifier);
    for (final t in topicos) {
      if (t.id == topicoId) continue;
      final viraOrfao = t.parentId == topicoId;
      final citaComoPre = t.prerequisitos.contains(topicoId);
      if (!viraOrfao && !citaComoPre) continue;
      await repositorio.salvar(
        t.copyWith(
          // `limparParent` cobre o caso do excluído ser raiz: o filho precisa
          // virar raiz também, e `parentId: null` cairia no `??`.
          limparParent: viraOrfao && alvo.parentId == null,
          parentId: viraOrfao ? alvo.parentId : t.parentId,
          prerequisitos: citaComoPre
              ? [
                  for (final id in t.prerequisitos)
                    if (id != topicoId) id,
                ]
              : t.prerequisitos,
        ),
      );
    }

    await repositorio.remover(topicoId);
  }


  /// Valida se mover [topicoId] para ser filho de [novoPaiId] é seguro.
  ///
  /// Pura e estática (sem `Ref`): testável fora do Flutter, mesmo padrão de
  /// `MapaEstudosService.criariaCiclo`. Mora aqui, ao lado de
  /// [excluirEmCascata], porque é regra de aplicação sobre a árvore — não
  /// invariante do modelo: um `Topico` isolado não sabe quem são seus
  /// descendentes, a resposta depende da COLEÇÃO.
  ///
  /// `novoPaiId == null` (virar raiz) é sempre válido: não há como isso
  /// fechar ciclo. Bloqueia:
  /// - mover para si mesmo;
  /// - mover para um descendente (filho, neto, ...) — fecharia ciclo em
  ///   `parentId`, e um ciclo aí já fez tópicos SUMIREM da árvore antes de
  ///   `_emOrdemHierarquica` (topicos_screen.dart) aprender a resistir.
  ///   Prevenir aqui é melhor que só resistir na renderização;
  /// - mover para tópico de outra matéria (a hierarquia é por matéria).
  static bool podeMoverPara(
    List<Topico> topicos,
    String topicoId,
    String? novoPaiId,
  ) {
    if (novoPaiId == null) return true;
    if (novoPaiId == topicoId) return false;

    final porId = {for (final t in topicos) t.id: t};
    final alvo = porId[topicoId];
    final novoPai = porId[novoPaiId];
    if (alvo == null || novoPai == null) return false;
    if (alvo.materiaId != novoPai.materiaId) return false;

    // Sobe a ascendência do destino: se `topicoId` aparecer no caminho até a
    // raiz, o destino é descendente do próprio tópico e mover fecharia um
    // ciclo. `visitados` blinda contra ciclo JÁ existente na massa (o import
    // de backup grava `parentId` sem validar) — sem isso essa subida poderia
    // não terminar.
    final visitados = <String>{};
    var atual = novoPai.parentId;
    while (atual != null) {
      if (atual == topicoId) return false;
      if (!visitados.add(atual)) break;
      atual = porId[atual]?.parentId;
    }
    return true;
  }

  /// Exclusão em massa dos tópicos de uma matéria (menu "Excluir todos").
  /// Passa pela mesma cascata, então nenhuma revisão pendente sobrevive.
  Future<void> excluirTodosDaMateria(String materiaId) async {
    final ids = _ref
        .read(topicosProvider)
        .where((t) => t.materiaId == materiaId)
        .map((t) => t.id)
        .toList();
    for (final id in ids) {
      await excluirEmCascata(id);
    }
  }
}

final topicoUseCaseProvider = Provider((ref) => TopicoUseCase(ref));
