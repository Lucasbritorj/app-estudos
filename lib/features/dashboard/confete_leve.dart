import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/haptica.dart';

/// Confete leve: overlay curto (1,6s) desenhado por CustomPainter, sem
/// dependência externa. Cada [chave] celebra UMA vez por execução do app —
/// bater a meta é celebrado no momento, não a cada rebuild.
class ConfeteLeve extends StatefulWidget {
  final Widget child;

  /// Quando true (e a [chave] ainda não celebrou), dispara a animação.
  final bool disparar;

  /// Identidade da conquista (ex.: 'semana-2026-07-06').
  final String chave;

  const ConfeteLeve({
    super.key,
    required this.child,
    required this.disparar,
    required this.chave,
  });

  /// Chaves já celebradas nesta execução (efêmero de propósito).
  static final celebradas = <String>{};

  @override
  State<ConfeteLeve> createState() => _ConfeteLeveState();
}

class _ConfeteLeveState extends State<ConfeteLeve>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _tentarDisparar();
  }

  @override
  void didUpdateWidget(covariant ConfeteLeve anterior) {
    super.didUpdateWidget(anterior);
    _tentarDisparar();
  }

  void _tentarDisparar() {
    if (widget.disparar && ConfeteLeve.celebradas.add(widget.chave)) {
      Haptica.celebrar();
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _controller.isAnimating
                  ? CustomPaint(painter: _ConfetePainter(_controller.value))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfetePainter extends CustomPainter {
  final double t;

  _ConfetePainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Semente fixa: mesmo desenho em todo disparo (determinístico).
    final sorteio = Random(7);
    final tinta = Paint();
    for (var i = 0; i < 24; i++) {
      final x = sorteio.nextDouble();
      final atraso = sorteio.nextDouble() * 0.3;
      final giro = sorteio.nextDouble() * pi;
      final progresso = ((t - atraso) / (1 - atraso)).clamp(0.0, 1.0);
      if (progresso == 0) continue;

      tinta.color = seriesColors[i % seriesColors.length]
          .withValues(alpha: 0.9 * (1 - progresso));
      canvas.save();
      canvas.translate(
          x * size.width, progresso * (size.height + 20) - 10);
      canvas.rotate(giro + progresso * 3 * (i.isEven ? 1 : -1));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(-3, -2, 6, 4), const Radius.circular(1)),
        tinta,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfetePainter anterior) => anterior.t != t;
}
