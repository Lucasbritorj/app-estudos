import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/notificacoes/notificacoes_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/revisao.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/revisao_service.dart';

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
          const SnackBar(content: Text('Cadastre uma matéria primeiro.')));
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
                decoration:
                    const InputDecoration(labelText: 'O que revisar'),
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
                final config = ref.read(configuracoesProvider);
                final revisao = Revisao(
                  id: const Uuid().v4(),
                  materiaId: materiaId,
                  titulo: titulo.text.trim(),
                  dataAgendada: data,
                  intervaloDias: 0,
                );
                await ref.read(revisoesProvider.notifier).salvar(revisao);
                await NotificacoesService.agendarRevisao(
                  id: revisao.id,
                  titulo: revisao.titulo,
                  dia: revisao.dataAgendada,
                  hora: config.horaNotificacao,
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

  /// Conclui e emenda a próxima revisão — FSRS-lite adaptativo pelo
  /// desempenho do tópico: <75% de acerto derruba a estabilidade e agenda
  /// reforço curto; 75-84% cresce devagar; >=85% (ou sem questões) espaça
  /// pleno (~7->15->32->70), com bônus quando revisada perto do
  /// esquecimento. Intervalo além do teto encerra a cadeia.
  Future<void> _concluir(Revisao revisao) async {
    final agora = DateTime.now();
    await ref
        .read(revisoesProvider.notifier)
        .salvar(revisao.copyWith(feita: true, dataConclusao: agora));
    await NotificacoesService.cancelar(revisao.id);

    final config = ref.read(configuracoesProvider);
    final taxa = RevisaoService.taxaAcertoDe(
      ref.read(registrosProvider),
      materiaId: revisao.materiaId,
      topicoId: revisao.topicoId,
    );
    final agendada = DateTime(revisao.dataAgendada.year,
        revisao.dataAgendada.month, revisao.dataAgendada.day);
    final passo = RevisaoService.proximoPassoFsrs(
      estabilidade: revisao.estabilidade,
      dificuldade: revisao.dificuldade,
      intervaloAtual: revisao.intervaloDias,
      diasDeAtraso: agora.difference(agendada).inDays,
      taxaAcerto: taxa,
    );
    if (passo == null) return;

    final tituloBase =
        revisao.titulo.replaceFirst(RegExp(r' \((\d+d|reforço)\)$'), '');
    final proxima = Revisao(
      id: const Uuid().v4(),
      materiaId: revisao.materiaId,
      topicoId: revisao.topicoId,
      titulo:
          passo.reforco ? '$tituloBase (reforço)' : '$tituloBase (${passo.dias}d)',
      dataAgendada:
          DateTime(agora.year, agora.month, agora.day + passo.dias),
      intervaloDias: passo.intervalo,
      estabilidade: passo.estabilidade,
      dificuldade: passo.dificuldade,
    );
    await ref.read(revisoesProvider.notifier).salvar(proxima);
    await NotificacoesService.agendarRevisao(
      id: proxima.id,
      titulo: proxima.titulo,
      dia: proxima.dataAgendada,
      hora: config.horaNotificacao,
    );
    if (mounted) {
      final motivo = passo.reforco
          ? 'Acerto ${(taxa! * 100).toStringAsFixed(0)}% abaixo de 75% — reforço em ${passo.dias}d'
          : 'Próxima em ${passo.dias}d';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Feita. $motivo (${formatarData(proxima.dataAgendada)}).')));
    }
  }

  Future<void> _adiar(Revisao revisao, int dias) async {
    final base = revisao.dataAgendada;
    final nova = revisao.copyWith(
        dataAgendada: DateTime(base.year, base.month, base.day + dias));
    await ref.read(revisoesProvider.notifier).salvar(nova);
    await NotificacoesService.cancelar(revisao.id);
    await NotificacoesService.agendarRevisao(
      id: nova.id,
      titulo: nova.titulo,
      dia: nova.dataAgendada,
      hora: ref.read(configuracoesProvider).horaNotificacao,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoje = DateTime.now();
    final revisoes = ref.watch(revisoesDoAmbienteProvider);
    final materias = ref.watch(materiasProvider);
    final materiasPorId = {for (final m in materias) m.id: m};

    final visiveis =
        revisoes.where((r) => r.feita == _mostrarFeitas).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Revisões')),
      floatingActionButton: FloatingActionButton(
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
                ? Center(
                    child: Text(
                        _mostrarFeitas
                            ? 'Nenhuma revisão concluída ainda.'
                            : 'Nada pendente. Salve sessões de estudo para gerar revisões.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: VizColors.muted)))
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
                            'Atrasada'
                          ),
                        RevisaoStatus.aFazer => (
                            StatusColors.atencao,
                            Icons.schedule,
                            'A fazer'
                          ),
                        RevisaoStatus.feita => (
                            StatusColors.bom,
                            Icons.check_circle_outline,
                            'Feita'
                          ),
                      };
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 10,
                          backgroundColor: corDaSerie(materia?.corSlot ?? 0),
                        ),
                        title: Text(revisao.titulo,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Row(
                          children: [
                            Icon(icone, size: 14, color: corStatus),
                            const SizedBox(width: 4),
                            Text('$rotulo · ${formatarData(revisao.dataAgendada)}',
                                style: TextStyle(color: corStatus)),
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
                                    icon: const Icon(Icons.schedule_send,
                                        color: VizColors.muted),
                                    onSelected: (dias) =>
                                        _adiar(revisao, dias),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 1,
                                          child: Text('Adiar 1 dia')),
                                      PopupMenuItem(
                                          value: 3,
                                          child: Text('Adiar 3 dias')),
                                      PopupMenuItem(
                                          value: 7,
                                          child: Text('Adiar 7 dias')),
                                    ],
                                  ),
                                  IconButton(
                                    tooltip: 'Concluir',
                                    icon: const Icon(Icons.check_circle,
                                        color: StatusColors.bom),
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
