import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/registro_hora.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../registro/registro_form.dart';
import 'cronometro_controller.dart';

class CronometroScreen extends ConsumerStatefulWidget {
  const CronometroScreen({super.key});

  @override
  ConsumerState<CronometroScreen> createState() => _CronometroScreenState();
}

class _CronometroScreenState extends ConsumerState<CronometroScreen> {
  String? _materiaId;
  String? _topicoId;
  String? _aulaId;
  var _tipo = TipoEstudo.teoria;

  Future<void> _finalizar(Duration decorrido) async {
    final controller = ref.read(cronometroProvider.notifier);
    controller.pausar();
    final salvo = await mostrarFormularioRegistro(
      context,
      duracao: decorrido,
      materiaInicial: _materiaId,
      topicoInicial: _topicoId,
      aulaInicial: _aulaId,
      tipoInicial: _tipo,
    );
    if (salvo) controller.descartar();
    // Cancelou o formulário: sessão fica pausada, nada se perde.
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(cronometroProvider);
    final controller = ref.read(cronometroProvider.notifier);
    final rodando = estado.status == CronometroStatus.rodando;
    final pausado = estado.status == CronometroStatus.pausado;
    final materias = ref
        .watch(materiasDoAmbienteProvider)
        .where((m) => !m.arquivada)
        .toList();
    final topicos = _materiaId == null
        ? const []
        : ref.watch(topicosProvider.notifier).daMateria(_materiaId!);
    final aulas = _materiaId == null
        ? const []
        : ref
            .watch(aulasProvider)
            .where((a) => a.materiaId == _materiaId)
            .toList();
    final teoria = _tipo == TipoEstudo.teoria;
    final registros = ref.watch(registrosDoAmbienteProvider);
    final materiasPorId = {for (final m in materias) m.id: m};
    final recentes = registros.take(5).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Cronômetro')),
      body: ConteudoCentral(
        maxWidth: 720,
        child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // O que esta sessão é — o tempo líquido é gravado com essa flag.
          SegmentedButton<TipoEstudo>(
            segments: const [
              ButtonSegment(
                  value: TipoEstudo.teoria,
                  label: Text('Estudo Teórico (PDF)'),
                  icon: Icon(Icons.menu_book_outlined)),
              ButtonSegment(
                  value: TipoEstudo.pratica,
                  label: Text('Prática (Questões)'),
                  icon: Icon(Icons.quiz_outlined)),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => setState(() => _tipo = s.first),
          ),
          const SizedBox(height: 12),
          // Seleção rápida antes de iniciar; vai pré-preenchida pro registro.
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _materiaId,
                  decoration: const InputDecoration(labelText: 'Matéria'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— escolher depois —')),
                    for (final m in materias)
                      DropdownMenuItem<String?>(
                          value: m.id, child: Text(m.nome)),
                  ],
                  onChanged: (v) => setState(() {
                    _materiaId = v;
                    _topicoId = null;
                    _aulaId = null;
                  }),
                ),
              ),
              if (teoria && aulas.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _aulaId,
                    decoration: const InputDecoration(labelText: 'Aula'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('— nenhuma —')),
                      for (final a in aulas)
                        DropdownMenuItem<String?>(
                            value: a.id, child: Text(a.nome)),
                    ],
                    onChanged: (v) => setState(() => _aulaId = v),
                  ),
                ),
              ],
              if (!teoria && topicos.isNotEmpty) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _topicoId,
                    decoration: const InputDecoration(labelText: 'Tópico'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('— nenhum —')),
                      for (final t in topicos)
                        DropdownMenuItem<String?>(
                            value: t.id, child: Text(t.nome)),
                    ],
                    onChanged: (v) => setState(() => _topicoId = v),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              formatarCronometro(estado.decorrido),
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: VizColors.inkPrimary,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              switch (estado.status) {
                CronometroStatus.parado => 'Pronto para estudar',
                CronometroStatus.rodando => 'Estudando — horas líquidas',
                CronometroStatus.pausado => 'Pausado',
              },
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: VizColors.muted),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            alignment: WrapAlignment.center,
            children: [
              if (estado.status == CronometroStatus.parado)
                FilledButton.icon(
                  onPressed: controller.iniciar,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar'),
                ),
              if (rodando)
                FilledButton.tonalIcon(
                  onPressed: controller.pausar,
                  icon: const Icon(Icons.pause),
                  label: const Text('Pausar'),
                ),
              if (pausado)
                FilledButton.tonalIcon(
                  onPressed: controller.retomar,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Retomar'),
                ),
              if (rodando || pausado)
                FilledButton.icon(
                  onPressed: () => _finalizar(estado.decorrido),
                  icon: const Icon(Icons.check),
                  label: const Text('Finalizar'),
                ),
            ],
          ),
          if (pausado)
            Center(
              child: TextButton(
                onPressed: controller.descartar,
                child: const Text('Descartar sessão'),
              ),
            ),
          if (recentes.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Sessões recentes',
                style: TextStyle(color: VizColors.inkSecondary)),
            const SizedBox(height: 4),
            for (final r in recentes)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 8,
                  backgroundColor:
                      corDaSerie(materiasPorId[r.materiaId]?.corSlot ?? 0),
                ),
                title: Text(
                  '${materiasPorId[r.materiaId]?.nome ?? '—'}'
                  '${r.tarefa.isEmpty ? '' : ' · ${r.tarefa}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '${formatarDiaMes(r.data)} · ${formatarMinutos(r.minutos)}',
                  style: const TextStyle(
                      color: VizColors.muted, fontSize: 12),
                ),
              ),
          ],
        ],
        ),
      ),
    );
  }
}
