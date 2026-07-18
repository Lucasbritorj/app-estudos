import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/haptica.dart';
import 'data/repositories/configuracoes_repositorio.dart';
import 'features/ambientes/ambientes_screen.dart';
import 'features/configuracoes/configuracoes_screen.dart';
import 'features/cronometro/cronometro_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
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
class _Sidebar extends ConsumerWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aba = ref.watch(abaProvider);

    void abrir(Widget tela) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    }

    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: VizColors.chromeSidebar,
        border: Border(right: BorderSide(color: VizColors.bordaSutil)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: LuminaColors.safira.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: LuminaColors.safiraClara.withValues(alpha: 0.5),
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_stories,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
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
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _RotuloSecao('Menu'),
          _ItemSidebar(
            icone: Icons.insights_outlined,
            iconeAtivo: Icons.insights,
            rotulo: 'Dashboard',
            ativo: aba == Abas.dashboard,
            onTap: () => ref.read(abaProvider.notifier).ir(Abas.dashboard),
          ),
          _ItemSidebar(
            icone: Icons.timer_outlined,
            iconeAtivo: Icons.timer,
            rotulo: 'Cronômetro',
            ativo: aba == Abas.cronometro,
            onTap: () => ref.read(abaProvider.notifier).ir(Abas.cronometro),
          ),
          _ItemSidebar(
            icone: Icons.library_books_outlined,
            iconeAtivo: Icons.library_books,
            rotulo: 'Matérias',
            ativo: aba == Abas.materias,
            onTap: () => ref.read(abaProvider.notifier).ir(Abas.materias),
          ),
          _ItemSidebar(
            icone: Icons.event_repeat_outlined,
            iconeAtivo: Icons.event_repeat,
            rotulo: 'Revisões',
            ativo: aba == Abas.revisoes,
            onTap: () => ref.read(abaProvider.notifier).ir(Abas.revisoes),
          ),
          const SizedBox(height: 18),
          const _RotuloSecao('Ferramentas'),
          _ItemSidebar(
            icone: Icons.account_tree_outlined,
            rotulo: 'Mapa de Estudos',
            onTap: () => abrir(const MapaEstudosScreen()),
          ),
          _ItemSidebar(
            icone: Icons.calendar_month_outlined,
            rotulo: 'Planejamento',
            onTap: () => abrir(const PlanejamentoScreen()),
          ),
          _ItemSidebar(
            icone: Icons.fact_check_outlined,
            rotulo: 'Simulados & Provas',
            onTap: () => abrir(const SimuladosScreen()),
          ),
          _ItemSidebar(
            icone: Icons.tag,
            rotulo: 'Resumos',
            onTap: () => abrir(const ResumosScreen()),
          ),
          _ItemSidebar(
            icone: Icons.menu_book_outlined,
            rotulo: 'Leituras',
            onTap: () => abrir(const LeiturasScreen()),
          ),
          _ItemSidebar(
            icone: Icons.workspaces_outlined,
            rotulo: 'Ambientes',
            onTap: () => abrir(const AmbientesScreen()),
          ),
          _ItemSidebar(
            icone: Icons.ios_share,
            rotulo: 'Exportar & Importar',
            onTap: () => abrir(const ExportarScreen()),
          ),
          _ItemSidebar(
            icone: Icons.settings_outlined,
            rotulo: 'Configurações',
            onTap: () => abrir(const ConfiguracoesScreen()),
          ),
        ],
      ),
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
  final VoidCallback onTap;

  const _ItemSidebar({
    required this.icone,
    this.iconeAtivo,
    required this.rotulo,
    this.ativo = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      // Glow safira discreto no item ativo (banco Asimov, glass-effect2):
      // reforça onde o usuário está sem competir com o conteúdo.
      child: DecoratedBox(
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    ativo ? (iconeAtivo ?? icone) : icone,
                    size: 19,
                    color: ativo ? Colors.white : VizColors.inkSecondary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rotulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: ativo ? FontWeight.w600 : FontWeight.w400,
                        color: ativo ? Colors.white : VizColors.inkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
