import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/aula.dart';
import '../../data/models/materia.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/aula_service.dart';
import '../registro/registro_form.dart';
import '../revisoes/criar_revisoes.dart';

/// Aulas (PDFs) de uma matéria: progresso de páginas, ritmo médio e
/// conclusão — concluir uma aula dispara a cadeia de revisões.
class AulasScreen extends ConsumerWidget {
  final Materia materia;

  const AulasScreen({super.key, required this.materia});

  Future<void> _dialogoAula(BuildContext context, WidgetRef ref,
      {Aula? existente}) async {
    final nome = TextEditingController(text: existente?.nome ?? '');
    final paginas = TextEditingController(
        text: existente == null ? '' : '${existente.paginasTotais}');
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existente == null ? 'Nova aula' : 'Editar aula'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nome,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Nome *',
                    hintText: 'Ex.: Aula 00 — Licitações'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
              ),
              TextFormField(
                controller: paginas,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Páginas totais do PDF *'),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Inteiro > 0';
                  return null;
                },
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
              if (!formKey.currentState!.validate()) return;
              final aula = existente == null
                  ? Aula(
                      id: const Uuid().v4(),
                      materiaId: materia.id,
                      nome: nome.text.trim(),
                      paginasTotais: int.parse(paginas.text),
                    )
                  : existente.copyWith(
                      nome: nome.text.trim(),
                      paginasTotais: int.parse(paginas.text),
                    );
              ref.read(aulasProvider.notifier).salvar(aula);
              Navigator.pop(dialogContext);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  /// Concluir manualmente = completar as páginas restantes hoje.
  /// A transição dispara a Revisão 1 da cadeia, igual à conclusão por sessão.
  Future<void> _concluirManual(
      BuildContext context, WidgetRef ref, Aula aula) async {
    final resultado = AulaService.aplicarSessao(
        aula, aula.paginasRestantes, DateTime.now());
    await ref.read(aulasProvider.notifier).salvar(resultado.aula);
    if (resultado.concluiuAgora) {
      final primeira =
          await criarCadeiaParaAula(ref, resultado.aula, materia.nome);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(primeira == null
                ? '${aula.nome} concluída.'
                : '${aula.nome} concluída — Revisão 1 em '
                    '${primeira.intervaloDias}d (${formatarData(primeira.dataAgendada)}).')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aulas = ref
        .watch(aulasProvider)
        .where((a) => a.materiaId == materia.id)
        .toList();
    final registros = ref.watch(registrosProvider);

    return Scaffold(
      appBar: AppBar(title: Text('Aulas — ${materia.nome}')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _dialogoAula(context, ref),
        child: const Icon(Icons.add),
      ),
      body: aulas.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Cadastre as aulas do material (ex.: Aula 00, Aula 01) '
                  'com o total de páginas de cada PDF.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: VizColors.muted),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: aulas.length,
              itemBuilder: (context, i) {
                final aula = aulas[i];
                final ritmo = AulaService.ritmoDaAula(registros, aula.id);
                final minPorPag =
                    AulaService.minutosPorPagina(registros, aula.id);
                final investido =
                    AulaService.minutosInvestidos(registros, aula.id);
                final restante =
                    AulaService.minutosParaTerminar(aula, registros);
                final detalhe = [
                  '${aula.paginasLidas}/${aula.paginasTotais} pág',
                  if (minPorPag != null)
                    '${minPorPag.toStringAsFixed(1)} min/pág',
                  if (ritmo != null)
                    '${ritmo.toStringAsFixed(1)} pág/h',
                  if (investido > 0)
                    '${formatarMinutos(investido)} investidos',
                  if (!aula.concluida && restante != null && restante > 0)
                    'faltam ~${formatarMinutos(restante)}',
                  if (aula.concluida && aula.dataConclusao != null)
                    'concluída em ${formatarData(aula.dataConclusao!)}',
                ].join(' · ');

                return ListTile(
                  leading: Icon(
                    aula.concluida
                        ? Icons.check_circle
                        : Icons.menu_book_outlined,
                    color: aula.concluida
                        ? const Color(0xFF0CA30C)
                        : VizColors.muted,
                  ),
                  title: Text(aula.nome),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detalhe,
                          style: const TextStyle(
                              color: VizColors.muted, fontSize: 12)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: aula.progresso,
                          minHeight: 6,
                          backgroundColor: VizColors.gridline,
                          color: aula.concluida
                              ? const Color(0xFF0CA30C)
                              : seriesColors[0],
                        ),
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (acao) {
                      if (acao == 'estudar') {
                        mostrarFormularioRegistro(context,
                            materiaInicial: materia.id,
                            aulaInicial: aula.id);
                      } else if (acao == 'editar') {
                        _dialogoAula(context, ref, existente: aula);
                      } else if (acao == 'concluir') {
                        _concluirManual(context, ref, aula);
                      } else if (acao == 'excluir') {
                        ref.read(aulasProvider.notifier).remover(aula.id);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'estudar',
                          child: Text('Registrar estudo')),
                      const PopupMenuItem(
                          value: 'editar', child: Text('Editar')),
                      if (!aula.concluida)
                        const PopupMenuItem(
                            value: 'concluir',
                            child: Text('Marcar concluída')),
                      const PopupMenuItem(
                          value: 'excluir', child: Text('Excluir')),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
