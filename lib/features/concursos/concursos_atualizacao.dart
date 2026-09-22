import 'dart:async';
import 'package:flutter/material.dart';
import 'concursos_store.dart';

/// Consulta durante uso ativo da PWA; TTL e exclusão mútua ficam no store.
/// Não solicita notificações, não executa em background e não altera edital.
class ConcursosAtualizacao extends StatefulWidget {
  const ConcursosAtualizacao({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;
  @override
  State<ConcursosAtualizacao> createState() => _ConcursosAtualizacaoState();
}

class _ConcursosAtualizacaoState extends State<ConcursosAtualizacao>
    with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _atualizar());
    _timer = Timer.periodic(const Duration(hours: 6), (_) => _atualizar());
  }

  Future<void> _atualizar() async {
    if (!mounted || !widget.enabled) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    try {
      await ConcursosStore().atualizar();
    } catch (e) {
      // Erros de fonte já são persistidos pelo store; este é erro local do Hive.
      debugPrint('Falha no armazenamento da consulta de concursos: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _atualizar();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
