import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Bolinha de cor da entidade (matéria/ambiente) — o marcador visual padrão
/// do app. Antes reimplementado como CircleAvatar em 12 telas; o raio varia
/// por contexto (10 = leading de lista, 5-8 = legenda/inline).
class AvatarCor extends StatelessWidget {
  final int slot;
  final double raio;

  const AvatarCor({super.key, required this.slot, this.raio = 10});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(radius: raio, backgroundColor: corDaSerie(slot));
  }
}
