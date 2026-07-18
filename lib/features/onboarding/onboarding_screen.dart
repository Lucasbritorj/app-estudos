import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/haptica.dart';
import '../../data/repositories/configuracoes_repositorio.dart';

/// Um passo do tour inicial: ícone, título e explicação curta.
class _PassoOnboarding {
  final IconData icone;
  final Color tinta;
  final String titulo;
  final String descricao;

  const _PassoOnboarding({
    required this.icone,
    required this.tinta,
    required this.titulo,
    required this.descricao,
  });
}

const _passos = <_PassoOnboarding>[
  _PassoOnboarding(
    icone: Icons.auto_stories,
    tinta: LuminaColors.safiraClara,
    titulo: 'Bem-vindo ao Meu Caminho Aprovado',
    descricao:
        'Seu controle de estudos para concursos, 100% offline. Horas, '
        'revisões espaçadas e prontidão para a prova — tudo calculado a '
        'partir dos seus próprios registros.',
  ),
  _PassoOnboarding(
    icone: Icons.timer_outlined,
    tinta: LuminaColors.safiraClara,
    titulo: 'Registre cada sessão',
    descricao:
        'Use o cronômetro ou o registro manual. Estudo teórico (páginas) e '
        'prática (questões) viram gráficos, streak e ranking de desempenho '
        'sem você fazer conta.',
  ),
  _PassoOnboarding(
    icone: Icons.library_books_outlined,
    tinta: LuminaColors.ouro,
    titulo: 'Monte seu edital',
    descricao:
        'Cadastre matérias com peso e cole o texto do edital: os tópicos '
        'viram uma árvore de estudo, com pré-requisitos e mapa de progresso.',
  ),
  _PassoOnboarding(
    icone: Icons.event_repeat_outlined,
    tinta: LuminaColors.safiraClara,
    titulo: 'Nunca esqueça o que estudou',
    descricao:
        'Ao concluir uma aula nasce a cadeia de revisões espaçadas. Marque a '
        'data da prova e acompanhe sua prontidão projetada no ritmo atual.',
  ),
];

/// Tour de primeira execução (item de onboarding multi-passo). Aparece uma
/// única vez — ao concluir ou pular, grava [Configuracoes.onboardingConcluido]
/// e o gate em `_HomeShell` libera o app. Complementa (não substitui) o
/// estado vazio do dashboard.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controle = PageController();
  int _pagina = 0;

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  bool get _ultima => _pagina == _passos.length - 1;

  Future<void> _concluir() async {
    Haptica.selecao();
    final repo = ref.read(configuracoesProvider.notifier);
    final atual = ref.read(configuracoesProvider);
    await repo.salvar(atual.copyWith(onboardingConcluido: true));
  }

  void _avancar() {
    if (_ultima) {
      _concluir();
      return;
    }
    Haptica.selecao();
    _controle.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ConteudoCentral(
          maxWidth: 520,
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                  child: TextButton(
                    onPressed: _concluir,
                    child: const Text('Pular'),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controle,
                  onPageChanged: (i) => setState(() => _pagina = i),
                  itemCount: _passos.length,
                  itemBuilder: (context, i) => _Passo(passo: _passos[i]),
                ),
              ),
              _Indicadores(total: _passos.length, ativo: _pagina),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _avancar,
                    child: Text(_ultima ? 'Começar' : 'Próximo'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Passo extends StatelessWidget {
  final _PassoOnboarding passo;

  const _Passo({required this.passo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: passo.tinta.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: passo.tinta.withValues(alpha: 0.4)),
            ),
            child: Icon(passo.icone, size: 44, color: passo.tinta),
          ),
          const SizedBox(height: 28),
          Text(
            passo.titulo,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: VizColors.inkPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            passo.descricao,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: VizColors.inkSecondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Indicadores extends StatelessWidget {
  final int total;
  final int ativo;

  const _Indicadores({required this.total, required this.ativo});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == ativo ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == ativo ? LuminaColors.safiraClara : VizColors.gridline,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
