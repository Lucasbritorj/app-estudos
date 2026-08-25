import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../application/backup_use_case.dart';
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
    final agora = DateTime.now();
    final inicio = StatsService.inicioDaSemana(agora);
    final fimDia = DateTime(agora.year, agora.month, agora.day);
    bool naSemana(DateTime data) {
      final d = DateTime(data.year, data.month, data.day);
      final i = DateTime(inicio.year, inicio.month, inicio.day);
      return !d.isBefore(i) && !d.isAfter(fimDia);
    }

    final registros =
        ref.read(registrosProvider).where((r) => naSemana(r.data)).toList();
    final materias = ref.read(materiasProvider);
    final materiasPorId = {for (final m in materias) m.id: m};
    final topicosPorId = {for (final t in ref.read(topicosProvider)) t.id: t};
    final resumo = StatsService.resumoDiario(registros);
    final porMateria = StatsService.minutosPorMateria(registros);
    final total = registros.fold(0, (soma, r) => soma + r.minutos);
    final ordenados = [...registros]..sort((a, b) => a.data.compareTo(b.data));
    final periodo =
        '${formatarData(inicio)} – ${formatarData(fimDia)}';
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (contexto) => [
          pw.Header(level: 0, text: 'Relatório semanal'),
          pw.Paragraph(
            text:
                '$periodo · Total: ${formatarMinutos(total)} · média/dia ${formatarMinutos(resumo.media)} · melhor dia ${formatarMinutos(resumo.maximo)}',
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
                  r.paginasPorHora == null
                      ? ''
                      : formatarDecimal(r.paginasPorHora!),
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
                  // Inclui as excluídas (tombstone): sem isso a sessão de
                  // matéria excluída saía sem nome nem peso — ver D-03.
                  materiasHistoricas: ref
                      .read(materiasProvider.notifier)
                      .historicas(),
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
                    // Dá nome, peso e ambiente reais às linhas sintéticas de
                    // dim_materia — ver D-03.
                    materiasHistoricas: ref
                        .read(materiasProvider.notifier)
                        .historicas(),
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
                'Matérias, tópicos, registros, revisões, leituras, resumos, '
                'caderno de erros, plano e configurações. Uma prova '
                'cronometrada em andamento NÃO entra — finalize antes. '
                'Fotos do enunciado anexadas ao caderno de erros deixam o '
                'arquivo bem maior.',
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
                  questoesErradas: ref.read(questoesErradasProvider),
                  anexos: ref.read(anexosQuestaoRepositorioProvider).todos(),
                  configuracoes: ref.read(configuracoesProvider),
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
                'Só as matérias e o histórico do ambiente escolhido. Fotos '
                'do caderno de erros deixam o arquivo maior.',
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

    // Aposenta o que o esquema de id por ÍNDICE deixou para trás (D-02, ver a
    // doc de PlanilhaImportService). Até 08/2026 o id embutia o número da
    // linha do Excel, então qualquer edição da planilha — inserir uma sessão,
    // apagar uma linha, clicar em "Classificar" — trocava todos os ids abaixo
    // e o `mesclar` regravava a coleção inteira em vez de atualizá-la. Sem
    // esta limpeza, o primeiro import depois da correção duplicaria tudo mais
    // uma vez, agora com ids do esquema novo.
    //
    // Só ids do esquema antigo casam (o novo começa pela data e continua com
    // hash e contador), então registro criado à mão no app nunca entra aqui.
    // `removerOnde` marca tombstone em RegistroHora — o histórico continua no
    // backup, apenas fora das contas.
    //
    // Cada limpeza é condicionada à aba correspondente ter vindo NESTE
    // arquivo: sem a guarda, importar uma planilha só de pesos do edital
    // (sem aba de Registro) apagaria todo o histórico importado antes.
    //
    // Revisões seguem a convenção da casa (`materia_use_case.dart:31`,
    // `topico_use_case.dart:45`): concluída não se destrói. Revisao não tem
    // tombstone — `removerOnde` apaga de fato —, então uma revisão que o
    // usuário fechou no app sairia sem volta. O resíduo assumido: revisões
    // antigas já concluídas ficam duplicadas uma única vez, sem crescer nos
    // imports seguintes (o id novo é estável).
    //
    // LIMITE CONHECIDO: linha que o usuário apagou da planilha depois do
    // primeiro import some do app aqui. É a consequência de tratar a planilha
    // como fonte de verdade do que veio dela — o esquema antigo mantinha a
    // linha viva, mas ao preço de duplicar todo o resto.
    //
    // CONSEQUÊNCIA ASSUMIDA: XP é 100% derivado dos registros
    // (`GamificacaoService.xpTotal`). Quem já tinha duplicatas verá o XP CAIR
    // uma vez neste import — o valor anterior contava sessões que o bug
    // fabricou. É correção, não revogação: a monotonicidade protege XP
    // legítimo, e nada aqui era.
    if (resultado.registros.isNotEmpty) {
      await ref
          .read(registrosProvider.notifier)
          .removerOnde((r) => PlanilhaImportService.idDeEsquemaAntigo(r.id));
    }
    if (resultado.revisoes.isNotEmpty) {
      await ref
          .read(revisoesProvider.notifier)
          .removerOnde(
            (r) => !r.feita && PlanilhaImportService.idDeEsquemaAntigo(r.id),
          );
    }

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
      questoesErradas: ref.read(questoesErradasProvider),
      anexos: ref.read(anexosQuestaoRepositorioProvider).todos(),
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
              await ref
                  .read(questoesErradasProvider.notifier)
                  .mesclar(backup.questoesErradas);
              await ref
                  .read(anexosQuestaoRepositorioProvider)
                  .mesclar(backup.anexos);

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

    // `texto.text` vira `backup` ANTES do pop; a cadeia de `mesclar` que roda
    // depois usa só o objeto já parseado.
    texto.dispose();
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

              // Backup parcial (de um ambiente) não pode substituir tudo:
              // leituras, resumos e planejamento não estão no arquivo e
              // seriam apagados sem volta. Só mesclar faz sentido.
              if (backup.parcial) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Este é um backup de UM ambiente: substituir tudo '
                      'apagaria leituras, resumos e o plano, que não estão '
                      'no arquivo. Use "Importar e mesclar".',
                    ),
                  ),
                );
                return;
              }

              // Capturado ANTES do diálogo: depois do await o `context` do
              // build já pode ter saído da árvore.
              final messenger = ScaffoldMessenger.of(context);
              final backupUseCase = ref.read(backupUseCaseProvider);
              final confirmado = await showDialog<bool>(
                context: context,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('Substituir todos os dados?'),
                  content: Text(
                    'O backup contém ${backup.resumo}.\n\n'
                    'Tudo que existe hoje no app será apagado. O app guarda '
                    'uma cópia do estado atual e oferece "Desfazer" logo '
                    'depois — mas ela vive só neste aparelho.',
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

              try {
                await backupUseCase.restaurarSubstituindo(backup);
              } catch (erro) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'Falha ao restaurar: $erro. Os dados anteriores foram '
                      'recolocados.',
                    ),
                  ),
                );
                return;
              }
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Backup restaurado: ${backup.resumo}.'),
                  duration: const Duration(seconds: 10),
                  action: SnackBarAction(
                    label: 'Desfazer',
                    onPressed: () async {
                      final voltou =
                          await backupUseCase.desfazerUltimaRestauracao();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            voltou
                                ? 'Importação desfeita.'
                                : 'Nada para desfazer.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
            child: const Text('Validar e importar'),
          ),
        ],
      ),
    );

    // Mesmo caso: parseBackup(texto.text) roda antes do pop. O diálogo de
    // confirmação que vem depois não toca no controller.
    texto.dispose();
  }
}
