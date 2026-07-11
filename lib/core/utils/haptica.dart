import 'package:flutter/services.dart';

/// Haptic feedback centralizado — best-effort: na web/desktop os canais
/// podem não vibrar, e tudo segue funcionando sem erro.
class Haptica {
  /// Confirmação leve (registro salvo, item concluído).
  static void leve() => HapticFeedback.lightImpact();

  /// Celebração (meta batida, aula concluída).
  static void celebrar() => HapticFeedback.mediumImpact();

  /// Troca de seleção (ambiente, abas, segmentos).
  static void selecao() => HapticFeedback.selectionClick();
}
