import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/haptica.dart';
import 'data/repositories/configuracoes_repositorio.dart';
import 'features/ambientes/ambientes_screen.dart';
import 'features/busca/busca_screen.dart';
import 'features/caderno/caderno_screen.dart';
import 'features/configuracoes/configuracoes_screen.dart';
import 'features/cronometro/cronometro_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/edital/edital_screen.dart';
import 'features/exportar/exportar_screen.dart';
import 'features/leituras/leituras_screen.dart';
import 'features/mais/mais_screen.dart';
import 'features/mapa/mapa_estudos_screen.dart';
import 'features/materias/materias_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/planejamento/planejamento_screen.dart';
import 'features/resumos/resumos_screen.dart';
import 'features/revisoes/revisoes_screen.dart';
import 'features/simulados/simulados_screen.dart';

/// Aba ativa da navegação — em provider para o dashboard poder navegar
/// (tiles clicáveis: Hoje → Cronômetro, Revisões pendentes → Revisões...).
class AbaNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void ir(int aba) {
    Haptica.selecao();
    state = aba;
  }
}

final abaProvider = NotifierProvider<AbaNotifier, int>(AbaNotifier.new);

/// Índices das abas — usar constantes, nunca número mágico nos onTap.
class Abas {
  static const dashboard = 0;
  static const cronometro = 1;
  static const materias = 2;
  static const revisoes = 3;
  static const mais = 4;
}

class AppEstudos extends StatelessWidget {
  const AppEstudos({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meu Caminho Aprovado',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      // App é pt-BR, mas os widgets do Material falavam inglês (U-12): sem os
      // delegates, showDatePicker/showTimePicker renderizam "OK/Cancel/Select
      // date" e os leitores de tela anunciam em inglês.
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Gradiente Lumina atrás do Navigator inteiro: scaffolds transparentes
      // deixam o vidro dos cards aparecer em qualquer rota.
      builder: (context, child) =>
          LuminaBackground(child: child ?? const SizedBox.shrink()),
      home: const _HomeShell(),
    );
  }
}

/// Largura mínima para trocar bottom bar por menu lateral fixo.
const _larguraSidebar = 1080.0;

class _HomeShell extends ConsumerWidget {
  const _HomeShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tour de primeira execução antes de qualquer aba — mostrado uma vez
    // (flag persistida); "Pular"/"Começar" liberam o app.
    final onboardingConcluido = ref.watch(
      configuracoesProvider.select((c) => c.onboardingConcluido),
    );
    if (!onboardingConcluido) {
      return const OnboardingScreen();
    }

    final aba = ref.watch(abaProvider);
    final conteudo = IndexedStack(
      index: aba,
      children: const [
        DashboardScreen(),
        CronometroScreen(),
        MateriasScreen(),
        RevisoesScreen(),
        MaisScreen(),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final larga = constraints.maxWidth >= _larguraSidebar;
        if (larga) {
          // Desktop/web largo: menu vertical à esquerda (o "Mais" vira a
          // seção Ferramentas); sem bottom bar.
          return Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Sidebar(),
                Expanded(child: conteudo),
              ],
            ),
          );
        }
        return Scaffold(
          body: conteudo,
          bottomNavigationBar: NavigationBar(
            selectedIndex: aba,
            onDestinationSelected: (i) => ref.read(abaProvider.notifier).ir(i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.timer_outlined),
                selectedIcon: Icon(Icons.timer),
                label: 'Cronômetro',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_books_outlined),
                selectedIcon: Icon(Icons.library_books),
                label: 'Matérias',
              ),
              NavigationDestination(
                icon: Icon(Icons.event_repeat_outlined),
                selectedIcon: Icon(Icons.event_repeat),
                label: 'Revisões',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more_horiz),
                label: 'Mais',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Menu lateral fixo (tela larga): abas principais + ferramentas do "Mais".
/// Segunda camada neutra, um tom abaixo do conteúdo — padrão de produto.
/// Colapsável (só-ícones, 72px): estado persiste em Configuracoes, sobrevive
/// a reabertura do app.
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  static const _larguraExpandida = 240.0;
  static const _larguraColapsada = 72.0;

  /// Limiar de conteúdo, a meio caminho entre as duas larguras-alvo.
  static const _larguraMeioTermo =
      (_larguraExpandida + _larguraColapsada) / 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aba = ref.watch(abaProvider);
    final config = ref.watch(configuracoesProvider);
    final colapsada = config.sidebarColapsada;

    void abrir(Widget tela) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    }

    void alternarColapso() {
      Haptica.selecao();
      ref
          .read(configuracoesProvider.notifier)
          .salvar(config.copyWith(sidebarColapsada: !colapsada));
    }

    return AnimatedContainer(
      key: const Key('app-sidebar'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: colapsada ? _larguraColapsada : _larguraExpandida,
      decoration: const BoxDecoration(
        color: VizColors.chromeSidebar,
        border: Border(right: BorderSide(color: VizColors.bordaSutil)),
      ),
      // O CONTEÚDO segue a largura REAL (constraints), não o bool
      // `colapsada` cru: o Riverpod muda o bool instantaneamente, mas o
      // AnimatedContainer ainda leva 180ms pra terminar a largura. Se o
      // conteúdo seguisse o bool, o Row expandido (ícone+texto) tentaria
      // caber num container ainda estreito no meio da transição e
      // estourava (RenderFlex overflow). Seguindo a largura real, a troca
      // de modo só acontece quando já sobra espaço pros dois lados.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final estreita = constraints.maxWidth < _larguraMeioTermo;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: estreita
                    ? Column(
                        children: [
                          const _LogoIcone(),
                          const SizedBox(height: 10),
                          Tooltip(
                            message: 'Expandir menu',
                            child: IconButton(
                              icon: const Icon(
                                Icons.menu,
                                size: 18,
                                color: VizColors.inkSecondary,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              onPressed: alternarColapso,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          const _LogoIcone(),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Meu Caminho\nAprovado',
                              style: TextStyle(
                                color: VizColors.inkPrimary,
                                fontSize: 13,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Colapsar menu',
                            child: IconButton(
                              icon: const Icon(
                                Icons.menu_open,
                                size: 18,
                                color: VizColors.inkSecondary,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              visualDensity: VisualDensity.compact,
                              onPressed: alternarColapso,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 22),
              if (!estreita) const _RotuloSecao('Menu'),
              _ItemSidebar(
                icone: Icons.insights_outlined,
                iconeAtivo: Icons.insights,
                rotulo: 'Dashboard',
                ativo: aba == Abas.dashboard,
                colapsado: estreita,
                onTap: () =>
                    ref.read(abaProvider.notifier).ir(Abas.dashboard),
              ),
              _ItemSidebar(
                icone: Icons.timer_outlined,
                iconeAtivo: Icons.timer,
                rotulo: 'Cronômetro',
                ativo: aba == Abas.cronometro,
                colapsado: estreita,
                onTap: () =>
                    ref.read(abaProvider.notifier).ir(Abas.cronometro),
              ),
              _ItemSidebar(
                icone: Icons.library_books_outlined,
                iconeAtivo: Icons.library_books,
                rotulo: 'Matérias',
                ativo: aba == Abas.materias,
                colapsado: estreita,
                onTap: () =>
                    ref.read(abaProvider.notifier).ir(Abas.materias),
              ),
              _ItemSidebar(
                icone: Icons.event_repeat_outlined,
                iconeAtivo: Icons.event_repeat,
                rotulo: 'Revisões',
                ativo: aba == Abas.revisoes,
                colapsado: estreita,
                onTap: () =>
                    ref.read(abaProvider.notifier).ir(Abas.revisoes),
              ),
              const SizedBox(height: 18),
              if (!estreita) const _RotuloSecao('Ferramentas'),
              _ItemSidebar(
                icone: Icons.search,
                rotulo: 'Buscar',
                colapsado: estreita,
                onTap: () => abrir(const BuscaScreen()),
              ),
              _ItemSidebar(
                icone: Icons.account_tree_outlined,
                rotulo: 'Mapa de Estudos',
                colapsado: estreita,
                onTap: () => abrir(const MapaEstudosScreen()),
              ),
              _ItemSidebar(
                icone: Icons.checklist_rtl,
                rotulo: 'Edital verticalizado',
                colapsado: estreita,
                onTap: () => abrir(const EditalScreen()),
              ),
              _ItemSidebar(
                icone: Icons.quiz_outlined,
                rotulo: 'Caderno de Erros',
                colapsado: estreita,
                onTap: () => abrir(const CadernoScreen()),
              ),
              _ItemSidebar(
                icone: Icons.calendar_month_outlined,
                rotulo: 'Planejamento',
                colapsado: estreita,
                onTap: () => abrir(const PlanejamentoScreen()),
              ),
              _ItemSidebar(
                icone: Icons.fact_check_outlined,
                rotulo: 'Simulados & Provas',
                colapsado: estreita,
                onTap: () => abrir(const SimuladosScreen()),
              ),
              _ItemSidebar(
                icone: Icons.tag,
                rotulo: 'Resumos',
                colapsado: estreita,
                onTap: () => abrir(const ResumosScreen()),
              ),
              _ItemSidebar(
                icone: Icons.menu_book_outlined,
                rotulo: 'Leituras',
                colapsado: estreita,
                onTap: () => abrir(const LeiturasScreen()),
              ),
              _ItemSidebar(
                icone: Icons.workspaces_outlined,
                rotulo: 'Ambientes',
                colapsado: estreita,
                onTap: () => abrir(const AmbientesScreen()),
              ),
              _ItemSidebar(
                icone: Icons.ios_share,
                rotulo: 'Exportar & Importar',
                colapsado: estreita,
                onTap: () => abrir(const ExportarScreen()),
              ),
              _ItemSidebar(
                icone: Icons.settings_outlined,
                rotulo: 'Configurações',
                colapsado: estreita,
                onTap: () => abrir(const ConfiguracoesScreen()),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Ícone de marca (34×34) — reaproveitado no cabeçalho expandido e colapsado.
class _LogoIcone extends StatelessWidget {
  const _LogoIcone();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: LuminaColors.safira.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: LuminaColors.safiraClara.withValues(alpha: 0.5),
        ),
      ),
      child: const Icon(Icons.auto_stories, size: 18, color: Colors.white),
    );
  }
}

class _RotuloSecao extends StatelessWidget {
  final String texto;

  const _RotuloSecao(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Text(texto.toUpperCase(), style: LuminaText.rotuloUppercase),
    );
  }
}

class _ItemSidebar extends StatelessWidget {
  final IconData icone;
  final IconData? iconeAtivo;
  final String rotulo;
  final bool ativo;
  final bool colapsado;
  final VoidCallback onTap;

  const _ItemSidebar({
    required this.icone,
    this.iconeAtivo,
    required this.rotulo,
    this.ativo = false,
    this.colapsado = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final corIcone = ativo ? Colors.white : VizColors.inkSecondary;
    final iconeEfetivo = ativo ? (iconeAtivo ?? icone) : icone;

    // Colapsado: só o ícone, centralizado — o rótulo migra pro Tooltip (some
    // da tela, mas continua acessível no hover/long-press).
    final conteudo = colapsado
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Center(
              child: Icon(iconeEfetivo, size: 19, color: corIcone),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(iconeEfetivo, size: 19, color: corIcone),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rotulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: ativo ? FontWeight.w600 : FontWeight.w400,
                      color: corIcone,
                    ),
                  ),
                ),
              ],
            ),
          );

    // Glow safira discreto no item ativo (banco Asimov, glass-effect2):
    // reforça onde o usuário está sem competir com o conteúdo.
    final botao = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: ativo
            ? LuminaElevation.glow(LuminaColors.safiraClara, alpha: 0.18)
            : null,
      ),
      child: Material(
        color: ativo
            ? LuminaColors.safiraClara.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Haptica.selecao();
            onTap();
          },
          child: conteudo,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: colapsado ? Tooltip(message: rotulo, child: botao) : botao,
    );
  }
}
