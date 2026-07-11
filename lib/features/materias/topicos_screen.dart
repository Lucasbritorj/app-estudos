import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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

  Future<void> _dialogoTopico(BuildContext context, WidgetRef ref,
      {Topico? existente, String? parentId}) async {
    final nome = TextEditingController(text: existente?.nome ?? '');
    final notas = TextEditingController(text: existente?.notas ?? '');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existente == null
            ? (parentId == null ? 'Novo tópico' : 'Novo subtópico')
            : 'Editar tópico'),
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
              final topico = existente?.copyWith(
                      nome: texto, notas: notas.text.trim()) ??
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

  /// Lista ordenada em profundidade: cada raiz seguida dos filhos.
  List<(Topico, int)> _emOrdemHierarquica(List<Topico> topicos) {
    final porPai = <String?, List<Topico>>{};
    for (final t in topicos) {
      porPai.putIfAbsent(t.parentId, () => []).add(t);
    }
    final ids = topicos.map((t) => t.id).toSet();
    final resultado = <(Topico, int)>[];

    void visitar(String? paiId, int profundidade) {
      for (final t in porPai[paiId] ?? const <Topico>[]) {
        resultado.add((t, profundidade));
        visitar(t.id, profundidade + 1);
      }
    }

    visitar(null, 0);
    // Órfãos (pai apagado): tratar como raiz para nunca sumirem da lista.
    for (final t in topicos) {
      if (t.parentId != null && !ids.contains(t.parentId)) {
        resultado.add((t, 0));
        visitar(t.id, 1);
      }
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _dialogoTopico(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ordenados.isEmpty
          ? const Center(
              child: Text(
                  'Sem tópicos. Toque em + ou importe o conteúdo do edital.'))
          : ListView.builder(
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
                        } else if (acao == 'notas') {
                          showDialog<void>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text('Notas — ${topico.nome}'),
                              content: SingleChildScrollView(
                                  child:
                                      NotasRicasView(texto: topico.notas)),
                            ),
                          );
                        } else if (acao == 'excluir') {
                          ref
                              .read(topicosProvider.notifier)
                              .remover(topico.id);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'editar', child: Text('Editar')),
                        const PopupMenuItem(
                            value: 'sub', child: Text('Adicionar subtópico')),
                        if (topico.notas.isNotEmpty)
                          const PopupMenuItem(
                              value: 'notas', child: Text('Ver notas')),
                        const PopupMenuItem(
                            value: 'excluir', child: Text('Excluir')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
