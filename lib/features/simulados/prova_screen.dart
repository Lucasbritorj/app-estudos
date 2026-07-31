import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/avatar_cor.dart';
import '../../data/models/ambiente.dart';
import '../../data/models/bancas.dart';
import '../../data/models/execucao_prova.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/prova_service.dart';

/// Fases da tela de prova. A transição entre elas é decisão LOCAL do
/// widget (não reativa ao provider) de propósito: depois de "Corrigir e
/// salvar", a execução é apagada do Hive (`encerrar()`), e se a fase viesse
/// do provider a tela voltaria pro setup no exato momento em que deveria
/// mostrar o resultado. Ver _ProvaScreenState.
enum _Fase { setup, execucao, correcao, resultado }

/// Tela do "modo prova": setup (nome/banca/questões/duração/faixas por
/// matéria) → execução (cronômetro regressivo + folha de respostas) →
/// correção (gabarito) → resultado (grava Simulado + QuestaoErrada +
/// RegistroHora). Reabrir com uma execução ativa no Hive retoma na fase
/// certa — ver initState.
class ProvaScreen extends ConsumerStatefulWidget {
  const ProvaScreen({super.key});

  @override
  ConsumerState<ProvaScreen> createState() => _ProvaScreenState();
}

class _ProvaScreenState extends ConsumerState<ProvaScreen> {
  late _Fase _fase;

  // Snapshot da execução+correção assim que "Corrigir e salvar" roda: a
  // execução ativa some do provider nesse momento (encerrar()), então o
  // resultado precisa da própria cópia local pra renderizar.
  ExecucaoProva? _execucaoResultado;
  CorrecaoProva? _correcaoResultado;

  @override
  void initState() {
    super.initState();
    final ativa = ref.read(execucaoProvaProvider);
    _fase = ativa == null
        ? _Fase.setup
        : (ativa.ativa ? _Fase.execucao : _Fase.correcao);
  }

  @override
  Widget build(BuildContext context) {
    switch (_fase) {
      case _Fase.setup:
        return _ProvaSetup(
          onIniciado: () => setState(() => _fase = _Fase.execucao),
        );
      case _Fase.execucao:
        return _ProvaExecucao(
          onFinalizado: () => setState(() => _fase = _Fase.correcao),
        );
      case _Fase.correcao:
        return _ProvaCorrecao(
          onSalvo: (execucao, correcao) => setState(() {
            _execucaoResultado = execucao;
            _correcaoResultado = correcao;
            _fase = _Fase.resultado;
          }),
        );
      case _Fase.resultado:
        return _ProvaResultado(
          execucao: _execucaoResultado!,
          correcao: _correcaoResultado!,
        );
    }
  }
}

/// Uma faixa de questões atribuída a uma matéria no setup (ex.: 1-20
/// Português). Puramente de formulário — vira `materiaId` de cada
/// [ItemProva] gerado ao iniciar.
class _FaixaMateria {
  final de = TextEditingController();
  final ate = TextEditingController();
  String? materiaId;

  void dispose() {
    de.dispose();
    ate.dispose();
  }
}

class _ProvaSetup extends ConsumerStatefulWidget {
  final VoidCallback onIniciado;

  const _ProvaSetup({required this.onIniciado});

  @override
  ConsumerState<_ProvaSetup> createState() => _ProvaSetupState();
}

class _ProvaSetupState extends ConsumerState<_ProvaSetup> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _banca = TextEditingController();
  final _bancaFocus = FocusNode();
  final _numQuestoes = TextEditingController();
  final _duracao = TextEditingController();
  final _faixas = <_FaixaMateria>[];
  var _iniciando = false;

  @override
  void dispose() {
    _nome.dispose();
    _banca.dispose();
    _bancaFocus.dispose();
    _numQuestoes.dispose();
    _duracao.dispose();
    for (final f in _faixas) {
      f.dispose();
    }
    super.dispose();
  }

  /// Primeira faixa que cobre o número (ordem da lista) — sem faixa
  /// correspondente, a questão nasce sem matéria (bucket "não classificada"
  /// na correção).
  String? _materiaDoNumero(int numero) {
    for (final f in _faixas) {
      final de = int.tryParse(f.de.text);
      final ate = int.tryParse(f.ate.text);
      if (de == null || ate == null || f.materiaId == null) continue;
      if (numero >= de && numero <= ate) return f.materiaId;
    }
    return null;
  }

  Future<void> _iniciar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _iniciando = true);
    final n = int.tryParse(_numQuestoes.text) ?? 0;
    final duracao = int.tryParse(_duracao.text) ?? 0;
    final execucao = ExecucaoProva(
      id: const Uuid().v4(),
      nome: _nome.text.trim(),
      ambienteId: ref.read(ambienteAtivoProvider)?.id ?? Ambiente.geralId,
      // Construtor normaliza (trim, maiúsculas, apelido CESPE→CEBRASPE,
      // vazio→null) — mesma regra de RegistroHora.banca/Simulado.banca.
      banca: _banca.text,
      iniciadaEm: DateTime.now(),
      duracaoMinutos: duracao,
      itens: [
        for (var i = 1; i <= n; i++)
          ItemProva(numero: i, materiaId: _materiaDoNumero(i)),
      ],
    );
    await ref.read(execucaoProvaProvider.notifier).iniciar(execucao);
    if (!mounted) return;
    widget.onIniciado();
  }

  @override
  Widget build(BuildContext context) {
    final materias = ref
        .watch(materiasDoAmbienteProvider)
        .where((m) => !m.arquivada)
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Prova cronometrada')),
      body: ConteudoCentral(
        maxWidth: 640,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                key: const Key('prova_setup_nome'),
                controller: _nome,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome da prova *',
                  hintText: 'Ex.: SEFAZ-RN 2026 — objetiva',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 8),
              // Autocomplete com o catálogo fixo de bancas — mesma receita
              // de simulados_screen.dart/registro_form.dart, não
              // compartilhada via import de propósito (cada tela autônoma).
              Autocomplete<String>(
                textEditingController: _banca,
                focusNode: _bancaFocus,
                optionsBuilder: (TextEditingValue value) {
                  final consulta = Bancas.normalizar(value.text) ?? '';
                  if (consulta.isEmpty) return Bancas.sugestoes;
                  return Bancas.sugestoes.where((o) => o.contains(consulta));
                },
                fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                  return TextFormField(
                    key: const Key('prova_setup_banca'),
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Banca (opcional)',
                      hintText: 'Ex.: CEBRASPE, FGV...',
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('prova_setup_num_questoes'),
                      controller: _numQuestoes,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Nº de questões *',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n <= 0) ? '> 0' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: const Key('prova_setup_duracao'),
                      controller: _duracao,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duração (min) *',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        return (n == null || n <= 0) ? '> 0' : null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Faixas de questões por matéria (opcional)',
                style: TextStyle(color: VizColors.inkSecondary),
              ),
              const SizedBox(height: 4),
              for (var i = 0; i < _faixas.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _faixas[i].de,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'De'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _faixas[i].ate,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Até'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: _faixas[i].materiaId,
                          decoration: const InputDecoration(
                            labelText: 'Matéria',
                          ),
                          items: [
                            for (final m in materias)
                              DropdownMenuItem(
                                value: m.id,
                                child: Text(
                                  m.nome,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _faixas[i].materiaId = v),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remover faixa',
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            setState(() => _faixas.removeAt(i).dispose()),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Adicionar faixa'),
                  onPressed: () => setState(() => _faixas.add(_FaixaMateria())),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('prova_setup_iniciar'),
                onPressed: _iniciando ? null : _iniciar,
                icon: const Icon(Icons.play_arrow),
                label: Text(_iniciando ? 'Iniciando...' : 'Iniciar prova'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvaExecucao extends ConsumerStatefulWidget {
  final VoidCallback onFinalizado;

  const _ProvaExecucao({required this.onFinalizado});

  @override
  ConsumerState<_ProvaExecucao> createState() => _ProvaExecucaoState();
}

class _ProvaExecucaoState extends ConsumerState<_ProvaExecucao> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Redesenha a cada segundo só pra atualizar o texto do relógio — o
    // tempo em si NUNCA vem daqui, vem de ProvaService.tempoRestante
    // (relógio de parede lido a cada build), então perder um tick (app em
    // segundo plano, etc.) não desalinha nada.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _marcar(ExecucaoProva execucao, int numero, String letra) {
    // Mesma proteção do gabarito: parte do estado ATUAL, não da `execucao`
    // deste build. Toques rápidos em questões diferentes dentro do mesmo frame
    // partiriam da mesma base e o segundo apagaria a marcação do primeiro.
    ref.read(execucaoProvaProvider.notifier).mutar((atual) {
      final item = atual.itens.firstWhere((i) => i.numero == numero);
      // Tocar na MESMA letra já marcada desmarca — fica em branco de novo.
      final desmarcar = item.respostaMarcada == letra;
      return atual.comItemAtualizado(
        numero,
        (i) => i.copyWith(
          respostaMarcada: desmarcar ? null : letra,
          limparResposta: desmarcar,
        ),
      );
    });
  }

  void _finalizar(ExecucaoProva execucao) {
    ref
        .read(execucaoProvaProvider.notifier)
        .atualizar(execucao.copyWith(finalizadaEm: DateTime.now()));
    widget.onFinalizado();
  }

  @override
  Widget build(BuildContext context) {
    final execucao = ref.watch(execucaoProvaProvider);
    if (execucao == null) {
      // Defensivo: execução encerrada por fora (ex.: apagar dados) enquanto
      // esta tela ainda estava montada.
      return Scaffold(
        appBar: AppBar(title: const Text('Prova')),
        body: const Center(child: Text('Prova encerrada.')),
      );
    }

    final restante = ProvaService.tempoRestante(execucao, DateTime.now());
    final progresso = ProvaService.progresso(execucao);
    final limiarSegundos = execucao.duracaoMinutos * 60 * 0.1;
    final critico = restante.inSeconds <= limiarSegundos;

    return Scaffold(
      appBar: AppBar(title: Text(execucao.nome)),
      body: ConteudoCentral(
        maxWidth: 720,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  Text(
                    formatarCronometro(restante),
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: critico
                          ? StatusColors.critico
                          : VizColors.inkPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${progresso.respondidas}/${progresso.total} respondidas',
                    style: const TextStyle(color: VizColors.inkSecondary),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: execucao.itens.length,
                itemBuilder: (context, i) {
                  final item = execucao.itens[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          child: Text(
                            '${item.numero}',
                            style: const TextStyle(
                              color: VizColors.inkSecondary,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            children: [
                              for (final letra in const [
                                'A',
                                'B',
                                'C',
                                'D',
                                'E',
                              ])
                                ChoiceChip(
                                  key: Key('resposta_${item.numero}_$letra'),
                                  label: Text(letra),
                                  selected: item.respostaMarcada == letra,
                                  onSelected: (_) =>
                                      _marcar(execucao, item.numero, letra),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    key: const Key('prova_pausar'),
                    // "Pausar" sai da tela sem finalizar — a execução
                    // continua ativa e persistida (o relógio real da prova
                    // não para: fechar o app não pausa um concurso de
                    // verdade). "Prova em andamento — retomar" em
                    // SimuladosScreen reabre exatamente aqui.
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Pausar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: const Key('prova_finalizar'),
                    onPressed: () => _finalizar(execucao),
                    icon: const Icon(Icons.check),
                    label: const Text('Finalizar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProvaCorrecao extends ConsumerStatefulWidget {
  final void Function(ExecucaoProva execucao, CorrecaoProva correcao) onSalvo;

  const _ProvaCorrecao({required this.onSalvo});

  @override
  ConsumerState<_ProvaCorrecao> createState() => _ProvaCorrecaoState();
}

class _ProvaCorrecaoState extends ConsumerState<_ProvaCorrecao> {
  final _colar = TextEditingController();
  final _gabaritos = <int, TextEditingController>{};
  var _salvando = false;

  TextEditingController _controllerDe(ItemProva item) => _gabaritos
      .putIfAbsent(item.numero, () => TextEditingController(text: item.gabarito ?? ''));

  /// Grava o gabarito digitado no item — fire-and-forget, mesmo padrão de
  /// ExecucaoProvaController.atualizar que _marcar já usa em
  /// _ProvaExecucaoState (B12): sem isso o gabarito só existia no
  /// TextEditingController local e sumia ao fechar o app no meio da
  /// correção.
  void _persistirGabarito(ExecucaoProva execucao, int numero, String valor) {
    // `mutar` lê o estado atual do provider em vez de partir da `execucao`
    // capturada neste build: dois campos de gabarito editados dentro do mesmo
    // frame partiriam da mesma base e o segundo write apagaria o primeiro.
    ref
        .read(execucaoProvaProvider.notifier)
        .mutar(
          (atual) => atual.comItemAtualizado(
            numero,
            (i) => i.copyWith(gabarito: valor),
          ),
        );
  }

  /// Distribui a string colada (ex.: "ABCDE...") pros campos de gabarito na
  /// ordem das questões — espaços são ignorados, sobra de letras além do
  /// nº de questões é descartada. Um só `atualizar` no fim (não um write
  /// por item) persiste o lote inteiro (B12).
  void _aplicarColado(ExecucaoProva execucao) {
    final letras = _colar.text.replaceAll(RegExp(r'\s+'), '').split('');
    var atualizada = execucao;
    setState(() {
      for (var i = 0; i < execucao.itens.length && i < letras.length; i++) {
        final item = execucao.itens[i];
        final letra = letras[i].toUpperCase();
        _controllerDe(item).text = letra;
        atualizada = atualizada.comItemAtualizado(
          item.numero,
          (it) => it.copyWith(gabarito: letra),
        );
      }
    });
    ref.read(execucaoProvaProvider.notifier).atualizar(atualizada);
  }

  Future<void> _corrigirESalvar(ExecucaoProva execucao) async {
    setState(() => _salvando = true);
    try {
      final itensComGabarito = [
        for (final item in execucao.itens)
          item.copyWith(gabarito: _controllerDe(item).text),
      ];
      final execucaoFinal = execucao.copyWith(itens: itensComGabarito);
      final correcao = ProvaService.corrigir(execucaoFinal);
      final hoje = DateTime.now();

      final simulado = ProvaService.paraSimulado(
        execucaoFinal,
        correcao,
        simuladoId: execucaoFinal.id,
      );
      final questoesErradas = ProvaService.paraQuestoesErradas(
        execucaoFinal,
        correcao,
        hoje,
      );
      final registro = ProvaService.paraRegistroHora(
        execucaoFinal,
        correcao,
        id: const Uuid().v4(),
      );

      await ref.read(simuladosProvider.notifier).salvar(simulado);
      for (final q in questoesErradas) {
        await ref.read(questoesErradasProvider.notifier).salvar(q);
      }
      await ref.read(registrosProvider.notifier).salvar(registro);
      await ref.read(execucaoProvaProvider.notifier).encerrar();

      if (!mounted) return;
      widget.onSalvo(execucaoFinal, correcao);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  void dispose() {
    _colar.dispose();
    for (final c in _gabaritos.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final execucao = ref.watch(execucaoProvaProvider);
    if (execucao == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Corrigir prova')),
        body: const Center(child: Text('Prova encerrada.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Corrigir prova')),
      body: ConteudoCentral(
        maxWidth: 720,
        // Column com a lista em Expanded(ListView.builder) — mesma receita
        // de _ProvaExecucao — em vez de ListView único eager (B11): prova
        // longa não materializa centenas de TextField de uma vez só.
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cole o gabarito na ordem das questões (ex.: ABCDE...) '
                    'ou preencha campo a campo.',
                    style: TextStyle(color: VizColors.inkSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('prova_colar_gabarito'),
                          controller: _colar,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Colar gabarito',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        key: const Key('prova_aplicar_gabarito'),
                        onPressed: () => _aplicarColado(execucao),
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                // Chave estável só pra teste conseguir mirar no Scrollable
                // certo (o TextField "colar gabarito" acima também tem um
                // Scrollable interno próprio — find.byType(Scrollable)
                // ambíguo pegaria o errado).
                key: const Key('prova_correcao_lista'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: execucao.itens.length,
                itemBuilder: (context, i) {
                  final item = execucao.itens[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text('Questão ${item.numero}'),
                        ),
                        Expanded(
                          child: TextField(
                            key: Key('prova_gabarito_${item.numero}'),
                            controller: _controllerDe(item),
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Gabarito',
                            ),
                            onChanged: (v) =>
                                _persistirGabarito(execucao, item.numero, v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          child: Text(
                            item.respostaMarcada == null
                                ? 'em branco'
                                : 'marcou ${item.respostaMarcada}',
                            style: const TextStyle(
                              color: VizColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                key: const Key('prova_corrigir_salvar'),
                onPressed: _salvando ? null : () => _corrigirESalvar(execucao),
                child: Text(_salvando ? 'Salvando...' : 'Corrigir e salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1 acerto" vs "2 acertos" — 0 pluraliza igual 2+ em português ("0
/// acertos", nunca "0 acerto"). Helper único pra não espalhar ternário
/// pelas métricas do resultado (B10).
class _ProvaResultado extends ConsumerWidget {
  final ExecucaoProva execucao;
  final CorrecaoProva correcao;

  const _ProvaResultado({required this.execucao, required this.correcao});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materiasPorId = {
      for (final m in ref.watch(materiasProvider)) m.id: m,
    };
    // Item sem gabarito preenchido fica fora da apuração (ver
    // ProvaService.corrigir) — nem acerto, nem erro. CorrecaoProva não
    // expõe essa contagem pronta; é o resto depois de acertos e erros.
    final semGabarito =
        execucao.itens.length - correcao.acertos - correcao.erros;

    return Scaffold(
      appBar: AppBar(title: const Text('Resultado')),
      body: ConteudoCentral(
        maxWidth: 720,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(execucao.nome, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${plural(correcao.acertos, 'acerto', 'acertos')} · '
              '${plural(correcao.erros, 'erro', 'erros')} · '
              '${plural(correcao.embranco, 'questão em branco', 'questões em branco')} · '
              '${plural(semGabarito, 'questão sem gabarito', 'questões sem gabarito')}',
              style: const TextStyle(color: VizColors.inkSecondary),
            ),
            const SizedBox(height: 16),
            for (final r in correcao.resultados)
              Card(
                child: ListTile(
                  leading: AvatarCor(
                    slot: materiasPorId[r.materiaId]?.corSlot ?? 0,
                  ),
                  title: Text(materiasPorId[r.materiaId]?.nome ?? '—'),
                  trailing: Text(
                    '${r.acertos}/${r.questoes}'
                    '${r.taxa == null ? '' : ' · ${(r.taxa! * 100).toStringAsFixed(0)}%'}',
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('prova_concluir'),
              onPressed: () => Navigator.pop(context),
              child: const Text('Concluir'),
            ),
          ],
        ),
      ),
    );
  }
}
