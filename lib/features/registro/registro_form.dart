import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../application/sessao_estudo_use_case.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptica.dart';
import '../../data/models/bancas.dart';
import '../../data/models/registro_hora.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/banca_service.dart';
import '../materias/materia_dialog.dart';

/// Opções do Autocomplete de banca: histórico do usuário primeiro (mais
/// relevante — ele já respondeu questões daquela banca), catálogo fixo
/// depois, sem duplicar. `Set.add` devolve false em duplicata, então a
/// segunda ocorrência (banca usada que também está no catálogo) é
/// descartada silenciosamente, preservando a ordem da primeira aparição.
List<String> _mesclarOpcoesBanca(List<String> usadas) {
  final vistas = <String>{};
  return [
    for (final b in [...usadas, ...Bancas.sugestoes])
      if (vistas.add(b)) b,
  ];
}

/// Abre o formulário de registro. Retorna true se um registro foi salvo.
Future<bool> mostrarFormularioRegistro(
  BuildContext context, {
  Duration? duracao,
  String? materiaInicial,
  String? topicoInicial,
  String? aulaInicial,
  TipoEstudo? tipoInicial,
}) async {
  final salvo = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RegistroForm(
      duracao: duracao,
      materiaInicial: materiaInicial,
      topicoInicial: topicoInicial,
      aulaInicial: aulaInicial,
      tipoInicial: tipoInicial,
    ),
  );
  return salvo ?? false;
}

class RegistroForm extends ConsumerStatefulWidget {
  final Duration? duracao;
  final String? materiaInicial;
  final String? topicoInicial;
  final String? aulaInicial;
  final TipoEstudo? tipoInicial;

  const RegistroForm({
    super.key,
    this.duracao,
    this.materiaInicial,
    this.topicoInicial,
    this.aulaInicial,
    this.tipoInicial,
  });

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
  final _banca = TextEditingController();
  final _bancaFocus = FocusNode();
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
  /// Início == fim retorna null (obriga correção) — antes o `<= 0` virava
  /// 1440 min: um toque errado injetava 24h fantasma em horas/meta/XP/streak.
  int? get _minutosDeInicioFim {
    final ini = _inicio;
    final fim = _fim;
    if (ini == null || fim == null) return null;
    var minutos = (fim.hour * 60 + fim.minute) - (ini.hour * 60 + ini.minute);
    if (minutos == 0) return null;
    if (minutos < 0) minutos += 24 * 60;
    return minutos;
  }

  int? get _minutosInformados =>
      _modoInicioFim ? _minutosDeInicioFim : int.tryParse(_minutos.text);

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
          : (minutosIniciais < 1 ? 1 : minutosIniciais).toString(),
    );
  }

  @override
  void dispose() {
    _minutos.dispose();
    _tarefa.dispose();
    _paginasSessao.dispose();
    _comentario.dispose();
    _questoes.dispose();
    _acertos.dispose();
    _banca.dispose();
    _bancaFocus.dispose();
    super.dispose();
  }

  int? get _paginasLidas => int.tryParse(_paginasSessao.text);

  String get _previaRitmo {
    final paginas = _paginasLidas;
    final minutos = _minutosInformados;
    if (paginas == null) return '';
    if (minutos == null || minutos <= 0) return '$paginas páginas lidas';
    final ritmo = paginas / (minutos / 60.0);
    return '$paginas páginas · ${formatarDecimal(ritmo)} pág/h';
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    final minutos = _minutosInformados;
    if (minutos == null || minutos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informe início e fim válidos (fim diferente do início).'),
        ),
      );
      return;
    }
    final teoria = _tipo == TipoEstudo.teoria;
    final agora = DateTime.now();
    final registro = RegistroHora(
      id: const Uuid().v4(),
      data: DateTime(
        _data.year,
        _data.month,
        _data.day,
        agora.hour,
        agora.minute,
      ),
      materiaId: _materiaId!,
      topicoId: teoria ? null : _topicoId,
      aulaId: _aulaId,
      tipo: _tipo,
      tarefa: _tarefa.text.trim(),
      minutos: minutos,
      paginasLidasManual: teoria ? _paginasLidas : null,
      comentario: _comentario.text.trim().isEmpty
          ? null
          : _comentario.text.trim(),
      questoes: teoria ? null : int.tryParse(_questoes.text),
      acertos: teoria ? null : int.tryParse(_acertos.text),
      // Banca só existe em sessão prática; construtor normaliza (trim,
      // maiúsculas, apelido CESPE→CEBRASPE, vazio→null).
      banca: teoria ? null : _banca.text,
    );
    // Toda a orquestração (aula, cadeia de revisão, reancoragem,
    // notificações) mora no caso de uso; aqui só se formata o resultado.
    final resultado = await ref
        .read(sessaoEstudoUseCaseProvider)
        .registrar(registro);

    String? avisoAula;
    final aulaAtualizada = resultado.aulaAtualizada;
    if (aulaAtualizada != null) {
      if (resultado.aulaConcluiuAgora) {
        final primeira = resultado.primeiraRevisao;
        avisoAula = primeira == null
            ? '${aulaAtualizada.nome} concluída!'
            : '${aulaAtualizada.nome} concluída! Revisão 1 em '
                  '${primeira.intervaloDias}d (${formatarData(primeira.dataAgendada)})';
      } else {
        avisoAula =
            '${aulaAtualizada.paginasLidas}/'
            '${aulaAtualizada.paginasTotais} páginas da ${aulaAtualizada.nome}';
      }
    }
    final reagendadas = resultado.revisoesReancoradas;

    if (!mounted) return;
    // Aula concluída merece celebração; registro comum, confirmação leve.
    if (resultado.aulaConcluiuAgora) {
      Haptica.celebrar();
    } else {
      Haptica.leve();
    }
    // Messenger resolvido ANTES do pop — depois dele o context deste sheet
    // está desativado e o lookup de ancestral falha.
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context, true);
    final sufixo = [
      ?avisoAula,
      if (reagendadas > 0) '$reagendadas revisões reancoradas',
    ].map((s) => ' · $s').join();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Registro salvo: ${formatarMinutos(registro.minutos)}$sufixo',
        ),
      ),
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
    // Sugestão do Autocomplete de banca: histórico do ambiente ativo
    // primeiro (o usuário já respondeu questões daquela banca), catálogo
    // fixo depois. Não é um Provider dedicado porque só alimenta este
    // formulário — cálculo O(registros+simulados) barato de sobra pra UI.
    final ativo = ref.watch(ambienteAtivoProvider);
    final opcoesBanca = _mesclarOpcoesBanca(
      BancaService.bancasUsadas(
        ref.watch(registrosDoAmbienteProvider),
        ref
            .watch(simuladosProvider)
            .where((s) => ativo == null || s.ambienteId == ativo.id)
            .toList(),
      ),
    );

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
              Text(
                'Registrar sessão',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              // Dualidade explícita: cada sessão é teoria OU prática, e o
              // tempo líquido fica gravado com a flag correspondente.
              SegmentedButton<TipoEstudo>(
                segments: const [
                  ButtonSegment(
                    value: TipoEstudo.teoria,
                    label: Text('Estudo Teórico (PDF)'),
                    icon: Icon(Icons.menu_book_outlined),
                  ),
                  ButtonSegment(
                    value: TipoEstudo.pratica,
                    label: Text('Prática (Questões)'),
                    icon: Icon(Icons.quiz_outlined),
                  ),
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
                  decoration: const InputDecoration(
                    labelText: 'Aula (opcional)',
                  ),
                  items: [
                    // Teoria avulsa (caderno, videoaula) é legítima — aula
                    // nunca é obrigatória; sem aula só não move o PDF.
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— sem aula —'),
                    ),
                    for (final a in aulas)
                      DropdownMenuItem<String?>(
                        value: a.id,
                        child: Text(
                          '${a.nome} · ${a.paginasLidas}/${a.paginasTotais} pág',
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _aulaId = v),
                ),
              ] else if (teoria && _materiaId != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Sem aulas cadastradas nesta matéria — cadastre em '
                    'Matérias > Aulas para acompanhar o progresso do PDF.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              if (!teoria && topicos.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _topicoId,
                  decoration: const InputDecoration(
                    labelText: 'Tópico (opcional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— sem tópico —'),
                    ),
                    for (final t in topicos)
                      DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.nome),
                      ),
                  ],
                  onChanged: (v) => setState(() => _topicoId = v),
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _tarefa,
                decoration: const InputDecoration(
                  labelText: 'Tarefa / aula',
                  hintText: 'Ex.: Aula 12 — AFO, questões Cebraspe',
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Minutos'),
                    icon: Icon(Icons.timer_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Início/Fim'),
                    icon: Icon(Icons.schedule),
                  ),
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
                            initialTime:
                                _inicio ?? const TimeOfDay(hour: 8, minute: 0),
                          );
                          if (hora != null) setState(() => _inicio = hora);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Início *',
                          ),
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
                            initialTime: _fim ?? TimeOfDay.now(),
                          );
                          if (hora != null) setState(() => _fim = hora);
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Fim *'),
                          child: Text(_fim?.format(context) ?? '—'),
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: TextFormField(
                        controller: _minutos,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Minutos *',
                        ),
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
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (teoria) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _paginasSessao,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Páginas lidas nesta sessão',
                    helperText:
                        'Acumula na aula; ao completar o PDF, a Revisão 1 (7d) é agendada',
                  ),
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
                    child: Text(
                      _previaRitmo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
                          labelText: 'Questões resolvidas *',
                        ),
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
                        decoration: const InputDecoration(
                          labelText: 'Acertos *',
                        ),
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
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                // Banca só faz sentido com questões — teoria (PDF/vídeo) não
                // tem organizadora a atribuir. Autocomplete aceita texto
                // livre: banca regional fora do catálogo fixo não é
                // bloqueada, só não aparece na lista de sugestões.
                Autocomplete<String>(
                  textEditingController: _banca,
                  focusNode: _bancaFocus,
                  optionsBuilder: (TextEditingValue value) {
                    // Reusa Bancas.normalizar (maiúsculas/sem acento/apelido)
                    // pra comparar com as opções, que já vêm normalizadas —
                    // "cespe" casa com "CEBRASPE" sem lógica de filtro nova.
                    final consulta = Bancas.normalizar(value.text) ?? '';
                    if (consulta.isEmpty) return opcoesBanca;
                    return opcoesBanca.where((o) => o.contains(consulta));
                  },
                  fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                    return TextFormField(
                      key: const Key('registro_form_banca'),
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Banca (opcional)',
                        hintText: 'Ex.: CEBRASPE, FGV...',
                      ),
                    );
                  },
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
