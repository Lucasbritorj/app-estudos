import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptica.dart';
import '../../data/models/ambiente.dart';
import '../../data/models/simulado.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';

Color _corTaxa(double taxa) => taxa < 0.75
    ? StatusColors.critico
    : (taxa < 0.85 ? StatusColors.atencao : StatusColors.bom);

/// Simulados e provas reais: usuário informa tempo/questões/acertos por
/// matéria; taxa, erros e min/questão o app deriva.
class SimuladosScreen extends ConsumerWidget {
  const SimuladosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ativo = ref.watch(ambienteAtivoProvider);
    final simulados = ref
        .watch(simuladosProvider)
        .where((s) => ativo == null || s.ambienteId == ativo.id)
        .toList();
    final materiasPorId = {
      for (final m in ref.watch(materiasProvider)) m.id: m
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Simulados & Provas')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const _SimuladoForm()),
        ),
        child: const Icon(Icons.add),
      ),
      body: simulados.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nenhum simulado ou prova registrado.\n'
                  'Toque em + e informe questões e acertos por matéria — '
                  'a taxa, os erros e o tempo por questão o app calcula.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ConteudoCentral(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                itemCount: simulados.length,
                itemBuilder: (context, i) {
                  final s = simulados[i];
                  final taxa = s.taxaGeral;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ExpansionTile(
                        shape: const Border(),
                        title: Row(
                          children: [
                            Icon(
                              s.tipo == TipoSimulado.prova
                                  ? Icons.workspace_premium_outlined
                                  : Icons.fact_check_outlined,
                              size: 18,
                              color: s.tipo == TipoSimulado.prova
                                  ? LuminaColors.ouro
                                  : LuminaColors.safiraClara,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(s.nome,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            if (taxa != null)
                              Text(
                                '${(taxa * 100).toStringAsFixed(0)}%',
                                style: TextStyle(
                                    color: _corTaxa(taxa),
                                    fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          [
                            formatarData(s.data),
                            if (s.cargo.isNotEmpty) s.cargo,
                            '${s.totalAcertos}/${s.totalQuestoes} '
                                '(${s.totalErros} erros)',
                            if (s.tempoMinutos != null)
                              '${formatarMinutos(s.tempoMinutos!)}'
                                  '${s.minutosPorQuestao == null ? '' : ' · ${s.minutosPorQuestao!.toStringAsFixed(1)} min/questão'}',
                          ].join(' · '),
                          style: const TextStyle(
                              color: VizColors.muted, fontSize: 12),
                        ),
                        children: [
                          for (final r in s.resultados)
                            ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 6,
                                backgroundColor: corDaSerie(
                                    materiasPorId[r.materiaId]?.corSlot ??
                                        0),
                              ),
                              title: Text(
                                  materiasPorId[r.materiaId]?.nome ?? '—'),
                              trailing: Text(
                                '${r.acertos}/${r.questoes} · '
                                '${r.taxa == null ? '—' : '${(r.taxa! * 100).toStringAsFixed(0)}%'}',
                                style: TextStyle(
                                    color: r.taxa == null
                                        ? VizColors.muted
                                        : _corTaxa(r.taxa!)),
                              ),
                            ),
                          if (s.comentario.isNotEmpty)
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(s.comentario,
                                    style: const TextStyle(
                                        color: VizColors.inkSecondary,
                                        fontSize: 13)),
                              ),
                            ),
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  label: const Text('Excluir'),
                                  onPressed: () async {
                                    final confirmado =
                                        await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) =>
                                          AlertDialog(
                                        title:
                                            Text('Excluir ${s.nome}?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(
                                                    dialogContext, false),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(
                                                    dialogContext, true),
                                            child: const Text('Excluir'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmado == true) {
                                      await ref
                                          .read(simuladosProvider.notifier)
                                          .remover(s.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Linha editável do formulário: matéria + questões + acertos.
class _LinhaResultado {
  String? materiaId;
  final questoes = TextEditingController();
  final acertos = TextEditingController();

  void dispose() {
    questoes.dispose();
    acertos.dispose();
  }
}

class _SimuladoForm extends ConsumerStatefulWidget {
  const _SimuladoForm();

  @override
  ConsumerState<_SimuladoForm> createState() => _SimuladoFormState();
}

class _SimuladoFormState extends ConsumerState<_SimuladoForm> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _cargo = TextEditingController();
  final _tempo = TextEditingController();
  final _comentario = TextEditingController();
  var _tipo = TipoSimulado.simulado;
  DateTime _data = DateTime.now();
  final _linhas = [_LinhaResultado()];

  @override
  void dispose() {
    _nome.dispose();
    _cargo.dispose();
    _tempo.dispose();
    _comentario.dispose();
    for (final l in _linhas) {
      l.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text);

  /// Prévia derivada ao vivo — mesmo cálculo do model.
  String get _previa {
    var questoes = 0;
    var acertos = 0;
    for (final l in _linhas) {
      questoes += _int(l.questoes) ?? 0;
      acertos += _int(l.acertos) ?? 0;
    }
    if (questoes == 0) return '';
    final taxa = acertos * 100 / questoes;
    final tempo = _int(_tempo);
    return 'Total: $acertos/$questoes · ${(questoes - acertos)} erros · '
        '${taxa.toStringAsFixed(0)}%'
        '${tempo == null || tempo <= 0 ? '' : ' · ${(tempo / questoes).toStringAsFixed(1)} min/questão'}';
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final resultados = <ResultadoMateria>[];
    for (final l in _linhas) {
      final materiaId = l.materiaId;
      final questoes = _int(l.questoes);
      if (materiaId == null || questoes == null || questoes <= 0) continue;
      resultados.add(ResultadoMateria(
        materiaId: materiaId,
        questoes: questoes,
        acertos: _int(l.acertos) ?? 0,
      ));
    }
    if (resultados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Informe pelo menos uma matéria com questões.')));
      return;
    }
    final simulado = Simulado(
      id: const Uuid().v4(),
      ambienteId:
          ref.read(ambienteAtivoProvider)?.id ?? Ambiente.geralId,
      tipo: _tipo,
      nome: _nome.text.trim(),
      cargo: _tipo == TipoSimulado.prova ? _cargo.text.trim() : '',
      data: _data,
      tempoMinutos: _int(_tempo),
      resultados: resultados,
      comentario: _comentario.text.trim(),
    );
    await ref.read(simuladosProvider.notifier).salvar(simulado);
    Haptica.celebrar();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final materias = ref
        .watch(materiasDoAmbienteProvider)
        .where((m) => !m.arquivada)
        .toList();
    final prova = _tipo == TipoSimulado.prova;

    return Scaffold(
      appBar: AppBar(
          title: Text(prova ? 'Nova prova' : 'Novo simulado')),
      body: ConteudoCentral(
        maxWidth: 640,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<TipoSimulado>(
                segments: const [
                  ButtonSegment(
                      value: TipoSimulado.simulado,
                      label: Text('Simulado'),
                      icon: Icon(Icons.fact_check_outlined)),
                  ButtonSegment(
                      value: TipoSimulado.prova,
                      label: Text('Prova real'),
                      icon: Icon(Icons.workspace_premium_outlined)),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) =>
                    setState(() => _tipo = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nome,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: 'Nome *',
                    hintText: prova
                        ? 'Ex.: SEFAZ-RN 2026 — objetiva'
                        : 'Ex.: Simulado FGV nº 3'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Obrigatório'
                    : null,
              ),
              if (prova) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cargo,
                  decoration: const InputDecoration(
                      labelText: 'Cargo / banca',
                      hintText: 'Ex.: Auditor Fiscal — FGV'),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final escolhida = await showDatePicker(
                          context: context,
                          initialDate: _data,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (escolhida != null) {
                          setState(() => _data = escolhida);
                        }
                      },
                      child: InputDecorator(
                        decoration:
                            const InputDecoration(labelText: 'Data'),
                        child: Text(formatarData(_data)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _tempo,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Tempo total (min)'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Resultado por matéria',
                  style: TextStyle(color: VizColors.inkSecondary)),
              const SizedBox(height: 4),
              for (var i = 0; i < _linhas.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: DropdownButtonFormField<String>(
                          initialValue: _linhas[i].materiaId,
                          decoration: const InputDecoration(
                              labelText: 'Matéria *'),
                          items: [
                            for (final m in materias)
                              DropdownMenuItem(
                                  value: m.id, child: Text(m.nome)),
                          ],
                          validator: (v) =>
                              v == null ? 'Escolha' : null,
                          onChanged: (v) =>
                              setState(() => _linhas[i].materiaId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _linhas[i].questoes,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Questões *'),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            if (n == null || n <= 0) return '> 0';
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _linhas[i].acertos,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Acertos *'),
                          validator: (v) {
                            final acertos = int.tryParse(v ?? '');
                            if (acertos == null || acertos < 0) {
                              return 'Inválido';
                            }
                            final questoes =
                                _int(_linhas[i].questoes);
                            if (questoes != null &&
                                acertos > questoes) {
                              return '> questões';
                            }
                            return null;
                          },
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      if (_linhas.length > 1)
                        IconButton(
                          tooltip: 'Remover linha',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() =>
                              _linhas.removeAt(i).dispose()),
                        ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar matéria'),
                  onPressed: () =>
                      setState(() => _linhas.add(_LinhaResultado())),
                ),
              ),
              if (_previa.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(_previa,
                      style: const TextStyle(
                          color: LuminaColors.safiraClara,
                          fontSize: 13)),
                ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _comentario,
                decoration:
                    const InputDecoration(labelText: 'Comentário'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _salvar,
                child: const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
