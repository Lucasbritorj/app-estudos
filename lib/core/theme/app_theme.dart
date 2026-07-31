import 'package:flutter/material.dart';

/// Escala de espaçamento em grade 4/8pt — ritmo vertical previsível, fim do
/// `SizedBox(10)` ad-hoc. Um único vocabulário de vãos no app inteiro.
class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Raios de canto padronizados — antes 14/10/9/22 misturados. `lg` é o raio
/// de card (vidro Lumina); `md`/`sm` para elementos internos menores.
class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

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

  /// Canal exclusivo do streak (mesma tinta do laranja da série categórica).
  /// Não usar em decoração nem status — a chama só significa ritmo.
  static const chama = Color(0xFFD95926);
}

/// Cores de status semânticas (bom/atenção/crítico) — canal exclusivo de
/// estado, nunca decoração; sempre acompanhadas de ícone/rótulo (nunca só
/// cor). Regra Nexus: <75% crítico, 75-84% atenção, >=85% bom.
class StatusColors {
  static const bom = Color(0xFF0CA30C);
  static const atencao = Color(0xFFFAB219);

  /// Tinta de estado crítico (texto, ícone, barra) sobre os fundos escuros do
  /// app. Era #D03B3B, que dá 3,34:1 sobre `VizColors.surface` — reprova o
  /// mínimo de 4,5:1 da WCAG 2.2 AA (1.4.3) para os rótulos de 11-12px em que
  /// é usado (desempenho, prontidão, alertas, mapa). #E06A63 mede 4,91:1
  /// sobre a superfície e 5,77:1 sobre a página.
  static const critico = Color(0xFFE06A63);

  /// Vermelho de SUPERFÍCIE para ação destrutiva (fundo de botão). Precisa ser
  /// escuro o bastante para o rótulo branco em cima passar em 4,5:1 (#D03B3B
  /// dá 4,80:1) — a tinta clara de [critico] só serve como texto sobre fundo
  /// escuro, e como fundo derrubaria o contraste do rótulo para 3,26:1.
  static const criticoSuperficie = Color(0xFFD03B3B);

  /// Regra Nexus como função única (taxa 0..1) — antes reimplementada em
  /// mapa, simulados, desempenho e prontidão, com risco de limiar divergir.
  static Color porTaxa(double taxa) {
    if (taxa < 0.75) return critico;
    if (taxa < 0.85) return atencao;
    return bom;
  }
}

/// Elevação Lumina (minerada do banco Asimov, componente glass-pricing):
/// sombra em camadas progressivas em vez de uma única sombra grande —
/// profundidade realista sem BackdropFilter (custo de GPU ~zero na web).
/// Original tinha 6 camadas até 100px; 4 bastam sobre fundo escuro.
class LuminaElevation {
  static const cardEmCamadas = <BoxShadow>[
    BoxShadow(
      color: Color(0x0A000000),
      offset: Offset(0, 2.8),
      blurRadius: 2.2,
    ),
    BoxShadow(
      color: Color(0x0F000000),
      offset: Offset(0, 6.7),
      blurRadius: 5.3,
    ),
    BoxShadow(
      color: Color(0x14000000),
      offset: Offset(0, 12.5),
      blurRadius: 10,
    ),
    BoxShadow(
      color: Color(0x1F000000),
      offset: Offset(0, 22.3),
      blurRadius: 17.9,
    ),
  ];

  /// Glow de acento (glass-effect2): brilho suave da cor em volta do elemento
  /// ativo/celebrado. Usar com parcimônia — no máximo 1 por região visível,
  /// senão vira ruído e o destaque morre.
  static List<BoxShadow> glow(Color cor, {double alpha = 0.35}) => [
    BoxShadow(color: cor.withValues(alpha: alpha), blurRadius: 15),
  ];
}

/// Tokens de texto fora da TextTheme (estilos utilitários Lumina).
class LuminaText {
  /// Rótulo de seção uppercase (banco Asimov: 12px tracking widest — aqui
  /// 10px porque a densidade do app é maior que a de landing page).
  static const rotuloUppercase = TextStyle(
    color: VizColors.muted,
    fontSize: 10,
    letterSpacing: 0.8,
    fontWeight: FontWeight.w600,
  );

  /// Título de card — voz única (fonte Display, cor e peso fixos) para todo
  /// título de card do dashboard. Antes metade em inkSecondary, metade em
  /// inkPrimary com brilho desigual lado a lado.
  static const cardTitle = TextStyle(
    fontFamily: 'Display',
    color: VizColors.inkPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  );

  /// Número-herói: valor grande dos KPIs/herói. Fonte Display + dígitos
  /// tabulares (largura fixa: não "dança" ao mudar). Tamanho no call site.
  static const numeroHero = TextStyle(
    fontFamily: 'Display',
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
  );
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

  /// Segunda camada neutra (chrome de navegação): um tom abaixo do conteúdo,
  /// translúcida sobre o gradiente Lumina.
  static const chromeNav = Color(0xF2161B27);
  static const chromeSidebar = Color(0xF2121620);
  static const bordaSutil = Color(0x1FFFFFFF);
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
    // Escala tipográfica minerada do banco Asimov (lumina-video): título
    // grande = tracking negativo + linha justa; corpo = mais respiro de
    // linha; hierarquia vem de peso/tracking, não só de tamanho. Estilos
    // parciais (sem cor) — o ThemeData mescla com os defaults M3.
    // Fonte 'Display' (Space Grotesk) SÓ nos títulos — corpo/labels/dados
    // seguem no default (Roboto) com dígitos tabulares onde há número. Par
    // por eixo de contraste (geométrica × neo-grotesca), não duas sans
    // parecidas.
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontFamily: 'Display',
        letterSpacing: -1.0,
        fontWeight: FontWeight.w600,
        height: 1.05,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Display',
        letterSpacing: -0.75,
        fontWeight: FontWeight.w600,
        height: 1.05,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Display',
        letterSpacing: -0.5,
        fontWeight: FontWeight.w600,
        height: 1.1,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Display',
        letterSpacing: -0.25,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: TextStyle(height: 1.55),
      bodyMedium: TextStyle(height: 1.45),
      labelSmall: TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w600),
    ),
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
        borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
        side: BorderSide(color: Color(0x24FFFFFF)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VizColors.chromeNav,
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
