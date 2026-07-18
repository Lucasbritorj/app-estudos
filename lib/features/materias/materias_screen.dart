import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/materia_use_case.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar_cor.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/materia.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../ambientes/ambiente_selector.dart';
import '../../domain/gamificacao_service.dart';
import '../../domain/stats_service.dart';
import '../aulas/aulas_screen.dart';
import 'importar_edital.dart';
import 'materia_dialog.dart';
import 'topicos_screen.dart';

class MateriasScreen extends ConsumerWidget {
  const MateriasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materias = ref.watch(materiasDoAmbienteProvider);
    final registros = ref.watch(registrosProvider);
    final minutosPorMateria = StatsService.minutosPorMateria(registros);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Matérias'),
        actions: [
          IconButton(
            tooltip: 'Importar edital (colar texto)',
            icon: const Icon(Icons.content_paste_go),
            onPressed: () => mostrarImportarEdital(context, ref),
          ),
          const AmbienteSelector(),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => mostrarDialogoMateria(context, ref),
        child: const Icon(Icons.add),
      ),
      body: materias.isEmpty
          ? const Center(child: Text('Sem matérias. Toque em + para começar.'))
          : ConteudoCentral(
              child: ListView.builder(
                itemCount: materias.length,
                itemBuilder: (context, i) {
                  final materia = materias[i];
                  final minutos = minutosPorMateria[materia.id] ?? 0;
                  return ListTile(
                    leading: AvatarCor(slot: materia.corSlot),
                    title: Text(materia.nome),
                    subtitle: Text(
                      'peso ${materia.peso} · ${formatarMinutos(minutos)} · nível ${GamificacaoService.nivelPara(minutos)}',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TopicosScreen(materia: materia),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Aulas (PDFs)',
                          icon: const Icon(Icons.menu_book_outlined, size: 20),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AulasScreen(materia: materia),
                            ),
                          ),
                        ),
                        if (materia.notas.isNotEmpty)
                          IconButton(
                            tooltip: 'Ver notas',
                            icon: const Icon(
                              Icons.sticky_note_2_outlined,
                              size: 20,
                            ),
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text('Notas — ${materia.nome}'),
                                content: SingleChildScrollView(
                                  child: Text(materia.notas),
                                ),
                              ),
                            ),
                          ),
                        _MenuMateria(materia: materia),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _MenuMateria extends ConsumerWidget {
  final Materia materia;

  const _MenuMateria({required this.materia});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (acao) async {
        if (acao == 'editar') {
          await mostrarDialogoMateria(context, ref, existente: materia);
        } else if (acao == 'excluir') {
          final confirmado = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text('Excluir ${materia.nome}?'),
              content: const Text(
                'Tópicos, aulas e revisões pendentes desta matéria também '
                'serão excluídos. Os registros de horas permanecem no '
                'histórico.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Excluir'),
                ),
              ],
            ),
          );
          if (confirmado == true) {
            await ref.read(materiaUseCaseProvider).excluirEmCascata(materia.id);
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'editar', child: Text('Editar')),
        PopupMenuItem(value: 'excluir', child: Text('Excluir')),
      ],
    );
  }
}
