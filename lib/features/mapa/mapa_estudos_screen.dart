import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/notas_editor.dart';
import '../../data/models/aula.dart';
import '../../data/models/materia.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/aula_service.dart';
import '../../domain/leitura_service.dart';
import '../../domain/mapa_estudos_service.dart';
import '../../domain/planejamento_service.dart';
import '../../domain/stats_service.dart';
import '../registro/registro_form.dart';

Color _corDaTaxa(double? taxa) {
  if (taxa == null) return VizColors.muted;
  if (taxa >= 0.85) return StatusColors.bom;
  if (taxa >= 0.75) return StatusColors.atencao;
  return StatusColors.critico;
}

/// Mapa de Estudos: o edital como árvore expansível, com status por tópico
/// (não iniciado / em estudo / concluído colorido pela taxa de acerto),
/// progresso de leitura e projeção de término por matéria.
class MapaEstudosScreen extends ConsumerWidget {
  const MapaEstudosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materias = ref
        .watch(materiasDoAmbienteProvider)
        .where((m) => !m.arquivada)
        .toList();
    final registros = ref.watch(registrosProvider);
    final leituras = ref.watch(leiturasProvider);
    final topicos = ref.watch(topicosProvider);
    final desempenho = StatsService.desempenhoPorMateria(registros);
    final minutosPorMateria = StatsService.minutosPorMateria(registros);

    return Scaffold(
      appBar: AppBar(title: const Text('Mapa de Estudos')),
      body: materias.isEmpty
          ? const Center(
              child: Text('Cadastre matérias para montar o mapa.',
                  style: TextStyle(color: VizColors.muted)))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final materia in materias)
                  _MateriaTile(
                    materia: materia,
                    aulas: ref
                        .watch(aulasProvider)
                        .where((a) => a.materiaId == materia.id)
                        .toList(),
                    topicos: topicos
                        .where((t) => t.materiaId == materia.id)
                        .toList(),
                    minutos: minutosPorMateria[materia.id] ?? 0,
                    taxa: switch (desempenho[materia.id]) {
                      null => null,
                      final d when d.questoes == 0 => null,
                      final d => d.acertos / d.questoes,
                    },
                    progressoLeitura: LeituraService.progressoDaMateria(
                        leituras, materia.id),
                    minutosParaTerminar: LeituraService.minutosParaTerminar(
                      LeituraService.paginasRestantesDaMateria(
                          leituras, materia.id),
                      StatsService.paginasPorHoraGeral(registros,
                          materiaId: materia.id),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _MateriaTile extends ConsumerWidget {
  final Materia materia;
  final List<Aula> aulas;
  final List<Topico> topicos;
  final int minutos;
  final double? taxa;
  final double? progressoLeitura;
  final int? minutosParaTerminar;

  const _MateriaTile({
    required this.materia,
    required this.aulas,
    required this.topicos,
    required this.minutos,
    required this.taxa,
    required this.progressoLeitura,
    required this.minutosParaTerminar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostico =
        PlanejamentoService.diagnostico(materia.intimidade, taxa);
    final raizes = topicos.where((t) => t.parentId == null).toList();
    final concluidos = topicos.where((t) => t.concluido).length;
    final aulasConcluidas = aulas.where((a) => a.concluida).length;

    final resumo = [
      if (minutos > 0) formatarMinutos(minutos),
      if (aulas.isNotEmpty) '$aulasConcluidas/${aulas.length} aulas',
      if (progressoLeitura != null)
        'leitura ${(progressoLeitura! * 100).toStringAsFixed(0)}%',
      if (minutosParaTerminar != null && minutosParaTerminar! > 0)
        'faltam ~${formatarMinutos(minutosParaTerminar!)} de leitura',
      if (topicos.isNotEmpty) '$concluidos/${topicos.length} tópicos',
    ].join(' · ');

    return ExpansionTile(
      leading: CircleAvatar(
          radius: 10, backgroundColor: corDaSerie(materia.corSlot)),
      title: Row(
        children: [
          Expanded(child: Text(materia.nome)),
          if (taxa != null)
            Text('${(taxa! * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: _corDaTaxa(taxa), fontSize: 13)),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (resumo.isNotEmpty)
            Text(resumo,
                style:
                    const TextStyle(color: VizColors.muted, fontSize: 12)),
          if (diagnostico == DiagnosticoMateria.falsoDominio)
            const _ChipDiagnostico(
                icone: Icons.warning_amber,
                cor: StatusColors.critico,
                texto: 'Falso domínio — reforce revisão e questões'),
          if (diagnostico == DiagnosticoMateria.teoriaPrioritaria)
            const _ChipDiagnostico(
                icone: Icons.menu_book_outlined,
                cor: StatusColors.atencao,
                texto: 'Iniciante — priorize leitura/teoria'),
          if (diagnostico == DiagnosticoMateria.dominada)
            const _ChipDiagnostico(
                icone: Icons.verified_outlined,
                cor: StatusColors.bom,
                texto: 'Dominada — só manutenção'),
        ],
      ),
      children: [
        for (final aula in aulas) _AulaLinha(aula: aula),
        if (aulas.isEmpty && topicos.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
                'Sem aulas nem tópicos. Cadastre as aulas do PDF em '
                'Matérias (ícone de livro) ou importe o edital.',
                style: TextStyle(color: VizColors.muted)),
          ),
        for (final raiz in raizes) ...[
          _TopicoLinha(topico: raiz, nivel: 0),
          for (final filho
              in topicos.where((t) => t.parentId == raiz.id))
            _TopicoLinha(topico: filho, nivel: 1),
        ],
      ],
    );
  }
}

class _ChipDiagnostico extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String texto;

  const _ChipDiagnostico(
      {required this.icone, required this.cor, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 14, color: cor),
          const SizedBox(width: 4),
          Flexible(
              child: Text(texto, style: TextStyle(color: cor, fontSize: 12))),
        ],
      ),
    );
  }
}

/// Linha de aula no mapa: progresso do PDF (45/150 pág), ritmo médio da
/// aula e status — concluída ganha check verde.
class _AulaLinha extends ConsumerWidget {
  final Aula aula;

  const _AulaLinha({required this.aula});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registros = ref.watch(registrosProvider);
    final ritmo = AulaService.ritmoDaAula(registros, aula.id);
    final restante = AulaService.minutosParaTerminar(aula, registros);

    final detalhe = [
      '${aula.paginasLidas}/${aula.paginasTotais} pág',
      if (ritmo != null) '${ritmo.toStringAsFixed(1)} pág/h',
      if (!aula.concluida && restante != null && restante > 0)
        'faltam ~${formatarMinutos(restante)}',
      if (aula.concluida && aula.dataConclusao != null)
        'concluída em ${formatarData(aula.dataConclusao!)}',
    ].join(' · ');

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 24, right: 8),
      leading: Icon(
        aula.concluida ? Icons.check_circle : Icons.menu_book_outlined,
        size: 20,
        color: aula.concluida ? StatusColors.bom : seriesColors[0],
      ),
      title: Text(aula.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(detalhe,
              style: const TextStyle(color: VizColors.muted, fontSize: 12)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: aula.progresso,
              minHeight: 5,
              backgroundColor: VizColors.gridline,
              color: aula.concluida ? StatusColors.bom : seriesColors[0],
            ),
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Registrar estudo desta aula',
        icon: const Icon(Icons.play_arrow, size: 18, color: VizColors.muted),
        onPressed: () => mostrarFormularioRegistro(context,
            materiaInicial: aula.materiaId, aulaInicial: aula.id),
      ),
    );
  }
}

class _TopicoLinha extends ConsumerWidget {
  final Topico topico;
  final int nivel;

  const _TopicoLinha({required this.topico, required this.nivel});

  Future<void> _notaRapida(
      BuildContext context, WidgetRef ref, Topico topico) async {
    final controlador = TextEditingController(text: topico.notas);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Anotações — ${topico.nome}'),
        content: SizedBox(width: 380, child: NotasEditor(controller: controlador)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(topicosProvider.notifier)
                  .salvar(topico.copyWith(notas: controlador.text.trim()));
              Navigator.pop(dialogContext);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  /// Editor de pré-requisitos: escolhe tópicos da mesma matéria que devem
  /// estar dominados/concluídos antes deste. Opção que criaria ciclo fica
  /// desabilitada — o grafo permanece um DAG.
  Future<void> _editarPrerequisitos(
      BuildContext context, WidgetRef ref, List<Topico> todos) async {
    final candidatos = todos
        .where((t) => t.materiaId == topico.materiaId && t.id != topico.id)
        .toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    if (candidatos.isEmpty) return;

    final selecionados = {...topico.prerequisitos};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text('Pré-requisitos — ${topico.nome}'),
          content: SizedBox(
            width: 380,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in candidatos)
                  CheckboxListTile(
                    dense: true,
                    value: selecionados.contains(c.id),
                    title: Text(c.nome,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: !selecionados.contains(c.id) &&
                            MapaEstudosService.criariaCiclo(
                                todos, topico.id, c.id)
                        ? const Text('criaria ciclo',
                            style: TextStyle(
                                color: StatusColors.critico, fontSize: 11))
                        : null,
                    onChanged: !selecionados.contains(c.id) &&
                            MapaEstudosService.criariaCiclo(
                                todos, topico.id, c.id)
                        ? null
                        : (v) => setStateDialog(() => v == true
                            ? selecionados.add(c.id)
                            : selecionados.remove(c.id)),
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
                ref.read(topicosProvider.notifier).salvar(
                    topico.copyWith(prerequisitos: selecionados.toList()));
                Navigator.pop(dialogContext);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registros = ref.watch(registrosProvider);
    final todosTopicos = ref.watch(topicosProvider);
    final status = MapaEstudosService.statusDe(topico, registros);
    final taxa = MapaEstudosService.taxaDoTopico(registros, topico.id);
    final dominio = MapaEstudosService.dominioDoTopico(registros, topico.id);
    final minutos =
        MapaEstudosService.minutosDoTopico(registros, topico.id);
    final bloqueios =
        MapaEstudosService.bloqueadoPor(topico, todosTopicos, registros);

    // Cor pela estimativa de domínio (evidência recente pesa mais) quando a
    // amostra é confiável; senão pela taxa acumulada, como antes.
    final corDesempenho = dominio != null && dominio.confiavel
        ? _corDaTaxa(dominio.dominio)
        : _corDaTaxa(taxa);

    var (icone, cor, rotulo) = switch (status) {
      StatusTopico.naoIniciado => (
          Icons.radio_button_unchecked,
          VizColors.muted,
          'Não iniciado'
        ),
      StatusTopico.emEstudo => (
          Icons.play_circle_outline,
          seriesColors[0],
          'Em estudo · ${formatarMinutos(minutos)}'
        ),
      StatusTopico.concluido => (
          Icons.check_circle,
          corDesempenho,
          taxa == null
              ? 'Concluído · sem questões'
              : 'Concluído · ${(taxa * 100).toStringAsFixed(0)}% de acerto'
        ),
    };
    if (status != StatusTopico.concluido && bloqueios.isNotEmpty) {
      icone = Icons.lock_outline;
      rotulo = 'Bloqueado · requer '
          '${bloqueios.map((b) => b.nome).join(', ')}';
    }

    final sufixoDominio = dominio == null
        ? ''
        : ' · domínio ${(dominio.dominio * 100).toStringAsFixed(0)}%'
            '${dominio.confiavel ? '' : ' (pouca amostra)'}';

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(left: 24.0 + nivel * 20, right: 8),
      leading: Icon(icone, size: 20, color: cor),
      title: Text(topico.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => _editarPrerequisitos(context, ref, todosTopicos),
      subtitle: Text(
        (taxa != null && status == StatusTopico.emEstudo
                ? '$rotulo · ${(taxa * 100).toStringAsFixed(0)}% de acerto'
                : rotulo) +
            sufixoDominio,
        style: TextStyle(color: cor, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Anotações',
            icon: Icon(
                topico.notas.isEmpty
                    ? Icons.note_add_outlined
                    : Icons.sticky_note_2,
                size: 18,
                color: topico.notas.isEmpty
                    ? VizColors.muted
                    : seriesColors[2]),
            onPressed: () => _notaRapida(context, ref, topico),
          ),
          IconButton(
            tooltip: 'Registrar estudo',
            icon: const Icon(Icons.play_arrow, size: 18,
                color: VizColors.muted),
            onPressed: () => mostrarFormularioRegistro(context,
                materiaInicial: topico.materiaId, topicoInicial: topico.id),
          ),
          Checkbox(
            value: topico.concluido,
            onChanged: (v) => ref
                .read(topicosProvider.notifier)
                .salvar(topico.copyWith(concluido: v ?? false)),
          ),
        ],
      ),
    );
  }
}
