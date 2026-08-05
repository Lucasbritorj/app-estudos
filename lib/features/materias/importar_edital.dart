import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/ambiente.dart';
import '../../data/models/materia.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/edital_parser_service.dart';

String _normalizar(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Grava itens como tópicos SEM duplicar: item com mesmo nome (normalizado)
/// sob o mesmo pai é reaproveitado — re-importar o edital só adiciona o que
/// faltou. Retorna quantos são novos.
Future<int> _gravarItens(
  WidgetRef ref,
  Materia destino,
  List<ItemEdital> itens,
) async {
  final repositorio = ref.read(topicosProvider.notifier);
  final existentes = ref
      .read(topicosProvider)
      .where((t) => t.materiaId == destino.id)
      .toList();
  final porChave = <String, String>{
    for (final t in existentes)
      '${t.parentId ?? ''}|${_normalizar(t.nome)}': t.id,
  };
  // Pilha nível -> id: liga cada item ao pai de nível acima.
  final pilha = <int, String>{};
  var novos = 0;
  for (final item in itens) {
    final parentId = item.nivel == 0 ? null : pilha[item.nivel - 1];
    final chave = '${parentId ?? ''}|${_normalizar(item.nome)}';
    var id = porChave[chave];
    if (id == null) {
      id = const Uuid().v4();
      await repositorio.salvar(
        Topico(
          id: id,
          materiaId: destino.id,
          parentId: parentId,
          nome: item.nome,
        ),
      );
      porChave[chave] = id;
      novos++;
    }
    pilha[item.nivel] = id;
    pilha.removeWhere((nivel, _) => nivel > item.nivel);
  }
  return novos;
}

/// Acha matéria existente pelo nome normalizado ou cria uma nova no
/// ambiente ativo.
Future<Materia> _materiaPorNome(WidgetRef ref, String nome) async {
  final repositorio = ref.read(materiasProvider.notifier);
  final existente = ref
      .read(materiasProvider)
      .where((m) => _normalizar(m.nome) == _normalizar(nome))
      .firstOrNull;
  if (existente != null) return existente;
  final nova = Materia(
    id: const Uuid().v4(),
    nome: nome,
    ambienteId: ref.read(ambienteAtivoProvider)?.id ?? Ambiente.geralId,
    corSlot: repositorio.proximoCorSlot(),
    criadaEm: DateTime.now(),
  );
  await repositorio.salvar(nova);
  return nova;
}

/// Import de edital por TEXTO COLADO (nunca JSON): copiar do PDF e colar.
/// Com "detectar matérias" ligado, cabeçalhos em caixa alta viram matérias
/// e os itens numerados abaixo viram os tópicos de cada uma — o Mapa de
/// Estudos e o ciclo do Planejamento passam a enxergá-las na hora.
Future<void> mostrarImportarEdital(
  BuildContext context,
  WidgetRef ref, {
  Materia? materiaFixa,
}) async {
  // Os dois controllers vivem sem `dispose()` de propósito. `Route.didComplete`
  // (navigator.dart:480) completa o Future do `showDialog` no POP, não quando a
  // rota sai da árvore: fechando por ESC ou por "Cancelar", o `await` abaixo
  // retoma com o diálogo AINDA MONTADO, animando a saída. O `StatefulBuilder`
  // rebuilda nessa janela — lê `materiasDoAmbienteProvider` e reconstrói os
  // `TextField` de `:172` e `:191` — e um controller já liberado explode com
  // "used after being disposed".
  //
  // `.whenComplete` não resolve (roda no mesmo instante do `await`) e
  // `addPostFrameCallback` também não (a saída dura vários frames). O caminho
  // "Importar" é pior ainda: dá `Navigator.pop` e SEGUE gravando tópicos, o que
  // dispara rebuild do diálogo moribundo por mudança de provider.
  //
  // Custo aceito: dois controllers por abertura do diálogo de import, aberto
  // poucas vezes na vida do app. Mesma isenção documentada de
  // `configuracoes_screen.dart`. Fechar de verdade exige `StatefulWidget` com
  // `dispose()` no State — débito, não esta onda.
  // dispose-exempt: rota ainda montada no ESC; liberar quebra o TextField.
  final texto = TextEditingController();
  // dispose-exempt: rota ainda montada no ESC; liberar quebra o TextField.
  final novaMateria = TextEditingController();
  String? materiaId = materiaFixa?.id;
  var criarNova = false;
  var detectarMaterias = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setStateDialog) {
        final materias = ref
            .read(materiasDoAmbienteProvider)
            .where((m) => !m.arquivada)
            .toList();
        if (materias.isEmpty && !detectarMaterias) criarNova = true;
        return AlertDialog(
          title: const Text('Importar edital (colar texto)'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Copie o conteúdo programático do PDF e cole abaixo — '
                  'texto normal. Numeração (1, 1.2, 1.2.3), itens '
                  'separados por ";" e marcadores viram a hierarquia. '
                  'Re-importar NÃO duplica: só entra o que faltou.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                if (materiaFixa == null) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Detectar matérias automaticamente',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text(
                      'Edital completo: cabeçalhos EM CAIXA ALTA viram '
                      'matérias',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: detectarMaterias,
                    onChanged: (v) =>
                        setStateDialog(() => detectarMaterias = v),
                  ),
                  if (!detectarMaterias) ...[
                    if (!criarNova)
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: materiaId,
                              decoration: const InputDecoration(
                                labelText: 'Matéria de destino *',
                              ),
                              items: [
                                for (final m in materias)
                                  DropdownMenuItem(
                                    value: m.id,
                                    child: Text(m.nome),
                                  ),
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
                                hintText: 'Ex.: Direito Constitucional',
                              ),
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
                  ],
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: texto,
                  autofocus: materiaFixa != null,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText:
                        'LÍNGUA PORTUGUESA: 1 Compreensão de textos; '
                        '2 Tipologia textual; 2.1 Gêneros...',
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
              onPressed: () async {
                // ---- Edital completo: várias matérias de uma vez.
                if (materiaFixa == null && detectarMaterias) {
                  final secoes = EditalParserService.parseSecoes(texto.text);
                  final comMateria = secoes
                      .where((s) => s.materia != null && s.itens.isNotEmpty)
                      .toList();
                  if (comMateria.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Nenhum cabeçalho de matéria detectado — '
                          'desligue a detecção e escolha a matéria.',
                        ),
                      ),
                    );
                    return;
                  }
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                  var totalNovos = 0;
                  var totalItens = 0;
                  for (final secao in comMateria) {
                    final destino = await _materiaPorNome(ref, secao.materia!);
                    totalNovos += await _gravarItens(ref, destino, secao.itens);
                    totalItens += secao.itens.length;
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${comMateria.length} matérias · $totalNovos '
                          'tópicos novos (${totalItens - totalNovos} já '
                          'existiam). Veja o Mapa de Estudos.',
                        ),
                      ),
                    );
                  }
                  return;
                }

                // ---- Uma matéria só.
                final itens = EditalParserService.parse(texto.text);
                if (itens.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nenhum tópico detectado no texto colado.'),
                    ),
                  );
                  return;
                }
                Materia? destino = materiaFixa;
                if (destino == null && criarNova) {
                  final nome = novaMateria.text.trim();
                  if (nome.isEmpty) return;
                  destino = await _materiaPorNome(ref, nome);
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
                final novos = await _gravarItens(ref, destino, itens);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '$novos tópicos novos em ${destino.nome} '
                        '(${itens.length - novos} já existiam).',
                      ),
                    ),
                  );
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
