import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/theme/app_theme.dart';
import '../../core/utils/compartilhador.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/ambiente.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/planejamento_repositorio.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/export_service.dart';
import '../../domain/import_service.dart';
import '../../domain/planilha_import_service.dart';
import '../../domain/stats_service.dart';
import '../../domain/xlsx_reader.dart';

class ExportarScreen extends ConsumerWidget {
  const ExportarScreen({super.key});

  String get _carimbo {
    final agora = DateTime.now();
    return '${agora.year}-${agora.month.toString().padLeft(2, '0')}-${agora.day.toString().padLeft(2, '0')}';
  }

  Future<void> _compartilharTexto(
    BuildContext context,
    String conteudo,
    String nomeArquivo,
    String mime,
  ) async {
    await _compartilharBytes(context, utf8.encode(conteudo), nomeArquivo, mime);
  }

  Future<void> _compartilharBytes(
    BuildContext context,
    Uint8List bytes,
    String nomeArquivo,
    String mime,
  ) async {
    try {
      // Implementação por plataforma (io grava temp; web manda os bytes).
      await compartilharBytes(bytes, nomeArquivo, mime);
    } catch (erro) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Falha ao exportar: $erro')));
      }
    }
  }

  Future<Uint8List> _gerarPdf(WidgetRef ref) async {
    final registros = ref.read(registrosProvider);
    final materias = ref.read(materiasProvider);
    final materiasPorId = {for (final m in materias) m.id: m};
    final topicosPorId = {for (final t in ref.read(topicosProvider)) t.id: t};
    final resumo = StatsService.resumoDiario(registros);
    final porMateria = StatsService.minutosPorMateria(registros);
    final total = registros.fold(0, (soma, r) => soma + r.minutos);
    final ordenados = [...registros]..sort((a, b) => a.data.compareTo(b.data));

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (contexto) => [
          pw.Header(level: 0, text: 'Relatório de estudos'),
          pw.Paragraph(
            text:
                'Total: ${formatarMinutos(total)} · média/dia ${formatarMinutos(resumo.media)} · melhor dia ${formatarMinutos(resumo.maximo)}',
          ),
          pw.Header(level: 1, text: 'Horas por matéria'),
          pw.TableHelper.fromTextArray(
            headers: ['Matéria', 'Horas'],
            data: [
              for (final e in porMateria.entries)
                [materiasPorId[e.key]?.nome ?? '—', formatarMinutos(e.value)],
            ],
          ),
          pw.Header(level: 1, text: 'Registro de horas'),
          pw.TableHelper.fromTextArray(
            headers: ['Data', 'Matéria', 'Tarefa', 'Min', 'Págs', 'Pág/h'],
            data: [
              for (final r in ordenados)
                [
                  formatarData(r.data),
                  materiasPorId[r.materiaId]?.nome ?? '—',
                  r.tarefa.isEmpty
                      ? (topicosPorId[r.topicoId]?.nome ?? '')
                      : r.tarefa,
                  '${r.minutos}',
                  r.paginasLidas?.toString() ?? '',
                  r.paginasPorHora?.toStringAsFixed(1) ?? '',
                ],
            ],
          ),
        ],
      ),
    );
    return doc.save();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Exportar dados')),
      body: ConteudoCentral(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV — registro de horas'),
              subtitle: const Text('Separador ; · abre direto no Excel pt-BR'),
              onTap: () {
                final csv = ExportService.csvRegistros(
                  ref.read(registrosProvider),
                  {for (final m in ref.read(materiasProvider)) m.id: m},
                  {for (final t in ref.read(topicosProvider)) t.id: t},
                );
                _compartilharTexto(
                  context,
                  csv,
                  'estudos_$_carimbo.csv',
                  'text/csv',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('CSV BI — dados brutos'),
              subtitle: const Text(
                'Flat p/ Power BI/ThoughtSpot: datas ISO, decimal com ponto',
              ),
              onTap: () {
                final csv = ExportService.csvBi(
                  ref.read(registrosProvider),
                  {for (final m in ref.read(materiasProvider)) m.id: m},
                  {for (final t in ref.read(topicosProvider)) t.id: t},
                  metaSemanalMinutos: ref
                      .read(configuracoesProvider)
                      .metaSemanalMinutos,
                );
                _compartilharTexto(
                  context,
                  csv,
                  'estudos_bi_$_carimbo.csv',
                  'text/csv',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.schema_outlined),
              title: const Text('ZIP — modelo estrela (Power BI)'),
              subtitle: const Text(
                'Tabela fato + dimensões (matéria, tópico, ambiente, '
                'calendário) prontas p/ relacionamento e DAX',
              ),
              onTap: () {
                final zip = ExportService.zipModeloEstrela(
                  ExportService.modeloEstrela(
                    registros: ref.read(registrosProvider),
                    materias: ref.read(materiasProvider),
                    topicos: ref.read(topicosProvider),
                    ambientes: ref.read(ambientesProvider),
                  ),
                );
                _compartilharBytes(
                  context,
                  zip,
                  'estudos_modelo_estrela_$_carimbo.zip',
                  'application/zip',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('JSON — backup completo'),
              subtitle: const Text(
                'Matérias, tópicos, registros, revisões, leituras, resumos e '
                'plano',
              ),
              onTap: () {
                final json = ExportService.jsonCompleto(
                  ambientes: ref.read(ambientesProvider),
                  materias: ref.read(materiasProvider),
                  topicos: ref.read(topicosProvider),
                  aulas: ref.read(aulasProvider),
                  registros: ref.read(registrosProvider),
                  revisoes: ref.read(revisoesProvider),
                  leituras: ref.read(leiturasProvider),
                  planejamento: ref.read(planejamentoProvider),
                  simulados: ref.read(simuladosProvider),
                  resumos: ref.read(resumosProvider),
                );
                _compartilharTexto(
                  context,
                  json,
                  'estudos_backup_$_carimbo.json',
                  'application/json',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.workspaces_outlined),
              title: const Text('JSON — backup de UM ambiente'),
              subtitle: const Text(
                'Só as matérias e o histórico do ambiente escolhido',
              ),
              onTap: () => _exportarAmbiente(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF — relatório'),
              subtitle: const Text('Resumo + horas por matéria + histórico'),
              onTap: () async {
                final bytes = await _gerarPdf(ref);
                if (context.mounted) {
                  await _compartilharBytes(
                    context,
                    bytes,
                    'estudos_relatorio_$_carimbo.pdf',
                    'application/pdf',
                  );
                }
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Importar backup JSON'),
              subtitle: const Text('Colar conteúdo exportado. SUBSTITUI tudo.'),
              onTap: () => _importarBackup(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.merge_outlined),
              title: const Text('Importar e MESCLAR (JSON)'),
              subtitle: const Text(
                'Adiciona/atualiza ambientes e matérias sem apagar nada — '
                'ideal p/ backup de um ambiente',
              ),
              onTap: () => _importarMesclando(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.grid_on_outlined),
              title: const Text('Importar planilha Excel (.xlsx)'),
              subtitle: const Text(
                'Todas as abas: registros, revisões, pesos do edital e '
                'meta semanal. Mescla, nunca apaga.',
              ),
              onTap: () => _importarPlanilha(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  /// Import da planilha original. Erro crítico vira AlertDialog com
  /// orientação (regra do projeto: nunca Snackbar para falha de import).
  Future<void> _importarPlanilha(BuildContext context, WidgetRef ref) async {
    const grupo = XTypeGroup(label: 'Planilha Excel', extensions: ['xlsx']);
    final arquivo = await openFile(acceptedTypeGroups: const [grupo]);
    if (arquivo == null) return;
    final bytes = await arquivo.readAsBytes();
    if (!context.mounted) return;

    final PlanilhaImportada resultado;
    try {
      final abas = XlsxReader.lerAbas(bytes);
      resultado = PlanilhaImportService.parse(
        abas,
        materiasExistentes: ref.read(materiasProvider),
      );
    } on FormatException catch (erro) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Planilha não reconhecida'),
          content: Text(
            '${erro.message}\n\nConfira se o arquivo é o .xlsx da '
            'planilha de controle de estudos (não CSV nem .xls antigo) '
            'e tente de novo.',
          ),
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

    if (!context.mounted) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Importar planilha?'),
        content: SingleChildScrollView(
          child: Text(
            [
              'Encontrado: ${resultado.resumo}.',
              if (resultado.avisos.isNotEmpty)
                '\nLinhas puladas (${resultado.avisos.length}):\n'
                    '${resultado.avisos.take(8).map((a) => '· $a').join('\n')}'
                    '${resultado.avisos.length > 8 ? '\n· …' : ''}',
              '\nNada é apagado: o import mescla com o que já existe.',
            ].join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    // Matérias novas nascem no ambiente ativo (ou "Geral" na visão global).
    final ambienteId = ref.read(ambienteAtivoProvider)?.id ?? Ambiente.geralId;
    final novas = resultado.materiasNovas
        .map((m) => m.copyWith(ambienteId: ambienteId))
        .toList();
    await ref.read(materiasProvider.notifier).mesclar([
      ...novas,
      ...resultado.materiasAtualizadas,
    ]);
    await ref.read(topicosProvider.notifier).mesclar(resultado.topicosNovos);
    await ref.read(registrosProvider.notifier).mesclar(resultado.registros);
    await ref.read(revisoesProvider.notifier).mesclar(resultado.revisoes);
    if (resultado.metaSemanalMinutos != null) {
      final config = ref.read(configuracoesProvider);
      await ref
          .read(configuracoesProvider.notifier)
          .salvar(
            config.copyWith(metaSemanalMinutos: resultado.metaSemanalMinutos),
          );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Planilha importada: ${resultado.resumo}.')),
      );
    }
  }

  Future<void> _exportarAmbiente(BuildContext context, WidgetRef ref) async {
    final ambientes = ref.read(ambientesProvider);
    final escolhido = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Qual ambiente exportar?'),
        children: [
          for (final a in ambientes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, a.id),
              child: Text(a.nome),
            ),
        ],
      ),
    );
    if (escolhido == null || !context.mounted) return;
    final ambiente = ambientes.where((a) => a.id == escolhido).firstOrNull;
    if (ambiente == null) return;
    final json = ExportService.jsonAmbiente(
      ambiente: ambiente,
      materias: ref.read(materiasProvider),
      topicos: ref.read(topicosProvider),
      aulas: ref.read(aulasProvider),
      registros: ref.read(registrosProvider),
      revisoes: ref.read(revisoesProvider),
      simulados: ref.read(simuladosProvider),
    );
    final nomeLimpo = ambiente.nome.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '_',
    );
    await _compartilharTexto(
      context,
      json,
      'ambiente_${nomeLimpo}_$_carimbo.json',
      'application/json',
    );
  }

  /// Import aditivo: mescla coleções via repo.mesclar — nada é apagado.
  /// Planejamento e configurações NÃO são tocados (são globais).
  Future<void> _importarMesclando(BuildContext context, WidgetRef ref) async {
    final texto = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Importar e mesclar'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: texto,
            autofocus: true,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Cole aqui o JSON exportado pelo app',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final BackupImportado backup;
              try {
                backup = ImportService.parseBackup(texto.text);
              } on FormatException catch (erro) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Import falhou: ${erro.message}')),
                );
                return;
              }
              Navigator.pop(dialogContext);

              await ref
                  .read(ambientesProvider.notifier)
                  .mesclar(backup.ambientesOuGeral(DateTime.now()));
              await ref
                  .read(materiasProvider.notifier)
                  .mesclar(backup.materias);
              await ref.read(topicosProvider.notifier).mesclar(backup.topicos);
              await ref.read(aulasProvider.notifier).mesclar(backup.aulas);
              await ref
                  .read(registrosProvider.notifier)
                  .mesclar(backup.registros);
              await ref
                  .read(revisoesProvider.notifier)
                  .mesclar(backup.revisoes);
              await ref
                  .read(leiturasProvider.notifier)
                  .mesclar(backup.leituras);
              await ref
                  .read(simuladosProvider.notifier)
                  .mesclar(backup.simulados);
              await ref.read(resumosProvider.notifier).mesclar(backup.resumos);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Mesclado: ${backup.resumo}.')),
                );
              }
            },
            child: const Text('Validar e mesclar'),
          ),
        ],
      ),
    );
  }

  Future<void> _importarBackup(BuildContext context, WidgetRef ref) async {
    final texto = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Importar backup'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: texto,
            autofocus: true,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Cole aqui o JSON exportado pelo app',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final BackupImportado backup;
              try {
                backup = ImportService.parseBackup(texto.text);
              } on FormatException catch (erro) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Import falhou: ${erro.message}')),
                );
                return;
              }
              Navigator.pop(dialogContext);

              final confirmado = await showDialog<bool>(
                context: context,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('Substituir todos os dados?'),
                  content: Text(
                    'O backup contém ${backup.resumo}.\n\nTudo que existe hoje no app será apagado. Não há como desfazer.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(confirmContext, true),
                      child: const Text('Substituir'),
                    ),
                  ],
                ),
              );
              if (confirmado != true) return;

              await ref
                  .read(ambientesProvider.notifier)
                  .substituirTudo(backup.ambientesOuGeral(DateTime.now()));
              // Escopo pode apontar p/ ambiente que não existe mais.
              final config = ref.read(configuracoesProvider);
              if (config.ambienteAtivoId != null) {
                await ref
                    .read(configuracoesProvider.notifier)
                    .salvar(config.copyWith(limparAmbienteAtivo: true));
              }
              await ref
                  .read(materiasProvider.notifier)
                  .substituirTudo(backup.materias);
              await ref
                  .read(topicosProvider.notifier)
                  .substituirTudo(backup.topicos);
              await ref
                  .read(aulasProvider.notifier)
                  .substituirTudo(backup.aulas);
              await ref
                  .read(registrosProvider.notifier)
                  .substituirTudo(backup.registros);
              await ref
                  .read(revisoesProvider.notifier)
                  .substituirTudo(backup.revisoes);
              await ref
                  .read(leiturasProvider.notifier)
                  .substituirTudo(backup.leituras);
              await ref
                  .read(simuladosProvider.notifier)
                  .substituirTudo(backup.simulados);
              await ref
                  .read(resumosProvider.notifier)
                  .substituirTudo(backup.resumos);
              await ref
                  .read(planejamentoProvider.notifier)
                  .substituir(backup.planejamento);

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Backup restaurado: ${backup.resumo}.'),
                  ),
                );
              }
            },
            child: const Text('Validar e importar'),
          ),
        ],
      ),
    );
  }
}
