import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app.dart';
import '../../data/repositories/repositorios.dart';
import '../../data/repositories/planejamento_repositorio.dart';
import '../../domain/plano_diario_service.dart';
import '../../domain/dominio_service.dart';
import '../cronometro/cronometro_controller.dart';
import 'plano_diario_repositorio.dart';

class PlanoDiarioScreen extends ConsumerStatefulWidget {
  const PlanoDiarioScreen({super.key});
  @override
  ConsumerState<PlanoDiarioScreen> createState() => _PlanoDiarioScreenState();
}

class _PlanoDiarioScreenState extends ConsumerState<PlanoDiarioScreen> {
  Map<int, int> dias = {};
  Map<String, int> excecoes = {};
  Map<String, String> comuns = {};
  String? principal;
  Set<String> secundarios = {};
  int percentual = 80;
  PropostaDiaria? proposta;
  bool ocupado = false;
  @override
  void initState() {
    super.initState();
    final salvo = ref.read(planoDiarioProvider);
    dias = salvo['dias'] == null
        ? {...ref.read(planejamentoProvider)}
        : (salvo['dias'] as Map).map(
            (k, v) => MapEntry(int.parse('$k'), (v as num).toInt()),
          );
    excecoes = (salvo['excecoes'] as Map? ?? {}).map(
      (k, v) => MapEntry('$k', (v as num).toInt()),
    );
    comuns = (salvo['comuns'] as Map? ?? {}).map(
      (k, v) => MapEntry('$k', '$v'),
    );
    principal = salvo['principal'] as String?;
    secundarios = Set<String>.from(salvo['secundarios'] as List? ?? []);
    percentual = (salvo['percentual'] as num?)?.toInt() ?? 80;
  }

  Map<String, dynamic> get config => {
    'dias': dias.map((k, v) => MapEntry('$k', v)),
    'excecoes': excecoes,
    'comuns': comuns,
    'principal': principal,
    'secundarios': secundarios.toList(),
    'percentual': percentual,
  };
  Future<void> executar(Future<void> Function() fn) async {
    setState(() => ocupado = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ambientes = ref
        .watch(ambientesProvider)
        .where((a) => !a.arquivado)
        .toList();
    final materias = ref.watch(materiasProvider);
    final registros = ref.watch(registrosProvider);
    final salvo = ref.watch(planoDiarioProvider);
    final aceitos = (salvo['blocos'] as List? ?? [])
        .map((j) => BlocoDiario.fromJson(j as Map))
        .toList();
    final vinculos = Map<String, dynamic>.from(salvo['vinculos'] as Map? ?? {});
    final blocos = proposta?.blocos ?? aceitos;
    final hoje = DateTime.now();
    final futuros = blocos
        .where(
          (b) => !b.dia.isBefore(DateTime(hoje.year, hoje.month, hoje.day)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Plano pessoal')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Uma disponibilidade para todos os concursos. Alterações geram uma proposta; somente aceitar substitui o plano futuro. Dias com sessões associadas são preservados.',
          ),
          DropdownButtonFormField<String>(
            initialValue: ambientes.any((a) => a.id == principal)
                ? principal
                : null,
            decoration: const InputDecoration(labelText: 'Concurso principal'),
            items: ambientes
                .map((a) => DropdownMenuItem(value: a.id, child: Text(a.nome)))
                .toList(),
            onChanged: (v) => setState(() {
              principal = v;
              secundarios.remove(v);
              proposta = null;
            }),
          ),
          for (final a in ambientes.where((a) => a.id != principal))
            CheckboxListTile(
              title: Text('${a.nome} · secundário'),
              value: secundarios.contains(a.id),
              onChanged: (v) => setState(() {
                v == true ? secundarios.add(a.id) : secundarios.remove(a.id);
                proposta = null;
              }),
            ),
          Text('Principal: $percentual% · secundários: ${100 - percentual}%'),
          Slider(
            value: percentual.toDouble(),
            min: 10,
            max: 90,
            divisions: 8,
            onChanged: (v) => setState(() {
              percentual = v.round();
              proposta = null;
            }),
          ),
          const Text('Minutos disponíveis por dia (0 = indisponível)'),
          for (var d = 1; d <= 7; d++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TextFormField(
                initialValue: '${dias[d] ?? 0}',
                decoration: InputDecoration(
                  labelText: [
                    'Segunda',
                    'Terça',
                    'Quarta',
                    'Quinta',
                    'Sexta',
                    'Sábado',
                    'Domingo',
                  ][d - 1],
                ),
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() {
                  dias[d] = (int.tryParse(v) ?? 0).clamp(0, 960);
                  proposta = null;
                }),
              ),
            ),
          TextButton.icon(
            icon: const Icon(Icons.event_busy),
            label: const Text('Adicionar exceção de calendário'),
            onPressed: () async {
              final data = await showDatePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
                initialDate: DateTime.now(),
              );
              if (data == null || !context.mounted) return;
              final c = TextEditingController(text: '0');
              final minutos = await showDialog<int>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('Minutos em ${diaPlano(data)}'),
                  content: TextField(
                    controller: c,
                    keyboardType: TextInputType.number,
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        ctx,
                        (int.tryParse(c.text) ?? 0).clamp(0, 960),
                      ),
                      child: const Text('Definir'),
                    ),
                  ],
                ),
              );
              c.dispose();
              if (minutos != null) {
                setState(() {
                  excecoes[diaPlano(data)] = minutos;
                  proposta = null;
                });
              }
            },
          ),
          for (final e in excecoes.entries)
            ListTile(
              title: Text('${e.key}: ${e.value} min'),
              trailing: IconButton(
                tooltip: 'Remover exceção',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  excecoes.remove(e.key);
                  proposta = null;
                }),
              ),
            ),
          ExpansionTile(
            title: const Text('Conteúdos comuns (associação explícita)'),
            children: [
              const Text(
                'Associe matérias equivalentes entre concursos. A reserva reduz a necessidade dos dois alvos; registros reais permanecem na matéria estudada.',
              ),
              for (final m in materias.where(
                (m) =>
                    !m.arquivada &&
                    (m.ambienteId == principal ||
                        secundarios.contains(m.ambienteId)),
              ))
                DropdownButtonFormField<String>(
                  initialValue:
                      materias.any(
                        (n) =>
                            n.id == comuns[m.id] &&
                            n.ambienteId != m.ambienteId,
                      )
                      ? comuns[m.id]
                      : null,
                  decoration: InputDecoration(labelText: m.nome),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text('Sem associação'),
                    ),
                    ...materias
                        .where(
                          (n) =>
                              !n.arquivada &&
                              n.ambienteId != m.ambienteId &&
                              (n.ambienteId == principal ||
                                  secundarios.contains(n.ambienteId)),
                        )
                        .map(
                          (n) => DropdownMenuItem(
                            value: n.id,
                            child: Text(n.nome),
                          ),
                        ),
                  ],
                  onChanged: (v) => setState(() {
                    if (v == null || v.isEmpty) {
                      comuns.remove(m.id);
                    } else {
                      comuns[m.id] = v;
                    }
                    proposta = null;
                  }),
                ),
            ],
          ),
          FilledButton(
            onPressed: principal == null || ocupado
                ? null
                : () => setState(() {
                    proposta = PlanoDiarioService.gerar(
                      hoje: hoje,
                      dias: dias,
                      excecoes: excecoes,
                      principal: principal!,
                      secundarios: secundarios.toList(),
                      percentualPrincipal: percentual,
                      ambientes: ambientes,
                      materias: materias,
                      revisoes: ref.read(revisoesProvider),
                      feito: {
                        for (final m in materias)
                          m.id: registros
                              .where((r) => r.materiaId == m.id)
                              .fold(0, (s, r) => s + r.minutos),
                      },
                      dominio:
                          DominioService.dominioPorMateria(
                            registros,
                            materias.map((m) => m.id),
                            referencia: hoje,
                          ).map(
                            (id, medicao) =>
                                MapEntry(id, medicao?.dominio ?? 0.5),
                          ),
                      comuns: comuns,
                    );
                  }),
            child: const Text('Gerar proposta'),
          ),
          if (proposta != null)
            FilledButton.tonal(
              onPressed: ocupado
                  ? null
                  : () => executar(() async {
                      await ref
                          .read(planoDiarioProvider.notifier)
                          .aceitar(config, proposta!, hoje);
                      if (mounted) setState(() => proposta = null);
                    }),
              child: const Text('Aceitar plano futuro'),
            ),
          for (final aviso
              in proposta?.avisos ??
                  List<String>.from(salvo['avisos'] as List? ?? []))
            Padding(padding: const EdgeInsets.all(8), child: Text(aviso)),
          if (futuros.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sem blocos futuros. Configure disponibilidade e concursos para gerar uma proposta.',
              ),
            ),
          for (final b in futuros.take(150))
            Builder(
              builder: (context) {
                final ms = materias.where((m) => m.id == b.materiaId);
                final nome = ms.isEmpty
                    ? 'Matéria indisponível'
                    : ms.first.nome;
                final vinculados = registros.where(
                  (r) => r.id == vinculos[b.id],
                );
                return Card(
                  child: ListTile(
                    title: Text(
                      '${diaPlano(b.dia)} · $nome · ${b.minutos} min',
                    ),
                    subtitle: Text(
                      '${b.motivo}${vinculados.isEmpty ? '' : '\nSessão real: ${vinculados.first.minutos} min'}',
                    ),
                    trailing: proposta != null
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (acao) async {
                              if (acao == 'iniciar') {
                                if (ref.read(cronometroProvider).status !=
                                    CronometroStatus.parado) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Finalize a sessão atual antes de iniciar outro bloco.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                ref
                                    .read(preSelecaoCronometroProvider.notifier)
                                    .definir(materiaId: b.materiaId);
                                ref.read(cronometroProvider.notifier).iniciar();
                                ref
                                    .read(abaProvider.notifier)
                                    .ir(Abas.cronometro);
                                Navigator.pop(context);
                              } else {
                                final disponiveis = registros
                                    .where(
                                      (r) =>
                                          r.materiaId == b.materiaId &&
                                          diaPlano(r.data) == diaPlano(b.dia) &&
                                          !vinculos.values.contains(r.id),
                                    )
                                    .toList();
                                final id = await showDialog<String>(
                                  context: context,
                                  builder: (ctx) => SimpleDialog(
                                    title: const Text('Associar sessão real'),
                                    children: [
                                      if (disponiveis.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Text(
                                            'Nenhuma sessão livre desta matéria e dia. Salve o estudo antes de associar.',
                                          ),
                                        ),
                                      for (final r in disponiveis)
                                        SimpleDialogOption(
                                          onPressed: () =>
                                              Navigator.pop(ctx, r.id),
                                          child: Text(
                                            '${r.minutos} min · ${r.tarefa}',
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                                if (id != null) {
                                  await executar(
                                    () => ref
                                        .read(planoDiarioProvider.notifier)
                                        .vincular(b.id, id),
                                  );
                                }
                              }
                            },
                            itemBuilder: (_) => [
                              if (ms.isNotEmpty)
                                const PopupMenuItem(
                                  value: 'iniciar',
                                  child: Text('Iniciar estudo'),
                                ),
                              if (vinculados.isEmpty)
                                const PopupMenuItem(
                                  value: 'associar',
                                  child: Text('Associar sessão salva'),
                                ),
                            ],
                          ),
                  ),
                );
              },
            ),
          if (futuros.length > 150)
            Text('Exibindo os primeiros 150 de ${futuros.length} blocos.'),
        ],
      ),
    );
  }
}
