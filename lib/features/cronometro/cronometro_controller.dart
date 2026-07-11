import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CronometroStatus { parado, rodando, pausado }

class CronometroState {
  final CronometroStatus status;
  final Duration decorrido;

  const CronometroState({required this.status, required this.decorrido});

  static const inicial =
      CronometroState(status: CronometroStatus.parado, decorrido: Duration.zero);
}

/// Cronômetro de horas líquidas: Stopwatch é a fonte de verdade (pausas não
/// contam); o Timer só re-renderiza a UI a cada 500ms.
class CronometroController extends Notifier<CronometroState> {
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _tick;

  @override
  CronometroState build() {
    ref.onDispose(() => _tick?.cancel());
    return CronometroState.inicial;
  }

  void iniciar() {
    _stopwatch
      ..reset()
      ..start();
    _ligarTick();
    _emitir(CronometroStatus.rodando);
  }

  void pausar() {
    _stopwatch.stop();
    _tick?.cancel();
    _emitir(CronometroStatus.pausado);
  }

  void retomar() {
    _stopwatch.start();
    _ligarTick();
    _emitir(CronometroStatus.rodando);
  }

  void descartar() {
    _stopwatch
      ..stop()
      ..reset();
    _tick?.cancel();
    state = CronometroState.inicial;
  }

  void _ligarTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _emitir(CronometroStatus.rodando);
    });
  }

  void _emitir(CronometroStatus status) {
    state = CronometroState(status: status, decorrido: _stopwatch.elapsed);
  }
}

final cronometroProvider =
    NotifierProvider<CronometroController, CronometroState>(
        CronometroController.new);
