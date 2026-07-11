import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/ambiente.dart';
import '../../data/models/materia.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/edital_parser_service.dart';

/// Import de edital por TEXTO COLADO (nunca JSON): copiar do PDF e colar.
/// Numeração (1, 1.2, 1.2.3) e marcadores (-, •) viram hierarquia de
/// tópicos. Com [materiaFixa] o destino é travado (fluxo da tela de
/// tópicos); sem ela o usuário escolhe a matéria ou cria uma na hora.
Future<void> mostrarImportarEdital(BuildContext context, WidgetRef ref,
    {Materia? materiaFixa}) async {
  final texto = TextEditingController();
  final novaMateria = TextEditingController();
  String? materiaId = materiaFixa?.id;
  var criarNova = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setStateDialog) {
        final materias = ref
            .read(materiasDoAmbienteProvider)
            .where((m) => !m.arquivada)
            .toList();
        if (materias.isEmpty) criarNova = true;
        return AlertDialog(
          title: const Text('Importar edital (colar texto)'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Copie o conteúdo programático do PDF do edital e cole '
                    'abaixo — texto normal, sem formato especial. '
                    'Numeração (1, 1.2, 1.2.3) e marcadores (-, •) viram '
                    'a hierarquia de tópicos.',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                if (materiaFixa == null) ...[
                  if (!criarNova)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: materiaId,
                            decoration: const InputDecoration(
                                labelText: 'Matéria de destino *'),
                            items: [
                              for (final m in materias)
                                DropdownMenuItem(
                                    value: m.id, child: Text(m.nome)),
                            ],
                            onChanged: (v) =>
                                setStateDialog(() => materiaId = v),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              setStateDialog(() => criarNova = true),
                          child: const Text('Nova'),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: novaMateria,
                            decoration: const InputDecoration(
                                labelText: 'Nome da nova matéria *',
                                hintText: 'Ex.: Direito Constitucional'),
                          ),
                        ),
                        if (materias.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                setStateDialog(() => criarNova = false),
                            child: const Text('Existente'),
                          ),
                      ],
                    ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: texto,
                  autofocus: materiaFixa != null,
                  maxLines: 10,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText:
                          '1 Auditoria Governamental\n1.1 Conceitos\n1.2 Normas\n2 AFO'),
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
              onPressed: () async {
                final itens = EditalParserService.parse(texto.text);
                if (itens.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Nenhum tópico detectado no texto colado.')));
                  return;
                }
                Materia? destino = materiaFixa;
                if (destino == null && criarNova) {
                  final nome = novaMateria.text.trim();
                  if (nome.isEmpty) return;
                  final repositorio = ref.read(materiasProvider.notifier);
                  destino = Materia(
                    id: const Uuid().v4(),
                    nome: nome,
                    ambienteId: ref.read(ambienteAtivoProvider)?.id ??
                        Ambiente.geralId,
                    corSlot: repositorio.proximoCorSlot(),
                    criadaEm: DateTime.now(),
                  );
                  await repositorio.salvar(destino);
                } else if (destino == null) {
                  if (materiaId == null) return;
                  destino = materias
                      .where((m) => m.id == materiaId)
                      .firstOrNull;
                  if (destino == null) return;
                }
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }

                final repositorio = ref.read(topicosProvider.notifier);
                // Pilha nível -> id: liga cada item ao pai de nível acima.
                final pilha = <int, String>{};
                for (final item in itens) {
                  final id = const Uuid().v4();
                  final parentId =
                      item.nivel == 0 ? null : pilha[item.nivel - 1];
                  await repositorio.salvar(Topico(
                    id: id,
                    materiaId: destino.id,
                    parentId: parentId,
                    nome: item.nome,
                  ));
                  pilha[item.nivel] = id;
                  pilha.removeWhere((nivel, _) => nivel > item.nivel);
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '${itens.length} tópicos importados em '
                          '${destino.nome}.')));
                }
              },
              child: const Text('Importar'),
            ),
          ],
        );
      },
    ),
  );
}
