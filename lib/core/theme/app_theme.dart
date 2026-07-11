import 'package:flutter/material.dart';

/// Paleta categórica validada (modo escuro) — ordem fixa é o mecanismo de
/// segurança para daltonismo; nunca reordenar nem ciclar.
const seriesColors = <Color>[
  Color(0xFF3987E5), // blue
  Color(0xFF199E70), // aqua
  Color(0xFFC98500), // yellow
  Color(0xFF008300), // green
  Color(0xFF9085E9), // violet
  Color(0xFFE66767), // red
  Color(0xFFD55181), // magenta
  Color(0xFFD95926), // orange
];

Color corDaSerie(int slot) => seriesColors[slot % seriesColors.length];

/// Acentos Lumina: grafite de fundo, dourado champagne para conquistas,
/// safira para foco/progresso. Dourado NUNCA substitui o amarelo de status
/// (atenção) — são canais semânticos diferentes.
class LuminaColors {
  static const grafite = Color(0xFF0F1115);
  static const ouro = Color(0xFFD4AF37);
  static const safira = Color(0xFF0F52BA);

  /// Safira legível sobre grafite (a #0F52BA pura some no escuro).
  static const safiraClara = Color(0xFF3D7BD9);
}

/// Chrome do gráfico (superfícies e tintas do modo escuro).
/// Superfícies mais claras que o fundo de propósito — feedback do Lucas:
/// a primeira versão ficou "fúnebre" (tudo no mesmo preto).
class VizColors {
  static const surface = Color(0xFF1B2130);
  static const page = LuminaColors.grafite;
  static const inkPrimary = Color(0xFFFFFFFF);
  static const inkSecondary = Color(0xFFC9CDD6);
  static const muted = Color(0xFF98A0AE);
  static const gridline = Color(0xFF2C3345);
  static const baseline = Color(0xFF3A4256);
}

ThemeData buildDarkTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: LuminaColors.safira,
    brightness: Brightness.dark,
    surface: VizColors.surface,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // Transparente: o gradiente Lumina é pintado atrás do Navigator
    // (LuminaBackground no builder do MaterialApp).
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      // Vidro: superfície translúcida + borda de 1px sobre o gradiente.
      color: Color(0xD91B2130),
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: Color(0x24FFFFFF)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: const Color(0xF2161B27),
      indicatorColor: LuminaColors.safiraClara.withValues(alpha: 0.28),
    ),
  );
}

/// Centraliza conteúdo em telas largas (web/desktop): sem isso o layout
/// mobile estica em 1900px e vira "quadro enorme vazio" (feedback real).
class ConteudoCentral extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ConteudoCentral({super.key, required this.child, this.maxWidth = 860});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

/// Fundo Lumina: grafite com brilhos radiais discretos (safira no topo,
/// dourado no rodapé). Sem BackdropFilter — o efeito de vidro vem da
/// translucidez dos cards sobre este gradiente, custo de GPU ~zero na web.
class LuminaBackground extends StatelessWidget {
  final Widget child;

  const LuminaBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: LuminaColors.grafite),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -100,
            child: _Brilho(cor: LuminaColors.safiraClara, alpha: 0.20),
          ),
          Positioned(
            bottom: -160,
            right: -120,
            child: _Brilho(cor: LuminaColors.ouro, alpha: 0.11),
          ),
          child,
        ],
      ),
    );
  }
}

class _Brilho extends StatelessWidget {
  final Color cor;
  final double alpha;

  const _Brilho({required this.cor, required this.alpha});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 420,
        height: 420,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              cor.withValues(alpha: alpha),
              cor.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
