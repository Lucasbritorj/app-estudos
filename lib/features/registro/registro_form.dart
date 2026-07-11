import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/notificacoes/notificacoes_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptica.dart';
import '../../data/models/registro_hora.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/aula_service.dart';
import '../../domain/revisao_service.dart';
import '../materias/materia_dialog.dart';
import '../revisoes/criar_revisoes.dart';

/// Abre o formulário de registro. Retorna true se um registro foi salvo.
Future<bool> mostrarFormularioRegistro(BuildContext context,
    {Duration? duracao,
    String? materiaInicial,
    String? topicoInicial,
    String? aulaInicial,
    TipoEstudo? tipoInicial}) async {
  final salvo = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RegistroForm(
        duracao: duracao,
        materiaInicial: materiaInicial,
        topicoInicial: topicoInicial,
        aulaInicial: aulaInicial,
        tipoInicial: tipoInicial),
  );
  return salvo ?? false;
}

class RegistroForm extends ConsumerStatefulWidget {
  final Duration? duracao;
  final String? materiaInicial;
  final String? topicoInicial;
  final String? aulaInicial;
  final TipoEstudo? tipoInicial;

  const RegistroForm(
      {super.key,
      this.duracao,
      this.materiaInicial,
      this.topicoInicial,
      this.aulaInicial,
      this.tipoInicial});

  @override
  ConsumerState<RegistroForm> createState() => _RegistroFormState();
}

class _RegistroFormState extends ConsumerState<RegistroForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _minutos;
  final _tarefa = TextEditingController();
  final _paginasSessao = TextEditingController();
  final _comentario = TextEditingController();
  final _questoes = TextEditingController();
  final _acertos = TextEditingController();
  String? _materiaId;
  String? _topicoId;
  String? _aulaId;
  late TipoEstudo _tipo;
  DateTime _data = DateTime.now();

  /// Tempo por "Início/Fim" em vez de minutos digitados.
  var _modoInicioFim = false;
  TimeOfDay? _inicio;
  TimeOfDay? _fim;

  /// Minutos líquidos entre início e fim; atravessa meia-noite (+24h).
  int? get _minutosDeInicioFim {
    final ini = _inicio;
    final fim = _fim;
    if (ini == null || fim == null) return null;
    var minutos = (fim.hour * 60 + fim.minute) - (ini.hour * 60 + ini.minute);
    if (minutos <= 0) minutos += 24 * 60;
    return minutos;
  }

  int? get _minutosInformados => _modoInicioFim
      ? _minutosDeInicioFim
      : int.tryParse(_minutos.text);

  @override
  void initState() {
    super.initState();
    _materiaId = widget.materiaInicial;
    _topicoId = widget.topicoInicial;
    _aulaId = widget.aulaInicial;
    _tipo = widget.tipoInicial ?? TipoEstudo.teoria;
    final minutosIniciais = widget.duracao?.inMinutes;
    _minutos = TextEditingController(
        text: minutosIniciais == null
            ? ''
            : (minutosIniciais < 1 ? 1 : minutosIniciais).toString());
  }

  @override
  void dispose() {
    _minutos.dispose();
    _tarefa.dispose();
    _paginasSessao.dispose();
    _comentario.dispose();
    _questoes.dispose();
    _acertos.dispose();
    super.dispose();
  }

  int? get _paginasLidas => int.tryParse(_paginasSessao.text);

  String get _previaRitmo {
    final paginas = _paginasLidas;
    final minutos = _minutosInformados;
    if (paginas == null) return '';
    if (minutos == null || minutos <= 0) return '$paginas páginas lidas';
    final ritmo = paginas / (minutos / 60.0);
    return '$paginas páginas · ${ritmo.toStringAsFixed(1)} pág/h';
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final minutos = _minutosInformados;
    if (minutos == null || minutos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Informe início e fim da sessão.')));
      return;
    }
    final teoria = _tipo == TipoEstudo.teoria;
    final agora = DateTime.now();
    final registro = RegistroHora(
      id: const Uuid().v4(),
      data: DateTime(
          _data.year, _data.month, _data.day, agora.hour, agora.minute),
      materiaId: _materiaId!,
      topicoId: teoria ? null : _topicoId,
      aulaId: _aulaId,
      tipo: _tipo,
      tarefa: _tarefa.text.trim(),
      minutos: minutos,
      paginasLidasManual: teoria ? _paginasLidas : null,
      comentario:
          _comentario.text.trim().isEmpty ? null : _comentario.text.trim(),
      questoes: teoria ? null : int.tryParse(_questoes.text),
      acertos: teoria ? null : int.tryParse(_acertos.text),
    );
    await ref.read(registrosProvider.notifier).salvar(registro);

    // Estudo teórico com aula: acumula páginas; concluir a aula é O gatilho
    // da cadeia de revisões (Revisão 1 nasce da data de conclusão do PDF).
    String? avisoAula;
    final paginas = teoria ? (_paginasLidas ?? 0) : 0;
    final aula = _aulaId == null
        ? null
        : ref.read(aulasProvider).where((a) => a.id == _aulaId).firstOrNull;
    if (aula != null && paginas > 0) {
      final resultado =
          AulaService.aplicarSessao(aula, paginas, registro.data);
      await ref.read(aulasProvider.notifier).salvar(resultado.aula);
      if (resultado.concluiuAgora) {
        final materia = ref
            .read(materiasProvider)
            .where((m) => m.id == _materiaId)
            .firstOrNull;
        final primeira = await criarCadeiaParaAula(
            ref, resultado.aula, materia?.nome ?? 'Estudo');
        avisoAula = primeira == null
            ? '${aula.nome} concluída!'
            : '${aula.nome} concluída! Revisão 1 em '
                '${primeira.intervaloDias}d (${formatarData(primeira.dataAgendada)})';
      } else {
        avisoAula =
            '${resultado.aula.paginasLidas}/${resultado.aula.paginasTotais} '
            'páginas da ${aula.nome}';
      }
    }

    // Revisões pendentes do tópico reancoram no último estudo (prática).
    var reagendadas = 0;
    if (registro.topicoId != null) {
      final config = ref.read(configuracoesProvider);
      final alteradas = RevisaoService.reagendarPorEstudo(
          ref.read(revisoesProvider), registro.topicoId!, registro.data);
      for (final revisao in alteradas) {
        await ref.read(revisoesProvider.notifier).salvar(revisao);
        await NotificacoesService.cancelar(revisao.id);
        await NotificacoesService.agendarRevisao(
          id: revisao.id,
          titulo: revisao.titulo,
          dia: revisao.dataAgendada,
          hora: config.horaNotificacao,
        );
      }
      reagendadas = alteradas.length;
    }

    if (!mounted) return;
    // Aula concluída merece celebração; registro comum, confirmação leve.
    if (avisoAula != null && avisoAula.contains('concluída')) {
      Haptica.celebrar();
    } else {
      Haptica.leve();
    }
    Navigator.pop(context, true);
    final sufixo = [
      ?avisoAula,
      if (reagendadas > 0) '$reagendadas revisões reancoradas',
    ].map((s) => ' · $s').join();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Registro salvo: ${formatarMinutos(registro.minutos)}$sufixo')),
    );
  }

  @override
  Widget build(BuildContext context) {
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

    if (materias.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nenhuma matéria cadastrada ainda.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => mostrarDialogoMateria(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('Criar matéria'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Registrar sessão',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              // Dualidade explícita: cada sessão é teoria OU prática, e o
              // tempo líquido fica gravado com a flag correspondente.
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
              DropdownButtonFormField<String>(
                initialValue: _materiaId,
                decoration: const InputDecoration(labelText: 'Matéria *'),
                items: [
                  for (final m in materias)
                    DropdownMenuItem(value: m.id, child: Text(m.nome)),
                ],
                validator: (v) => v == null ? 'Escolha a matéria' : null,
                onChanged: (v) => setState(() {
                  _materiaId = v;
                  _topicoId = null;
                  _aulaId = null;
                }),
              ),
              if (aulas.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _aulaId,
                  decoration: InputDecoration(
                      labelText: teoria ? 'Aula *' : 'Aula (opcional)'),
                  items: [
                    if (!teoria)
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('— sem aula —')),
                    for (final a in aulas)
                      DropdownMenuItem<String?>(
                          value: a.id,
                          child: Text(
                              '${a.nome} · ${a.paginasLidas}/${a.paginasTotais} pág')),
                  ],
                  validator: (v) => teoria && v == null && aulas.isNotEmpty
                      ? 'Escolha a aula do PDF'
                      : null,
                  onChanged: (v) => setState(() => _aulaId = v),
                ),
              ] else if (teoria && _materiaId != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      'Sem aulas cadastradas nesta matéria — cadastre em '
                      'Matérias > Aulas para acompanhar o progresso do PDF.',
                      style: TextStyle(fontSize: 12)),
                ),
              if (!teoria && topicos.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _topicoId,
                  decoration:
                      const InputDecoration(labelText: 'Tópico (opcional)'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('— sem tópico —')),
                    for (final t in topicos)
                      DropdownMenuItem<String?>(
                          value: t.id, child: Text(t.nome)),
                  ],
                  onChanged: (v) => setState(() => _topicoId = v),
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _tarefa,
                decoration: const InputDecoration(
                    labelText: 'Tarefa / aula',
                    hintText: 'Ex.: Aula 12 — AFO, questões Cebraspe'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                      value: false,
                      label: Text('Minutos'),
                      icon: Icon(Icons.timer_outlined)),
                  ButtonSegment(
                      value: true,
                      label: Text('Início/Fim'),
                      icon: Icon(Icons.schedule)),
                ],
                selected: {_modoInicioFim},
                onSelectionChanged: (s) =>
                    setState(() => _modoInicioFim = s.first),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_modoInicioFim) ...[
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final hora = await showTimePicker(
                              context: context,
                              initialTime: _inicio ??
                                  const TimeOfDay(hour: 8, minute: 0));
                          if (hora != null) setState(() => _inicio = hora);
                        },
                        child: InputDecorator(
                          decoration:
                              const InputDecoration(labelText: 'Início *'),
                          child: Text(_inicio?.format(context) ?? '—'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final hora = await showTimePicker(
                              context: context,
                              initialTime: _fim ?? TimeOfDay.now());
                          if (hora != null) setState(() => _fim = hora);
                        },
                        child: InputDecorator(
                          decoration:
                              const InputDecoration(labelText: 'Fim *'),
                          child: Text(_fim?.format(context) ?? '—'),
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: TextFormField(
                        controller: _minutos,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Minutos *'),
                        validator: (v) {
                          if (_modoInicioFim) return null;
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Minutos > 0';
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  const SizedBox(width: 8),
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
                        decoration: const InputDecoration(labelText: 'Data'),
                        child: Text(formatarData(_data)),
                      ),
                    ),
                  ),
                ],
              ),
              if (_modoInicioFim && _minutosDeInicioFim != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'Tempo líquido: ${formatarMinutos(_minutosDeInicioFim!)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              if (teoria) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _paginasSessao,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Páginas lidas nesta sessão',
                      helperText:
                          'Acumula na aula; ao completar o PDF, a Revisão 1 (7d) é agendada'),
                  validator: (v) {
                    if (v == null || v.isEmpty) return null;
                    final n = int.tryParse(v);
                    if (n == null || n < 0) return 'Número inválido';
                    return null;
                  },
                  onChanged: (_) => setState(() {}),
                ),
                if (_previaRitmo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_previaRitmo,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ] else ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _questoes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Questões resolvidas *'),
                        validator: (v) {
                          if (_tipo != TipoEstudo.pratica) return null;
                          final n = int.tryParse(v ?? '');
                          if (n == null || n <= 0) return 'Questões > 0';
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _acertos,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Acertos *'),
                        validator: (v) {
                          if (_tipo != TipoEstudo.pratica) return null;
                          final questoes = int.tryParse(_questoes.text);
                          final acertos = int.tryParse(v ?? '');
                          if (acertos == null) return 'Informe os acertos';
                          if (questoes != null && acertos > questoes) {
                            return 'Maior que questões';
                          }
                          return null;
                        },
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (int.tryParse(_questoes.text) != null &&
                    int.tryParse(_acertos.text) != null &&
                    int.parse(_acertos.text) <= int.parse(_questoes.text))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        'Erros: ${int.parse(_questoes.text) - int.parse(_acertos.text)} · '
                        'acerto ${(int.parse(_acertos.text) * 100 / int.parse(_questoes.text)).toStringAsFixed(0)}%',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _comentario,
                decoration: const InputDecoration(labelText: 'Comentário'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _salvar,
                child: const Text('Salvar registro'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
