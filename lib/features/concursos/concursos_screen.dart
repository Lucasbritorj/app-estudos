import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'concursos_store.dart';
import 'cliente.dart';
import '../edital/edital_screen.dart';

class ConcursosScreen extends StatefulWidget {
  const ConcursosScreen({super.key});
  @override
  State<ConcursosScreen> createState() => _ConcursosScreenState();
}

class _ConcursosScreenState extends State<ConcursosScreen>
    with WidgetsBindingObserver {
  late final ConcursosStore store;
  Timer? timer;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    store = ConcursosStore();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(minutes: 5), (_) => refresh());
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh({bool manual = false}) async {
    if (busy ||
        (WidgetsBinding.instance.lifecycleState != null &&
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed)) {
      return;
    }
    setState(() => busy = true);
    try {
      await store.atualizar(manual: manual);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> profile() async {
    final current = Map<String, dynamic>.from(store.state['perfil'] ?? {});
    final fields = {
      'termos': 'Cargo ou área (termos separados por vírgula)',
      'escolaridade': 'Escolaridade desejada',
      'localizacao': 'Localização desejada',
      'salario': 'Remuneração mínima (R\$)',
    };
    final controllers = {
      for (final k in fields.keys)
        k: TextEditingController(text: current[k]?.toString() ?? ''),
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Meu perfil'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final e in fields.entries)
                TextField(
                  controller: controllers[e.key],
                  decoration: InputDecoration(labelText: e.value),
                ),
              const Text(
                'Dados não publicados permanecem desconhecidos e não excluem oportunidades. Confira escolaridade e localização no edital.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await store.save({
        ...store.state,
        'perfil': {
          for (final e in controllers.entries) e.key: e.value.text.trim(),
        },
      });
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Future<void> review(Map<String, dynamic> row) async {
    final old = row['anterior'];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revisar publicação'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (old is Map)
                Text(
                  'Versão anterior: ${old['titulo']}\n${old['data'] ?? 'Data não publicada'}\n\n',
                ),
              Text(
                'Versão atual: ${row['titulo']}\n${row['data'] ?? 'Data não publicada'}',
              ),
              Text(
                row['verificacao']?.toString() ??
                    'Catálogo: acompanhe o concurso para verificar seus documentos.',
              ),
              if (old is Map &&
                  old['checksum'] != null &&
                  row['checksum'] != null &&
                  old['checksum'] != row['checksum'])
                const Text(
                  'O conteúdo do documento mudou. Leia a versão atual na fonte oficial.',
                ),
              const SizedBox(height: 12),
              SelectableText(row['url'] as String),
              TextButton(
                onPressed: () => abrirFonte(row['url'] as String),
                child: const Text('Abrir fonte oficial'),
              ),
              const Text(
                'Marcar como conferida registra sua revisão. Datas, tópicos e pesos do edital devem ser ajustados na tela Edital após leitura do documento.',
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_note),
                label: const Text(
                  'Abrir edital para importar ou ajustar tópicos',
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EditalScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Depois'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Marcar conferida'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      final state = store.state;
      await store.save({
        ...state,
        'aprovadas': {
          ...Map<String, dynamic>.from(state['aprovadas'] ?? {}),
          row['id'] as String: row['versao'],
        },
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Concursos e editais'),
      actions: [
        IconButton(
          onPressed: profile,
          icon: const Icon(Icons.tune),
          tooltip: 'Meu perfil',
        ),
        IconButton(
          onPressed: busy ? null : () => refresh(manual: true),
          icon: const Icon(Icons.refresh),
          tooltip: 'Atualizar (intervalo mínimo de 5 minutos)',
        ),
      ],
    ),
    body: ValueListenableBuilder(
      valueListenable: store.box.listenable(keys: ['concursos']),
      builder: (context, _, _) {
        final state = store.state;
        final perfil = Map<String, dynamic>.from(state['perfil'] ?? {});
        final terms = (perfil['termos']?.toString() ?? '')
            .toLowerCase()
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        final salary = double.tryParse(
          (perfil['salario']?.toString() ?? '').replaceAll(',', '.'),
        );
        final tracked = List<String>.from(state['acompanhados'] ?? []);
        final rows =
            Map<String, dynamic>.from(state['publicacoes'] ?? {}).values
                .map((v) => Map<String, dynamic>.from(v as Map))
                .where(
                  (v) =>
                      tracked.contains('${v['fonte']}:${v['concurso']}') ||
                      (terms.isEmpty ||
                              terms.any(
                                (t) => v['titulo']
                                    .toString()
                                    .toLowerCase()
                                    .contains(t),
                              )) &&
                          (salary == null ||
                              v['salario'] == null ||
                              (v['salario'] as num) >= salary),
                )
                .toList()
              ..sort(
                (a, b) => (b['detectadoEm'] ?? '').toString().compareTo(
                  (a['detectadoEm'] ?? '').toString(),
                ),
              );
        final approved = Map<String, dynamic>.from(state['aprovadas'] ?? {});
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Fontes oficiais • atualização durante o uso a cada 6 horas. Catálogos podem incluir concursos em andamento. Confirme prazos no edital.',
            ),
            if (busy) const LinearProgressIndicator(),
            for (final e in Map<String, dynamic>.from(
              state['consultas'] ?? {},
            ).entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${e.key}: ${e.value['erro'] != null ? 'Desatualizado — ${e.value['erro']}' : 'Consultado em ${e.value['sucesso'] ?? 'aguardando'}'}',
                ),
              ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sem dados para este perfil. Configure termos ou atualize as fontes.',
                ),
              ),
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text(row['titulo'] as String),
                  subtitle: Text(
                    '${row['fonte']} • ${row['data'] ?? 'Data não publicada'}\n${row['salario'] == null ? 'Remuneração desconhecida' : 'Até R\$ ${row['salario']}'} • Escolaridade/localização: consultar edital\n${approved[row['id']] == row['versao']
                        ? 'Conferida'
                        : row['anterior'] != null
                        ? 'Publicação alterada'
                        : 'Nova publicação'}',
                  ),
                  isThreeLine: true,
                  onTap: () => review(row),
                  trailing: row['concurso'] == null
                      ? null
                      : IconButton(
                          tooltip:
                              tracked.contains(
                                '${row['fonte']}:${row['concurso']}',
                              )
                              ? 'Parar acompanhamento'
                              : 'Acompanhar editais deste concurso',
                          icon: Icon(
                            tracked.contains(
                                  '${row['fonte']}:${row['concurso']}',
                                )
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                          ),
                          onPressed: () async {
                            final key = '${row['fonte']}:${row['concurso']}';
                            final list = List<String>.from(
                              store.state['acompanhados'] ?? [],
                            );
                            if (list.contains(key)) {
                              list.remove(key);
                            } else {
                              list.add(key);
                            }
                            await store.save({
                              ...store.state,
                              'acompanhados': list,
                            });
                            await refresh();
                          },
                        ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
