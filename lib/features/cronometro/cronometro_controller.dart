import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../data/local/hive_boxes.dart';

enum CronometroStatus { parado, rodando, pausado }

class CronometroState {
  final CronometroStatus status;
  final Duration decorrido;

  const CronometroState({required this.status, required this.decorrido});

  static const inicial = CronometroState(
    status: CronometroStatus.parado,
    decorrido: Duration.zero,
  );

  /// Restaura o estado a partir do registro persistido. Sessão que estava
  /// rodando volta PAUSADA no último tempo salvo: não perde o estudo nem
  /// conta o tempo em que o app ficou fechado (o usuário decide retomar).
  static CronometroState restaurar(Map<String, dynamic>? raw) {
    if (raw == null) return inicial;
    final ms = (raw['elapsedMs'] as num?)?.toInt() ?? 0;
    if (ms <= 0) return inicial;
    return CronometroState(
      status: CronometroStatus.pausado,
      decorrido: Duration(milliseconds: ms),
    );
  }
}

/// Cronômetro de horas líquidas: relógio de parede (accurate mesmo com a aba
/// em segundo plano); pausas não contam. Persiste o decorrido a cada segundo
/// para sobreviver a reload/kill — o Stopwatch em memória, sozinho, perdia a
/// sessão inteira num F5.
class CronometroController extends Notifier<CronometroState> {
  static const _chave = 'atual';

  Timer? _tick;

  /// Tempo acumulado antes do segmento em curso (soma das pausas fechadas).
  Duration _acumulado = Duration.zero;

  /// Início (relógio de parede) do segmento em curso; null quando parado
  /// ou pausado.
  DateTime? _inicioSegmento;

  /// Último segundo inteiro persistido — evita escrita a cada 500ms.
  int _ultimoSegundoSalvo = -1;

  Box<Map> get _box => Hive.box<Map>(HiveBoxes.cronometro);

  @override
  CronometroState build() {
    ref.onDispose(() => _tick?.cancel());
    final raw = _box.get(_chave);
    final restaurado = CronometroState.restaurar(
      raw == null ? null : Map<String, dynamic>.from(raw),
    );
    _acumulado = restaurado.decorrido;
    return restaurado;
  }

  Duration get _decorrido => _inicioSegmento == null
      ? _acumulado
      : _acumulado + DateTime.now().difference(_inicioSegmento!);

  void iniciar() {
    _acumulado = Duration.zero;
    _inicioSegmento = DateTime.now();
    _ligarTick();
    _emitir(CronometroStatus.rodando);
  }

  void pausar() {
    _acumulado = _decorrido;
    _inicioSegmento = null;
    _tick?.cancel();
    _emitir(CronometroStatus.pausado);
  }

  void retomar() {
    _inicioSegmento = DateTime.now();
    _ligarTick();
    _emitir(CronometroStatus.rodando);
  }

  void descartar() {
    _tick?.cancel();
    _acumulado = Duration.zero;
    _inicioSegmento = null;
    _ultimoSegundoSalvo = -1;
    _box.delete(_chave);
    state = CronometroState.inicial;
  }

  void _ligarTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _emitir(CronometroStatus.rodando);
    });
  }

  void _emitir(CronometroStatus status) {
    final decorrido = _decorrido;
    state = CronometroState(status: status, decorrido: decorrido);
    _persistir(status, decorrido);
  }

  void _persistir(CronometroStatus status, Duration decorrido) {
    // Grava no máximo uma vez por segundo enquanto roda; sempre em pausa.
    final segundo = decorrido.inSeconds;
    if (status == CronometroStatus.rodando && segundo == _ultimoSegundoSalvo) {
      return;
    }
    _ultimoSegundoSalvo = segundo;
    _box.put(_chave, {
      'elapsedMs': decorrido.inMilliseconds,
      'rodando': status == CronometroStatus.rodando,
    });
  }
}

final cronometroProvider =
    NotifierProvider<CronometroController, CronometroState>(
      CronometroController.new,
    );

typedef PreSelecaoCronometro = ({String? materiaId, String? topicoId});

/// Payload do deep-link "Estudar agora" (Missão de hoje → Cronômetro):
/// a tela do cronômetro consome uma vez e limpa.
class PreSelecaoCronometroNotifier extends Notifier<PreSelecaoCronometro?> {
  @override
  PreSelecaoCronometro? build() => null;

  void definir({String? materiaId, String? topicoId}) =>
      state = (materiaId: materiaId, topicoId: topicoId);

  void consumir() => state = null;
}

final preSelecaoCronometroProvider =
    NotifierProvider<PreSelecaoCronometroNotifier, PreSelecaoCronometro?>(
      PreSelecaoCronometroNotifier.new,
    );
