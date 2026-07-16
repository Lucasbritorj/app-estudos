import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/ambiente.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/insights_service.dart';

/// CRUD de Ambientes. Regra de proteção: ambiente com matérias não pode ser
/// excluído (mova/apague as matérias antes) — evita órfãos silenciosos.
class AmbientesScreen extends ConsumerWidget {
  const AmbientesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ambientes = ref.watch(ambientesProvider);
    final materias = ref.watch(materiasProvider);
    final registros = ref.watch(registrosProvider);
    final minutosPorAmbiente =
        InsightsService.minutosPorAmbiente(registros, materias);

    return Scaffold(
      appBar: AppBar(title: const Text('Ambientes')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostrarDialogo(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ambientes.isEmpty
          ? const Center(
              child: Text('Sem ambientes. Toque em + para criar o primeiro.'))
          : ListView.builder(
              itemCount: ambientes.length,
              itemBuilder: (context, i) {
                final ambiente = ambientes[i];
                final qtdMaterias = materias
                    .where((m) => m.ambienteId == ambiente.id)
                    .length;
                final minutos = minutosPorAmbiente[ambiente.id] ?? 0;
                return ListTile(
                  leading: CircleAvatar(
                    radius: 10,
                    backgroundColor: corDaSerie(ambiente.corSlot),
                  ),
                  title: Text(ambiente.nome),
                  subtitle: Text(
                      '$qtdMaterias ${qtdMaterias == 1 ? 'matéria' : 'matérias'}'
                      ' · ${formatarMinutos(minutos)} acumulados'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (acao) async {
                      if (acao == 'editar') {
                        await _mostrarDialogo(context, ref,
                            existente: ambiente);
                      } else if (acao == 'excluir') {
                        await _excluir(context, ref, ambiente, qtdMaterias);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'editar', child: Text('Editar')),
                      PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _excluir(BuildContext context, WidgetRef ref,
      Ambiente ambiente, int qtdMaterias) async {
    if (qtdMaterias > 0) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${ambiente.nome} tem matérias'),
          content: Text(
              'Este ambiente tem $qtdMaterias '
              '${qtdMaterias == 1 ? 'matéria' : 'matérias'}. '
              'Mova-as para outro ambiente (editar matéria) ou exclua-as '
              'antes de excluir o ambiente.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Entendi'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Excluir ${ambiente.nome}?'),
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
    if (confirmado != true) return;
    await ref.read(ambientesProvider.notifier).remover(ambiente.id);
    // Escopo apontando para o excluído volta à visão consolidada.
    final config = ref.read(configuracoesProvider);
    if (config.ambienteAtivoId == ambiente.id) {
      await ref
          .read(configuracoesProvider.notifier)
          .salvar(config.copyWith(limparAmbienteAtivo: true));
    }
  }

  Future<void> _mostrarDialogo(BuildContext context, WidgetRef ref,
      {Ambiente? existente}) async {
    final nome = TextEditingController(text: existente?.nome ?? '');
    final formKey = GlobalKey<FormState>();
    DateTime? dataProva = existente?.dataProva;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title:
              Text(existente == null ? 'Novo ambiente' : 'Editar ambiente'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nome,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Nome *',
                      hintText: 'Ex.: Concurso SEFAZ-RN 2026'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final escolhida = await showDatePicker(
                      context: dialogContext,
                      initialDate: dataProva ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (escolhida != null) {
                      setStateDialog(() => dataProva = escolhida);
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Data da prova (opcional)',
                      helperText: 'Habilita a projeção de prontidão',
                      suffixIcon: dataProva == null
                          ? const Icon(Icons.event, size: 18)
                          : IconButton(
                              tooltip: 'Limpar data',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  setStateDialog(() => dataProva = null),
                            ),
                    ),
                    child: Text(dataProva == null
                        ? 'Sem data marcada'
                        : formatarData(dataProva!)),
                  ),
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
                if (!formKey.currentState!.validate()) return;
                final repositorio = ref.read(ambientesProvider.notifier);
                final ambiente = existente == null
                    ? Ambiente(
                        id: const Uuid().v4(),
                        nome: nome.text.trim(),
                        corSlot: repositorio.proximoCorSlot(),
                        criadoEm: DateTime.now(),
                        dataProva: dataProva,
                      )
                    : existente.copyWith(
                        nome: nome.text.trim(),
                        dataProva: dataProva,
                        limparDataProva: dataProva == null,
                      );
                repositorio.salvar(ambiente);
                Navigator.pop(dialogContext);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
