import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import '../../data/local/hive_boxes.dart';
import '../../data/models/revisao.dart';
import '../../data/repositories/repositorios.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import 'notificacao_browser_stub.dart'
    if (dart.library.js_interop) 'notificacao_browser_web.dart'
    as browser;

List<Revisao> revisoesParaAvisar(
  List<Revisao> revisoes,
  DateTime agora,
  int hora,
) => revisoes
    .where(
      (r) =>
          !r.feita &&
          !DateTime(
            r.dataAgendada.year,
            r.dataAgendada.month,
            r.dataAgendada.day,
            hora,
          ).isAfter(agora),
    )
    .toList();

/// Aviso persistente dentro do aplicativo. A notificação do sistema é opcional
/// e só é emitida com a PWA aberta, uma vez por revisão/dia.
class AvisosRevisoes extends ConsumerStatefulWidget {
  const AvisosRevisoes({
    super.key,
    required this.child,
    required this.abrirRevisoes,
  });
  final Widget child;
  final VoidCallback abrirRevisoes;
  @override
  ConsumerState<AvisosRevisoes> createState() => _AvisosRevisoesState();
}

class _AvisosRevisoesState extends ConsumerState<AvisosRevisoes>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _ativo = true;
  bool _verificando = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _verificar());
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificar());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _ativo = state == AppLifecycleState.resumed;
    if (_ativo) _verificar();
  }

  Future<void> _verificar() async {
    if (!mounted || !_ativo || _verificando || !kIsWeb) return;
    _verificando = true;
    try {
      final agora = DateTime.now();
      final dia = '${agora.year}-${agora.month}-${agora.day}';
      final box = Hive.box<Map>(HiveBoxes.config);
      final guardado = box.get('avisosRevisoes');
      final ids = guardado?['dia'] == dia
          ? Set<String>.from(guardado?['ids'] as List? ?? [])
          : <String>{};
      final pendentes = revisoesParaAvisar(
        ref.read(revisoesProvider),
        agora,
        ref.read(configuracoesProvider).horaNotificacao,
      );
      final novas = pendentes.where((r) => !ids.contains(r.id)).toList();
      if (novas.isNotEmpty &&
          browser.mostrar(
            'Revisões pendentes',
            '${novas.length} revisões aguardam você. Abra a tela Revisões.',
          )) {
        await box.put('avisosRevisoes', {
          'dia': dia,
          'ids': {...ids, ...novas.map((r) => r.id)}.toList(),
        });
      }
      if (mounted) setState(() {});
    } finally {
      _verificando = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendentes = revisoesParaAvisar(
      ref.watch(revisoesProvider),
      DateTime.now(),
      ref.watch(configuracoesProvider).horaNotificacao,
    );
    if (!kIsWeb || pendentes.isEmpty) return widget.child;
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text('${pendentes.length} revisões pendentes'),
                TextButton(
                  onPressed: widget.abrirRevisoes,
                  child: const Text('Revisar'),
                ),
                TextButton(
                  onPressed: () async {
                    final permitido = await browser.pedirPermissao();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          permitido
                              ? 'Avisos ativos enquanto o aplicativo estiver aberto.'
                              : 'Notificação indisponível ou negada. Os avisos continuam aqui.',
                        ),
                      ),
                    );
                    if (permitido) await _verificar();
                  },
                  child: const Text('Ativar avisos'),
                ),
              ],
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
