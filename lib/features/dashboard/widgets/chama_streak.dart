import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A chama do streak — o único "personagem" do app. Estável quando o ritmo
/// está protegido; tremula (opacidade pulsando) quando hoje ainda não teve
/// sessão e o streak está em risco. Urgência sem alarme.
class ChamaAnimada extends StatefulWidget {
  final bool emRisco;
  final double size;

  const ChamaAnimada({super.key, required this.emRisco, this.size = 13});

  @override
  State<ChamaAnimada> createState() => _ChamaAnimadaState();
}

class _ChamaAnimadaState extends State<ChamaAnimada>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _sincronizar();
  }

  @override
  void didUpdateWidget(covariant ChamaAnimada anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.emRisco != widget.emRisco) _sincronizar();
  }

  void _sincronizar() {
    if (widget.emRisco) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ícone puro (Icons.local_fire_department) não fala nada sozinho — quando
    // este widget aparece fora do tile de Streak (que já tem seu próprio
    // rótulo composto), o leitor de tela precisa de um nome próprio para a
    // chama e o estado que ela representa.
    return Semantics(
      container: true,
      label: widget.emRisco
          ? 'Chama do streak: hoje em risco, estude para não perder a sequência'
          : 'Chama do streak: sequência protegida',
      child: FadeTransition(
        opacity: Tween(
          begin: 1.0,
          end: 0.35,
        ).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
        ),
        child: Icon(
          Icons.local_fire_department,
          size: widget.size,
          color: LuminaColors.chama,
        ),
      ),
    );
  }
}
