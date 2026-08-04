import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../application/topico_use_case.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/notas_editor.dart';
import '../../data/models/materia.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/repositorios.dart';
import 'importar_edital.dart';

/// Tópicos de uma matéria, exibidos em hierarquia (parentId), com import
/// de conteúdo programático colado de edital.
class TopicosScreen extends ConsumerWidget {
  final Materia materia;

  const TopicosScreen({super.key, required this.materia});

  Future<void> _dialogoTopico(
    BuildContext context,
    WidgetRef ref, {
    Topico? existente,
    String? parentId,
  }) async {
    final nome = TextEditingController(text: existente?.nome ?? '');
    final notas = TextEditingController(text: existente?.notas ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existente == null
              ? (parentId == null ? 'Novo tópico' : 'Novo subtópico')
              : 'Editar tópico',
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nome,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              NotasEditor(controller: notas),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final texto = nome.text.trim();
              if (texto.isEmpty) return;
              final topico =
                  existente?.copyWith(nome: texto, notas: notas.text.trim()) ??
                  Topico(
                    id: const Uuid().v4(),
                    materiaId: materia.id,
                    parentId: parentId,
                    nome: texto,
                    notas: notas.text.trim(),
                  );
              ref.read(topicosProvider.notifier).salvar(topico);
              Navigator.pop(dialogContext);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  /// Move [topico] para dentro de [novoPaiId] (`null` = vira raiz). Revalida
  /// `TopicoUseCase.podeMoverPara` aqui — não confia só no seletor ter desabilitado
  /// a opção — então nenhum caminho grava um ciclo em `parentId`. Grava
  /// direto no repositório (sem cascata: mudar de posição na árvore não
  /// mexe em revisão nem em pré-requisito, diferente de excluir).
  void _mover(
    WidgetRef ref,
    List<Topico> topicosDaMateria,
    Topico topico,
    String? novoPaiId,
  ) {
    if (!TopicoUseCase.podeMoverPara(topicosDaMateria, topico.id, novoPaiId)) return;
    ref
        .read(topicosProvider.notifier)
        .salvar(
          topico.copyWith(
            parentId: novoPaiId,
            limparParent: novoPaiId == null,
          ),
        );
  }

  /// Seletor de destino para mover [topico] dentro da mesma matéria: "Tornar
  /// tópico raiz" + todos os outros tópicos, na mesma ordem/indentação da
  /// tela. Um destino que fecharia ciclo em `parentId` (mover para si mesmo,
  /// para um filho, neto, ...) fica DESABILITADO em vez de omitido — o
  /// usuário vê que o tópico existe e entende por que não pode escolher ali
  /// (ver `TopicoUseCase.podeMoverPara`).
  ///
  /// Cada opção grava direto no `onPressed`/`onTap` e só then fecha o
  /// diálogo — de propósito, não encadeada como continuação do Future do
  /// `showDialog`. Encadeada, a gravação só dispararia depois da animação de
  /// fechamento assentar.
  Future<void> _dialogoMover(
    BuildContext context,
    WidgetRef ref,
    Topico topico,
    List<Topico> topicosDaMateria,
  ) {
    final ordenados = _emOrdemHierarquica(topicosDaMateria);
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Mover "${topico.nome}"'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              _mover(ref, topicosDaMateria, topico, null);
              Navigator.pop(dialogContext);
            },
            child: const Text('Tornar tópico raiz'),
          ),
          for (final (candidato, profundidade) in ordenados)
            if (candidato.id != topico.id)
              _opcaoMover(
                dialogContext,
                ref,
                topicosDaMateria,
                topico,
                candidato,
                profundidade,
              ),
        ],
      ),
    );
  }

  /// Uma linha do seletor de destino (ver `_dialogoMover`).
  Widget _opcaoMover(
    BuildContext dialogContext,
    WidgetRef ref,
    List<Topico> topicosDaMateria,
    Topico topico,
    Topico candidato,
    int profundidade,
  ) {
    final podeMover = TopicoUseCase.podeMoverPara(
      topicosDaMateria,
      topico.id,
      candidato.id,
    );
    return ListTile(
      enabled: podeMover,
      contentPadding: EdgeInsets.only(left: 24 + profundidade * 16.0, right: 24),
      title: Text(candidato.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: podeMover
          ? null
          : const Text(
              'criaria ciclo',
              style: TextStyle(color: StatusColors.critico, fontSize: 11),
            ),
      onTap: podeMover
          ? () {
              _mover(ref, topicosDaMateria, topico, candidato.id);
              Navigator.pop(dialogContext);
            }
          : null,
    );
  }

  /// Lista ordenada em profundidade: cada raiz seguida dos filhos.
  List<(Topico, int)> _emOrdemHierarquica(List<Topico> topicos) {
    final porPai = <String?, List<Topico>>{};
    for (final t in topicos) {
      porPai.putIfAbsent(t.parentId, () => []).add(t);
    }
    final resultado = <(Topico, int)>[];
    final emitidos = <String>{};

    void visitar(String? paiId, int profundidade) {
      for (final t in porPai[paiId] ?? const <Topico>[]) {
        // Emitir uma única vez resolve os dois casos degenerados de hierarquia
        // que o import de backup aceita (nada valida `parentId`): ciclo
        // A→B→A e auto-pai. Sem isso a recursão não terminava e, na poda de
        // órfãos, os tópicos do ciclo simplesmente desapareciam da tela
        // continuando gravados no Hive.
        if (!emitidos.add(t.id)) continue;
        resultado.add((t, profundidade));
        visitar(t.id, profundidade + 1);
      }
    }

    visitar(null, 0);
    // Não alcançado a partir da raiz: órfão (pai apagado) ou preso em ciclo.
    // Entra como raiz para nunca sumir da lista.
    for (final t in topicos) {
      if (!emitidos.add(t.id)) continue;
      resultado.add((t, 0));
      visitar(t.id, 1);
    }
    return resultado;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(topicosProvider);
    final topicos = ref.read(topicosProvider.notifier).daMateria(materia.id);
    final ordenados = _emOrdemHierarquica(topicos);

    return Scaffold(
      appBar: AppBar(
        title: Text(materia.nome),
        actions: [
          IconButton(
            tooltip: 'Importar do edital',
            icon: const Icon(Icons.content_paste_go),
            onPressed: () =>
                mostrarImportarEdital(context, ref, materiaFixa: materia),
          ),
          if (topicos.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (acao) async {
                if (acao != 'excluir-todos') return;
                final confirmado = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: Text(
                      'Excluir os ${topicos.length} tópicos de '
                      '${materia.nome}?',
                    ),
                    content: const Text(
                      'Remove todos os tópicos e subtópicos desta '
                      'matéria. Registros de horas não são apagados. '
                      'Não há como desfazer.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Excluir todos'),
                      ),
                    ],
                  ),
                );
                if (confirmado != true) return;
                await ref
                    .read(topicoUseCaseProvider)
                    .excluirTodosDaMateria(materia.id);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'excluir-todos',
                  child: Text('Excluir todos os tópicos'),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // Empilhada sobre Matérias, que também tem FAB — ver o porquê em
        // dashboard_screen.dart.
        heroTag: 'fab-topicos',
        onPressed: () => _dialogoTopico(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ordenados.isEmpty
          ? const Center(
              child: Text(
                'Sem tópicos. Toque em + ou importe o conteúdo do edital.',
              ),
            )
          : ConteudoCentral(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: ordenados.length,
                itemBuilder: (context, i) {
                  final (topico, profundidade) = ordenados[i];
                  return Padding(
                    padding: EdgeInsets.only(left: profundidade * 16.0),
                    child: CheckboxListTile(
                      value: topico.concluido,
                      dense: profundidade > 0,
                      onChanged: (v) => ref
                          .read(topicosProvider.notifier)
                          .salvar(topico.copyWith(concluido: v ?? false)),
                      title: Text(topico.nome),
                      secondary: PopupMenuButton<String>(
                        onSelected: (acao) {
                          if (acao == 'editar') {
                            _dialogoTopico(context, ref, existente: topico);
                          } else if (acao == 'sub') {
                            _dialogoTopico(context, ref, parentId: topico.id);
                          } else if (acao == 'mover') {
                            _dialogoMover(context, ref, topico, topicos);
                          } else if (acao == 'notas') {
                            showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text('Notas — ${topico.nome}'),
                                content: SingleChildScrollView(
                                  child: NotasRicasView(texto: topico.notas),
                                ),
                              ),
                            );
                          } else if (acao == 'excluir') {
                            // Cascata explícita: sem ela a revisão pendente do
                            // tópico ficava viva e agendada, e os subtópicos
                            // desabavam para a raiz.
                            ref
                                .read(topicoUseCaseProvider)
                                .excluirEmCascata(topico.id);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'editar',
                            child: Text('Editar'),
                          ),
                          const PopupMenuItem(
                            value: 'sub',
                            child: Text('Adicionar subtópico'),
                          ),
                          const PopupMenuItem(
                            value: 'mover',
                            child: Text('Mover'),
                          ),
                          if (topico.notas.isNotEmpty)
                            const PopupMenuItem(
                              value: 'notas',
                              child: Text('Ver notas'),
                            ),
                          const PopupMenuItem(
                            value: 'excluir',
                            child: Text('Excluir'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
