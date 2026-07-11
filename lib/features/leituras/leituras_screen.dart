import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/leitura.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/leitura_service.dart';

class LeiturasScreen extends ConsumerWidget {
  const LeiturasScreen({super.key});

  Future<void> _novaLeitura(BuildContext context, WidgetRef ref) async {
    final materias =
        ref.read(materiasProvider).where((m) => !m.arquivada).toList();
    final titulo = TextEditingController();
    final pagInicio = TextEditingController(text: '1');
    final pagFim = TextEditingController();
    String? materiaId;
    var partes = 5.0;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: const Text('Nova leitura'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titulo,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Título *', hintText: 'Ex.: Manual de AFO'),
                ),
                if (materias.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: materiaId,
                    decoration: const InputDecoration(
                        labelText: 'Matéria (opcional)'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('— nenhuma —')),
                      for (final m in materias)
                        DropdownMenuItem<String?>(
                            value: m.id, child: Text(m.nome)),
                    ],
                    onChanged: (v) => materiaId = v,
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: pagInicio,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Pág. inicial *'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: pagFim,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Pág. final *'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Partes: ${partes.round()}'),
                ),
                Slider(
                  value: partes,
                  min: 2,
                  max: 10,
                  divisions: 8,
                  label: '${partes.round()}',
                  onChanged: (v) => setStateDialog(() => partes = v),
                ),
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
                final inicio = int.tryParse(pagInicio.text);
                final fim = int.tryParse(pagFim.text);
                if (titulo.text.trim().isEmpty ||
                    inicio == null ||
                    fim == null ||
                    fim < inicio) {
                  return;
                }
                final n = partes.round();
                ref.read(leiturasProvider.notifier).salvar(Leitura(
                      id: const Uuid().v4(),
                      titulo: titulo.text.trim(),
                      materiaId: materiaId,
                      paginaInicio: inicio,
                      paginaFim: fim,
                      partes: n,
                      partesConcluidas: List.filled(n, false),
                    ));
                Navigator.pop(dialogContext);
              },
              child: const Text('Criar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leituras = ref.watch(leiturasProvider);
    final materias = ref.watch(materiasProvider);
    final materiasPorId = {for (final m in materias) m.id: m};

    return Scaffold(
      appBar: AppBar(title: const Text('Leituras')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _novaLeitura(context, ref),
        child: const Icon(Icons.add),
      ),
      body: leituras.isEmpty
          ? const Center(
              child: Text('Sem leituras. Toque em + para dividir um PDF.',
                  style: TextStyle(color: VizColors.muted)))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: leituras.length,
              itemBuilder: (context, i) {
                final leitura = leituras[i];
                final materia = materiasPorId[leitura.materiaId];
                final lidas = LeituraService.paginasConcluidas(leitura);
                final progresso = LeituraService.progresso(leitura);
                return ListTile(
                  leading: CircleAvatar(
                    radius: 10,
                    backgroundColor: materia == null
                        ? VizColors.muted
                        : corDaSerie(materia.corSlot),
                  ),
                  title: Text(leitura.titulo),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'págs ${leitura.paginaInicio}–${leitura.paginaFim} · ${leitura.partes} partes · '
                          '$lidas/${leitura.totalPaginas} lidas (${(progresso * 100).toStringAsFixed(0)}%)'),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progresso,
                          minHeight: 5,
                          backgroundColor: VizColors.gridline,
                          color: materia == null
                              ? seriesColors[0]
                              : corDaSerie(materia.corSlot),
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: 'Excluir',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        ref.read(leiturasProvider.notifier).remover(leitura.id),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => _LeituraDetalhe(id: leitura.id)),
                  ),
                );
              },
            ),
    );
  }
}

class _LeituraDetalhe extends ConsumerWidget {
  final String id;

  const _LeituraDetalhe({required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leitura =
        ref.watch(leiturasProvider).where((l) => l.id == id).firstOrNull;
    if (leitura == null) {
      return const Scaffold(body: Center(child: Text('Leitura removida.')));
    }
    final blocos = LeituraService.dividir(
        leitura.paginaInicio, leitura.paginaFim, leitura.partes);

    return Scaffold(
      appBar: AppBar(title: Text(leitura.titulo)),
      body: ListView.builder(
        itemCount: blocos.length,
        itemBuilder: (context, i) {
          final bloco = blocos[i];
          return CheckboxListTile(
            value: leitura.partesConcluidas[i],
            title: Text('Parte ${i + 1}'),
            subtitle: Text(
                'págs ${bloco.inicio}–${bloco.fim} (${bloco.fim - bloco.inicio + 1} páginas)'),
            onChanged: (v) {
              final novas = [...leitura.partesConcluidas];
              novas[i] = v ?? false;
              ref
                  .read(leiturasProvider.notifier)
                  .salvar(leitura.copyWith(partesConcluidas: novas));
            },
          );
        },
      ),
    );
  }
}
