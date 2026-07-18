import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar_cor.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/notas_editor.dart';
import '../../data/models/aula.dart';
import '../../data/models/materia.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/aula_service.dart';
import '../../domain/dominio_service.dart';
import '../../domain/leitura_service.dart';
import '../../domain/mapa_estudos_service.dart';
import '../../domain/planejamento_service.dart';
import '../../domain/stats_service.dart';
import '../registro/registro_form.dart';

Color _corDaTaxa(double? taxa) =>
    taxa == null ? VizColors.muted : StatusColors.porTaxa(taxa);

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
    // Diagnóstico pela medição Elo (mesma régua do ciclo/prontidão); a taxa
    // acumulada continua exibida como percentual informativo.
    final medidos = DominioService.dominioPorMateria(
      registros,
      materias.map((m) => m.id),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mapa de Estudos')),
      body: materias.isEmpty
          ? const Center(
              child: Text(
                'Cadastre matérias para montar o mapa.',
                style: TextStyle(color: VizColors.muted),
              ),
            )
          : ConteudoCentral(
              child: ListView(
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
                      medicao: medidos[materia.id],
                      taxa: switch (desempenho[materia.id]) {
                        null => null,
                        final d when d.questoes == 0 => null,
                        final d => d.acertos / d.questoes,
                      },
                      progressoLeitura: LeituraService.progressoDaMateria(
                        leituras,
                        materia.id,
                      ),
                      minutosParaTerminar: LeituraService.minutosParaTerminar(
                        LeituraService.paginasRestantesDaMateria(
                          leituras,
                          materia.id,
                        ),
                        StatsService.paginasPorHoraGeral(
                          registros,
                          materiaId: materia.id,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _MateriaTile extends ConsumerWidget {
  final Materia materia;
  final List<Aula> aulas;
  final List<Topico> topicos;
  final int minutos;
  final MedicaoDominio? medicao;
  final double? taxa;
  final double? progressoLeitura;
  final int? minutosParaTerminar;

  const _MateriaTile({
    required this.materia,
    required this.aulas,
    required this.topicos,
    required this.minutos,
    required this.medicao,
    required this.taxa,
    required this.progressoLeitura,
    required this.minutosParaTerminar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostico = PlanejamentoService.diagnostico(
      materia.intimidade,
      medicao,
    );
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
      leading: AvatarCor(slot: materia.corSlot),
      title: Row(
        children: [
          Expanded(child: Text(materia.nome)),
          if (taxa != null)
            Text(
              '${(taxa! * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: _corDaTaxa(taxa), fontSize: 13),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (resumo.isNotEmpty)
            Text(
              resumo,
              style: const TextStyle(color: VizColors.muted, fontSize: 12),
            ),
          if (diagnostico == DiagnosticoMateria.falsoDominio)
            const _ChipDiagnostico(
              icone: Icons.warning_amber,
              cor: StatusColors.critico,
              texto: 'Falso domínio — reforce revisão e questões',
            ),
          if (diagnostico == DiagnosticoMateria.teoriaPrioritaria)
            const _ChipDiagnostico(
              icone: Icons.menu_book_outlined,
              cor: StatusColors.atencao,
              texto: 'Iniciante — priorize leitura/teoria',
            ),
          if (diagnostico == DiagnosticoMateria.dominada)
            const _ChipDiagnostico(
              icone: Icons.verified_outlined,
              cor: StatusColors.bom,
              texto: 'Dominada — só manutenção',
            ),
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
              style: TextStyle(color: VizColors.muted),
            ),
          ),
        ..._linhasDeTopicos(ref),
      ],
    );
  }

  /// Árvore completa em profundidade arbitrária (edital importado tem
  /// níveis 2+; renderizar só raiz+filho fazia ramos sumirem do mapa).
  /// Métricas calculadas UMA vez por matéria, nunca por linha.
  List<Widget> _linhasDeTopicos(WidgetRef ref) {
    final registros = ref.watch(registrosProvider);
    final metricas = MapaEstudosService.metricasPorTopico(topicos, registros);
    final filhosDe = <String?, List<Topico>>{};
    for (final t in topicos) {
      (filhosDe[t.parentId] ??= []).add(t);
    }

    final linhas = <Widget>[];
    void adicionar(Topico t, int nivel) {
      linhas.add(
        _TopicoLinha(
          topico: t,
          nivel: nivel,
          metricas: metricas[t.id]!,
          topicosDaMateria: topicos,
        ),
      );
      for (final filho in filhosDe[t.id] ?? const <Topico>[]) {
        adicionar(filho, nivel + 1);
      }
    }

    for (final raiz in filhosDe[null] ?? const <Topico>[]) {
      adicionar(raiz, 0);
    }
    return linhas;
  }
}

class _ChipDiagnostico extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String texto;

  const _ChipDiagnostico({
    required this.icone,
    required this.cor,
    required this.texto,
  });

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
            child: Text(texto, style: TextStyle(color: cor, fontSize: 12)),
          ),
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
          Text(
            detalhe,
            style: const TextStyle(color: VizColors.muted, fontSize: 12),
          ),
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
        onPressed: () => mostrarFormularioRegistro(
          context,
          materiaInicial: aula.materiaId,
          aulaInicial: aula.id,
        ),
      ),
    );
  }
}

class _TopicoLinha extends ConsumerWidget {
  final Topico topico;
  final int nivel;

  final MetricasTopico metricas;
  final List<Topico> topicosDaMateria;

  const _TopicoLinha({
    required this.topico,
    required this.nivel,
    required this.metricas,
    required this.topicosDaMateria,
  });

  Future<void> _notaRapida(
    BuildContext context,
    WidgetRef ref,
    Topico topico,
  ) async {
    final controlador = TextEditingController(text: topico.notas);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Anotações — ${topico.nome}'),
        content: SizedBox(
          width: 380,
          child: NotasEditor(controller: controlador),
        ),
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
    BuildContext context,
    WidgetRef ref,
    List<Topico> todos,
  ) async {
    final candidatos =
        todos
            .where((t) => t.materiaId == topico.materiaId && t.id != topico.id)
            .toList()
          ..sort(
            (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
          );
    if (candidatos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cadastre outro tópico nesta matéria para definir pré-requisitos.',
          ),
        ),
      );
      return;
    }

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
                    title: Text(
                      c.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle:
                        !selecionados.contains(c.id) &&
                            MapaEstudosService.criariaCiclo(
                              todos,
                              topico.id,
                              c.id,
                            )
                        ? const Text(
                            'criaria ciclo',
                            style: TextStyle(
                              color: StatusColors.critico,
                              fontSize: 11,
                            ),
                          )
                        : null,
                    onChanged:
                        !selecionados.contains(c.id) &&
                            MapaEstudosService.criariaCiclo(
                              todos,
                              topico.id,
                              c.id,
                            )
                        ? null
                        : (v) => setStateDialog(
                            () => v == true
                                ? selecionados.add(c.id)
                                : selecionados.remove(c.id),
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
                ref
                    .read(topicosProvider.notifier)
                    .salvar(
                      topico.copyWith(prerequisitos: selecionados.toList()),
                    );
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
    final status = metricas.status;
    final taxa = metricas.taxa;
    final dominio = metricas.dominio;
    final bloqueios = metricas.bloqueadoPor;

    // Cor pela estimativa de domínio (evidência recente pesa mais) quando a
    // amostra é confiável; senão pela taxa acumulada, como antes.
    final corDesempenho = dominio != null && dominio.confiavel
        ? _corDaTaxa(dominio.dominio)
        : _corDaTaxa(taxa);

    var (icone, cor, rotulo) = switch (status) {
      StatusTopico.naoIniciado => (
        Icons.radio_button_unchecked,
        VizColors.muted,
        'Não iniciado',
      ),
      StatusTopico.emEstudo => (
        Icons.play_circle_outline,
        seriesColors[0],
        'Em estudo · ${formatarMinutos(metricas.minutos)}',
      ),
      StatusTopico.concluido => (
        Icons.check_circle,
        corDesempenho,
        taxa == null
            ? 'Concluído · sem questões'
            : 'Concluído · ${(taxa * 100).toStringAsFixed(0)}% de acerto',
      ),
    };
    if (status != StatusTopico.concluido && bloqueios.isNotEmpty) {
      icone = Icons.lock_outline;
      rotulo =
          'Bloqueado · requer '
          '${bloqueios.map((b) => b.nome).join(', ')}';
    }

    final sufixoDominio = dominio == null
        ? ''
        : ' · domínio ${(dominio.dominio * 100).toStringAsFixed(0)}%'
              '${dominio.confiavel ? '' : ' (pouca amostra)'}';
    final linhaStatus =
        (taxa != null && status == StatusTopico.emEstudo
            ? '$rotulo · ${(taxa * 100).toStringAsFixed(0)}% de acerto'
            : rotulo) +
        sufixoDominio;
    // Pré-requisitos já satisfeitos ainda aparecem — a dependência existe
    // no grafo mesmo depois de liberada (não é só "bloqueado").
    final temPreReqs = topico.prerequisitos.isNotEmpty;

    return Semantics(
      label:
          '${topico.nome}. $linhaStatus'
          '${topico.notas.isEmpty ? '' : '. Com anotações'}',
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.only(left: 24.0 + nivel * 20, right: 4),
        leading: Icon(icone, size: 20, color: cor),
        title: Text(topico.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(linhaStatus, style: TextStyle(color: cor, fontSize: 12)),
            if (temPreReqs && bloqueios.isEmpty)
              Row(
                children: [
                  const Icon(
                    Icons.account_tree_outlined,
                    size: 12,
                    color: VizColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'pré-req: '
                      '${topico.prerequisitos.length} tópico'
                      '${topico.prerequisitos.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: VizColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: topico.concluido,
              onChanged: (v) => ref
                  .read(topicosProvider.notifier)
                  .salvar(topico.copyWith(concluido: v ?? false)),
            ),
            PopupMenuButton<String>(
              tooltip: 'Ações do tópico',
              icon: Icon(
                topico.notas.isEmpty ? Icons.more_vert : Icons.sticky_note_2,
                color: topico.notas.isEmpty ? VizColors.muted : seriesColors[2],
              ),
              onSelected: (acao) {
                switch (acao) {
                  case 'registrar':
                    mostrarFormularioRegistro(
                      context,
                      materiaInicial: topico.materiaId,
                      topicoInicial: topico.id,
                    );
                  case 'notas':
                    _notaRapida(context, ref, topico);
                  case 'prereqs':
                    _editarPrerequisitos(context, ref, topicosDaMateria);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'registrar',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.play_arrow),
                    title: Text('Registrar estudo'),
                  ),
                ),
                PopupMenuItem(
                  value: 'notas',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.sticky_note_2_outlined),
                    title: Text(
                      topico.notas.isEmpty ? 'Anotações' : 'Editar anotações',
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'prereqs',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_tree_outlined),
                    title: Text(
                      temPreReqs
                          ? 'Pré-requisitos (${topico.prerequisitos.length})'
                          : 'Definir pré-requisitos',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
