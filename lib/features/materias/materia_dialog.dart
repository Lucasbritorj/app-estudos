import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/widgets/notas_editor.dart';
import '../../data/catalogo/catalogo_materias.dart';
import '../../data/models/ambiente.dart';
import '../../data/models/materia.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';

/// Cria ou edita matéria. Cor é atribuída pelo próximo slot livre da paleta
/// fixa e nunca muda depois (cor segue a entidade).
Future<void> mostrarDialogoMateria(
  BuildContext context,
  WidgetRef ref, {
  Materia? existente,
}) async {
  final nome = TextEditingController(text: existente?.nome ?? '');
  final peso = TextEditingController(text: '${existente?.peso ?? 1}');
  final questoes = TextEditingController(
    text: existente?.questoes?.toString() ?? '',
  );
  final minimo = TextEditingController(
    text: existente?.minimo?.toString() ?? '',
  );
  final notas = TextEditingController(text: existente?.notas ?? '');
  // Alvo em HORAS na UI (como o usuário pensa); gravado em minutos.
  final horasAlvo = TextEditingController(
    text: existente?.minutosAlvo == null
        ? ''
        : (existente!.minutosAlvo! / 60).toStringAsFixed(0),
  );
  final formKey = GlobalKey<FormState>();
  var intimidade = existente?.intimidade ?? 3;
  final ambientes = ref.read(ambientesProvider);
  // Matéria nova nasce no ambiente ativo (ou "Geral" na visão consolidada).
  var ambienteId =
      existente?.ambienteId ??
      ref.read(ambienteAtivoProvider)?.id ??
      Ambiente.geralId;
  if (!ambientes.any((a) => a.id == ambienteId) && ambientes.isNotEmpty) {
    ambienteId = ambientes.first.id;
  }
  const rotulosIntimidade = [
    'Iniciante',
    'Já vi o básico',
    'Intermediário',
    'Avançado',
    'Especialista',
  ];

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setStateDialog) => AlertDialog(
        title: Text(existente == null ? 'Nova matéria' : 'Editar matéria'),
        content: Form(
          key: formKey,
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Catálogo é SÓ sugestão: o campo aceita texto livre (o usuário
                // nomeia a matéria como quiser). O controller externo `nome`
                // segue como fonte da verdade no salvar; o campo do Autocomplete
                // espelha nele a cada digitação/seleção.
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: existente?.nome ?? ''),
                  optionsBuilder: (value) {
                    final q = value.text.trim().toLowerCase();
                    final nomes = catalogoMaterias.map((m) => m.nome);
                    if (q.isEmpty) return nomes;
                    return nomes.where((n) => n.toLowerCase().contains(q));
                  },
                  onSelected: (v) => nome.text = v,
                  fieldViewBuilder:
                      (context, fieldController, focusNode, onSubmitted) {
                        return TextFormField(
                          controller: fieldController,
                          focusNode: focusNode,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Nome *',
                            helperText:
                                'Escolha do catálogo ou digite livremente',
                          ),
                          onChanged: (v) => nome.text = v,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Obrigatório'
                              : null,
                        );
                      },
                ),
                if (ambientes.length > 1) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: ambienteId,
                    decoration: const InputDecoration(labelText: 'Ambiente'),
                    items: [
                      for (final a in ambientes)
                        DropdownMenuItem(value: a.id, child: Text(a.nome)),
                    ],
                    onChanged: (v) =>
                        setStateDialog(() => ambienteId = v ?? ambienteId),
                  ),
                ],
                TextFormField(
                  controller: peso,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Peso no edital',
                  ),
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    if (n == null || n < 1) return 'Inteiro >= 1';
                    return null;
                  },
                ),
                TextFormField(
                  controller: questoes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Questões na prova (opcional)',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = int.tryParse(v);
                    if (n == null || n < 1) return 'Inteiro >= 1';
                    return null;
                  },
                ),
                TextFormField(
                  controller: minimo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Mínimo de acertos (opcional)',
                  ),
                  // Regra do edital: mínimo exigido nunca excede o total de
                  // questões da matéria na prova.
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = int.tryParse(v);
                    if (n == null || n < 0) return 'Número inválido';
                    final q = int.tryParse(questoes.text);
                    if (q != null && n > q) {
                      return 'Maior que as questões na prova ($q)';
                    }
                    return null;
                  },
                ),
                TextFormField(
                  controller: horasAlvo,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Horas previstas p/ concluir (opcional)',
                    helperText: 'Alimenta a fila de estudo do Planejamento',
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = int.tryParse(v);
                    if (n == null || n < 1) return 'Inteiro >= 1';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Intimidade: ${rotulosIntimidade[intimidade - 1]}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Slider(
                  value: intimidade.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: rotulosIntimidade[intimidade - 1],
                  onChanged: (v) =>
                      setStateDialog(() => intimidade = v.round()),
                ),
                const SizedBox(height: 4),
                NotasEditor(controller: notas),
              ],
            ),
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
              final repositorio = ref.read(materiasProvider.notifier);
              final materia = existente == null
                  ? Materia(
                      id: const Uuid().v4(),
                      nome: nome.text.trim(),
                      ambienteId: ambienteId,
                      corSlot: repositorio.proximoCorSlot(),
                      peso: int.parse(peso.text),
                      questoes: int.tryParse(questoes.text),
                      minimo: int.tryParse(minimo.text),
                      intimidade: intimidade,
                      minutosAlvo: horasAlvo.text.isEmpty
                          ? null
                          : int.parse(horasAlvo.text) * 60,
                      criadaEm: DateTime.now(),
                      notas: notas.text.trim(),
                    )
                  : existente.copyWith(
                      nome: nome.text.trim(),
                      ambienteId: ambienteId,
                      peso: int.parse(peso.text),
                      questoes: int.tryParse(questoes.text),
                      minimo: int.tryParse(minimo.text),
                      intimidade: intimidade,
                      minutosAlvo: horasAlvo.text.isEmpty
                          ? null
                          : int.parse(horasAlvo.text) * 60,
                      limparMinutosAlvo: horasAlvo.text.isEmpty,
                      notas: notas.text.trim(),
                    );
              repositorio.salvar(materia);
              Navigator.pop(dialogContext);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    ),
  );

  // Diálogo fechado: nenhum widget referencia mais estes controllers. Sem
  // isto cada abertura vazava 6 ChangeNotifier — e este diálogo tem 5 call
  // sites. `nome` entra na lista mesmo sendo só espelho do Autocomplete: o
  // controller é NOSSO (o Autocomplete usa o `fieldController` dele próprio e
  // nunca dispõe um que não criou).
  nome.dispose();
  peso.dispose();
  questoes.dispose();
  minimo.dispose();
  notas.dispose();
  horasAlvo.dispose();
}
