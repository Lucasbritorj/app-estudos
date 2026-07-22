import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptica.dart';
import '../../core/widgets/estado_vazio.dart';
import '../../data/models/leitura.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/leitura_service.dart';

/// Registra a leitura do dia: páginas + tempo. Data padrão = hoje, mas
/// editável (esqueceu de registrar na hora). Min/pág e projeção são
/// calculados — nunca digitados.
Future<void> registrarSessaoLeitura(
  BuildContext context,
  WidgetRef ref,
  Leitura leitura,
) async {
  final paginas = TextEditingController();
  final minutos = TextEditingController();
  var data = DateTime.now();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setStateDialog) {
        final p = int.tryParse(paginas.text);
        final m = int.tryParse(minutos.text);
        final previa = (p != null && p > 0 && m != null && m > 0)
            ? '${(m / p).toStringAsFixed(1)} min/pág nesta sessão'
            : '';
        return AlertDialog(
          title: Text('Registrar leitura — ${leitura.titulo}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final escolhida = await showDatePicker(
                          context: dialogContext,
                          initialDate: data,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (escolhida != null) {
                          setStateDialog(() => data = escolhida);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Data'),
                        child: Text(formatarData(data)),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: paginas,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Páginas lidas *',
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: minutos,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minutos (opcional)',
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                  ),
                ],
              ),
              if (previa.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      previa,
                      style: const TextStyle(
                        color: LuminaColors.safiraClara,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final pag = int.tryParse(paginas.text);
                if (pag == null || pag <= 0) return;
                final sessao = SessaoLeitura(
                  data: data,
                  paginas: pag,
                  minutos: int.tryParse(minutos.text),
                );
                ref
                    .read(leiturasProvider.notifier)
                    .salvar(
                      leitura.copyWith(sessoes: [...leitura.sessoes, sessao]),
                    );
                Haptica.leve();
                Navigator.pop(dialogContext);
              },
              child: const Text('Salvar'),
            ),
          ],
        );
      },
    ),
  );
}

class LeiturasScreen extends ConsumerWidget {
  const LeiturasScreen({super.key});

  Future<void> _novaLeitura(BuildContext context, WidgetRef ref) async {
    final materias = ref
        .read(materiasProvider)
        .where((m) => !m.arquivada)
        .toList();
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
                    labelText: 'Título *',
                    hintText: 'Ex.: Manual de AFO',
                  ),
                ),
                if (materias.isNotEmpty)
                  DropdownButtonFormField<String?>(
                    initialValue: materiaId,
                    decoration: const InputDecoration(
                      labelText: 'Matéria (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— nenhuma —'),
                      ),
                      for (final m in materias)
                        DropdownMenuItem<String?>(
                          value: m.id,
                          child: Text(m.nome),
                        ),
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
                          labelText: 'Pág. inicial *',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: pagFim,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Pág. final *',
                        ),
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
                ref
                    .read(leiturasProvider.notifier)
                    .salvar(
                      Leitura(
                        id: const Uuid().v4(),
                        titulo: titulo.text.trim(),
                        materiaId: materiaId,
                        paginaInicio: inicio,
                        paginaFim: fim,
                        partes: n,
                        partesConcluidas: List.filled(n, false),
                      ),
                    );
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
          ? EstadoVazio(
              icone: Icons.menu_book,
              titulo: 'Nenhuma leitura ainda',
              descricao:
                  'Divida um PDF em blocos e acompanhe páginas, tempo '
                  'e ritmo de leitura.',
              cta: FilledButton.icon(
                onPressed: () => _novaLeitura(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Dividir PDF'),
              ),
            )
          : ConteudoCentral(
              child: ListView.builder(
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
                          '$lidas/${leitura.totalPaginas} lidas (${(progresso * 100).toStringAsFixed(0)}%)',
                        ),
                        if (leitura.sessoes.isNotEmpty)
                          Text(
                            '${leitura.paginasRegistradas} pág registradas'
                            '${leitura.minutosPorPagina == null ? '' : ' · ${leitura.minutosPorPagina!.toStringAsFixed(1)} min/pág'}'
                            '${leitura.minutosParaTerminar == null || leitura.minutosParaTerminar == 0 ? '' : ' · ~${formatarMinutos(leitura.minutosParaTerminar!)} p/ terminar'}',
                            style: const TextStyle(
                              color: VizColors.muted,
                              fontSize: 12,
                            ),
                          ),
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Registrar leitura de hoje',
                          icon: const Icon(Icons.add_task, size: 20),
                          onPressed: () =>
                              registrarSessaoLeitura(context, ref, leitura),
                        ),
                        IconButton(
                          tooltip: 'Excluir',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => ref
                              .read(leiturasProvider.notifier)
                              .remover(leitura.id),
                        ),
                      ],
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _LeituraDetalhe(id: leitura.id),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _LeituraDetalhe extends ConsumerWidget {
  final String id;

  const _LeituraDetalhe({required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leitura = ref
        .watch(leiturasProvider)
        .where((l) => l.id == id)
        .firstOrNull;
    if (leitura == null) {
      return const Scaffold(body: Center(child: Text('Leitura removida.')));
    }
    final blocos = LeituraService.dividir(
      leitura.paginaInicio,
      leitura.paginaFim,
      leitura.partes,
    );

    final sessoes = [...leitura.sessoes]
      ..sort((a, b) => b.data.compareTo(a.data));

    return Scaffold(
      appBar: AppBar(title: Text(leitura.titulo)),
      body: ConteudoCentral(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            for (var i = 0; i < blocos.length; i++)
              CheckboxListTile(
                value: leitura.partesConcluidas[i],
                title: Text('Parte ${i + 1}'),
                subtitle: Text(
                  'págs ${blocos[i].inicio}–${blocos[i].fim} (${blocos[i].fim - blocos[i].inicio + 1} páginas)',
                ),
                onChanged: (v) {
                  final novas = [...leitura.partesConcluidas];
                  novas[i] = v ?? false;
                  ref
                      .read(leiturasProvider.notifier)
                      .salvar(leitura.copyWith(partesConcluidas: novas));
                },
              ),
            const Divider(color: VizColors.gridline),
            ListTile(
              title: const Text('Sessões de leitura'),
              subtitle: Text(
                leitura.sessoes.isEmpty
                    ? 'Registre páginas e tempo por dia — o ritmo é calculado'
                    : '${leitura.paginasRegistradas} pág em '
                          '${formatarMinutos(leitura.minutosRegistrados)}'
                          '${leitura.minutosPorPagina == null ? '' : ' · ${leitura.minutosPorPagina!.toStringAsFixed(1)} min/pág'}'
                          '${leitura.minutosParaTerminar == null || leitura.minutosParaTerminar == 0 ? '' : ' · ~${formatarMinutos(leitura.minutosParaTerminar!)} p/ terminar'}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: FilledButton.tonalIcon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Registrar'),
                onPressed: () => registrarSessaoLeitura(context, ref, leitura),
              ),
            ),
            for (final sessao in sessoes)
              ListTile(
                dense: true,
                leading: const Icon(Icons.menu_book_outlined, size: 18),
                title: Text(
                  '${formatarData(sessao.data)} · ${sessao.paginas} pág'
                  '${sessao.minutos == null ? '' : ' · ${formatarMinutos(sessao.minutos!)}'}'
                  '${sessao.minutosPorPagina == null ? '' : ' · ${sessao.minutosPorPagina!.toStringAsFixed(1)} min/pág'}',
                ),
                trailing: IconButton(
                  tooltip: 'Excluir sessão',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () {
                    final restantes = [...leitura.sessoes]..remove(sessao);
                    ref
                        .read(leiturasProvider.notifier)
                        .salvar(leitura.copyWith(sessoes: restantes));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
