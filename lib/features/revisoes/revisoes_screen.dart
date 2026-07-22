import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/revisao_use_case.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar_cor.dart';
import '../../core/widgets/estado_vazio.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/revisao.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';

class RevisoesScreen extends ConsumerStatefulWidget {
  const RevisoesScreen({super.key});

  @override
  ConsumerState<RevisoesScreen> createState() => _RevisoesScreenState();
}

class _RevisoesScreenState extends ConsumerState<RevisoesScreen> {
  var _mostrarFeitas = false;

  Future<void> _novaRevisaoManual() async {
    final materias = ref
        .read(materiasDoAmbienteProvider)
        .where((m) => !m.arquivada)
        .toList();
    if (materias.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre uma matéria primeiro.')),
      );
      return;
    }
    final titulo = TextEditingController();
    String materiaId = materias.first.id;
    DateTime data = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: const Text('Nova revisão'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: materiaId,
                decoration: const InputDecoration(labelText: 'Matéria'),
                items: [
                  for (final m in materias)
                    DropdownMenuItem(value: m.id, child: Text(m.nome)),
                ],
                onChanged: (v) => materiaId = v ?? materiaId,
              ),
              TextField(
                controller: titulo,
                decoration: const InputDecoration(labelText: 'O que revisar'),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final escolhida = await showDatePicker(
                    context: dialogContext,
                    initialDate: data,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2030),
                  );
                  if (escolhida != null) setStateDialog(() => data = escolhida);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Data'),
                  child: Text(formatarData(data)),
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
              onPressed: () async {
                if (titulo.text.trim().isEmpty) return;
                await ref
                    .read(revisaoUseCaseProvider)
                    .criarManual(
                      materiaId: materiaId,
                      titulo: titulo.text.trim(),
                      data: data,
                    );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  /// Conclui via caso de uso (FSRS-lite) e formata o feedback. Antes,
  /// oferece registrar o desempenho da revisão (vira sessão prática — o
  /// intervalo seguinte responde à taxa real, não só ao histórico).
  Future<void> _concluir(Revisao revisao) async {
    final desempenho = await _perguntarDesempenho(revisao);
    if (desempenho == null || !mounted) return; // cancelou: nada acontece
    final resultado = await ref
        .read(revisaoUseCaseProvider)
        .concluir(
          revisao,
          questoes: desempenho.questoes,
          acertos: desempenho.acertos,
        );
    final proxima = resultado.proxima;
    if (proxima == null || !mounted) return;
    final motivo = resultado.reforco
        ? 'Acerto ${(resultado.taxaAcerto! * 100).toStringAsFixed(0)}% '
              'abaixo de 75% — reforço em ${proxima.intervaloDias}d'
        : 'Próxima em ${proxima.intervaloDias}d';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Feita. $motivo (${formatarData(proxima.dataAgendada)}).',
        ),
      ),
    );
  }

  Future<void> _adiar(Revisao revisao, int dias) =>
      ref.read(revisaoUseCaseProvider).adiar(revisao, dias);

  /// Pergunta o desempenho da revisão. Retornos: null = cancelou (não
  /// conclui); (questoes: null, ...) = concluir sem registrar; valores =
  /// concluir e registrar prática.
  Future<({int? questoes, int? acertos})?> _perguntarDesempenho(
    Revisao revisao,
  ) {
    final questoesCtrl = TextEditingController();
    final acertosCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    return showDialog<({int? questoes, int? acertos})?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Como foi a revisão?'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Se fez questões, informe o resultado — o próximo intervalo '
                'se ajusta à taxa de acerto e o registro entra como prática.',
                style: TextStyle(color: VizColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: questoesCtrl,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Questões'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final n = int.tryParse(v.trim());
                        if (n == null || n <= 0) return 'Inteiro > 0';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: acertosCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Acertos'),
                      validator: (v) {
                        final questoes = int.tryParse(questoesCtrl.text.trim());
                        if (questoes == null) return null;
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 0) return 'Obrigatório';
                        if (n > questoes) return '≤ questões';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, (questoes: null, acertos: null)),
            child: const Text('Só concluir'),
          ),
          FilledButton(
            onPressed: () {
              final questoes = int.tryParse(questoesCtrl.text.trim());
              if (questoes == null) {
                // Sem questões preenchidas, o botão equivale a só concluir.
                Navigator.pop(dialogContext, (questoes: null, acertos: null));
                return;
              }
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogContext, (
                questoes: questoes,
                acertos: int.tryParse(acertosCtrl.text.trim()),
              ));
            },
            child: const Text('Concluir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoje = DateTime.now();
    final revisoes = ref.watch(revisoesDoAmbienteProvider);
    final materias = ref.watch(materiasProvider);
    final materiasPorId = {for (final m in materias) m.id: m};

    final visiveis = revisoes.where((r) => r.feita == _mostrarFeitas).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Revisões')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nova revisão',
        onPressed: _novaRevisaoManual,
        child: const Icon(Icons.add),
      ),
      body: ConteudoCentral(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Pendentes')),
                  ButtonSegment(value: true, label: Text('Feitas')),
                ],
                selected: {_mostrarFeitas},
                onSelectionChanged: (s) =>
                    setState(() => _mostrarFeitas = s.first),
              ),
            ),
            Expanded(
              child: visiveis.isEmpty
                  ? EstadoVazio(
                      icone: _mostrarFeitas
                          ? Icons.task_alt
                          : Icons.inbox_outlined,
                      titulo: _mostrarFeitas
                          ? 'Nenhuma revisão concluída ainda'
                          : 'Nada pendente',
                      descricao: _mostrarFeitas
                          ? 'Revisões concluídas aparecem aqui.'
                          : 'Salve sessões de estudo para gerar revisões.',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: visiveis.length,
                      itemBuilder: (context, i) {
                        final revisao = visiveis[i];
                        final status = revisao.statusEm(hoje);
                        final materia = materiasPorId[revisao.materiaId];
                        final (corStatus, icone, rotulo) = switch (status) {
                          RevisaoStatus.atrasada => (
                            StatusColors.critico,
                            Icons.error_outline,
                            'Atrasada',
                          ),
                          RevisaoStatus.aFazer => (
                            StatusColors.atencao,
                            Icons.schedule,
                            'A fazer',
                          ),
                          RevisaoStatus.feita => (
                            StatusColors.bom,
                            Icons.check_circle_outline,
                            'Feita',
                          ),
                        };
                        return ListTile(
                          leading: AvatarCor(slot: materia?.corSlot ?? 0),
                          title: Text(
                            revisao.titulo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Row(
                            children: [
                              Icon(icone, size: 14, color: corStatus),
                              const SizedBox(width: 4),
                              Text(
                                '$rotulo · ${formatarData(revisao.dataAgendada)}',
                                style: TextStyle(color: corStatus),
                              ),
                            ],
                          ),
                          trailing: _mostrarFeitas
                              ? IconButton(
                                  tooltip: 'Excluir',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => ref
                                      .read(revisoesProvider.notifier)
                                      .remover(revisao.id),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PopupMenuButton<int>(
                                      tooltip: 'Adiar',
                                      icon: const Icon(
                                        Icons.schedule_send,
                                        color: VizColors.muted,
                                      ),
                                      onSelected: (dias) =>
                                          _adiar(revisao, dias),
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 1,
                                          child: Text('Adiar 1 dia'),
                                        ),
                                        PopupMenuItem(
                                          value: 3,
                                          child: Text('Adiar 3 dias'),
                                        ),
                                        PopupMenuItem(
                                          value: 7,
                                          child: Text('Adiar 7 dias'),
                                        ),
                                      ],
                                    ),
                                    IconButton(
                                      tooltip: 'Concluir',
                                      icon: const Icon(
                                        Icons.check_circle,
                                        color: StatusColors.bom,
                                      ),
                                      onPressed: () => _concluir(revisao),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
