// `foundation` e `services` NÃO são reexportados por `material.dart`:
// `widgets.dart` só faz `export 'foundation.dart' show Brightness, UniqueKey`.
// Sem estes dois imports, `FlutterErrorDetails` e `Clipboard` não resolvem.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tela de último recurso quando o boot não consegue abrir os dados locais.
///
/// Deliberadamente **sem nenhum import do resto do app** (nem `app_theme`, nem
/// repositórios, nem Riverpod): esta é a única superfície que precisa
/// funcionar exatamente quando alguma outra coisa quebrou. Depender de código
/// que pode ser a causa da falha é como guardar o extintor dentro do quarto
/// que pega fogo. O grafite Lumina entra como literal por isso.
const _fundo = Color(0xFF0F1115);
const _superficie = Color(0xFF171A21);
const _texto = Color(0xFFE7E9EE);
const _textoFraco = Color(0xFF9BA1AE);
const _alerta = Color(0xFFFFB4A9);

/// Passo do boot que falhou. O texto muda conforme o passo porque "não
/// consegui abrir seus dados" e "não consegui atualizar o formato dos seus
/// dados" pedem reações diferentes de quem está lendo.
enum PassoBoot {
  armazenamento(
    'Não foi possível abrir seus dados',
    'O app guarda tudo no seu próprio aparelho, sem servidor. O armazenamento '
        'local não pôde ser aberto agora.',
  ),
  migracao(
    'Não foi possível preparar seus dados',
    'Seus dados foram abertos, mas a etapa que atualiza o formato interno não '
        'terminou.',
  );

  const PassoBoot(this.titulo, this.explicacao);

  final String titulo;
  final String explicacao;
}

/// App mínimo mostrado no lugar do `AppEstudos` quando o boot falha.
///
/// Regra de conteúdo que vale mais que o visual: **nunca sugerir limpar os
/// dados do app/site.** Numa falha de leitura os dados quase sempre continuam
/// intactos, e "limpar dados" é o único gesto realmente irreversível
/// disponível ao usuário. A tela avisa contra ele em vez de convidar.
class FalhaBootApp extends StatelessWidget {
  const FalhaBootApp({
    super.key,
    required this.passo,
    required this.erro,
    required this.aoTentarNovamente,
    this.pilha,
  });

  final PassoBoot passo;
  final Object erro;
  final StackTrace? pilha;
  final Future<void> Function() aoTentarNovamente;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meu Caminho Aprovado',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _fundo,
        colorScheme: const ColorScheme.dark(
          surface: _superficie,
          primary: _texto,
        ),
      ),
      home: _FalhaBootTela(
        passo: passo,
        erro: erro,
        pilha: pilha,
        aoTentarNovamente: aoTentarNovamente,
      ),
    );
  }
}

class _FalhaBootTela extends StatefulWidget {
  const _FalhaBootTela({
    required this.passo,
    required this.erro,
    required this.pilha,
    required this.aoTentarNovamente,
  });

  final PassoBoot passo;
  final Object erro;
  final StackTrace? pilha;
  final Future<void> Function() aoTentarNovamente;

  @override
  State<_FalhaBootTela> createState() => _FalhaBootTelaState();
}

class _FalhaBootTelaState extends State<_FalhaBootTela> {
  bool _tentando = false;
  bool _detalhesAbertos = false;

  String get _detalheTecnico {
    final pilha = widget.pilha;
    return 'passo: ${widget.passo.name}\n'
        'erro: ${widget.erro}\n'
        '${pilha == null ? '' : '\n$pilha'}';
  }

  Future<void> _tentarNovamente() async {
    if (_tentando) return;
    setState(() => _tentando = true);
    try {
      await widget.aoTentarNovamente();
    } finally {
      // Se a nova tentativa deu certo, `runApp` já trocou a árvore inteira e
      // este State não existe mais — daí o guarda de `mounted`.
      if (mounted) setState(() => _tentando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.report_problem_outlined,
                      color: _alerta, size: 40),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(
                      widget.passo.titulo,
                      style: const TextStyle(
                        color: _texto,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.passo.explicacao,
                    style: const TextStyle(
                      color: _textoFraco,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const _AvisoNaoLimpar(),
                  const SizedBox(height: 20),
                  const Text(
                    'O que costuma resolver',
                    style: TextStyle(
                      color: _texto,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _Causa('Feche as outras abas do app e tente de novo — '
                      'duas abas disputando o mesmo armazenamento é a causa '
                      'mais comum na web.'),
                  const _Causa('Saia da navegação anônima/privada: nela o '
                      'navegador bloqueia o armazenamento local.'),
                  const _Causa('Libere espaço no aparelho e recarregue.'),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: _tentando ? null : _tentarNovamente,
                        icon: _tentando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label:
                            Text(_tentando ? 'Tentando…' : 'Tentar de novo'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _detalheTecnico),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Detalhes técnicos copiados.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_all_outlined),
                        label: const Text('Copiar detalhes'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Detalhes(
                    aberto: _detalhesAbertos,
                    texto: _detalheTecnico,
                    aoAlternar: () => setState(
                      () => _detalhesAbertos = !_detalhesAbertos,
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

/// O aviso mais importante da tela: o gesto irreversível fica explicitamente
/// desaconselhado, em vez de o usuário chegar nele sozinho por eliminação.
class _AvisoNaoLimpar extends StatelessWidget {
  const _AvisoNaoLimpar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _alerta.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _alerta.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'Não limpe os dados do app nem do site. Este erro é de leitura — seu '
        'histórico de estudos provavelmente está intacto, e limpar os dados é '
        'a única ação daqui que não tem volta.',
        style: TextStyle(color: _alerta, fontSize: 14, height: 1.45),
      ),
    );
  }
}

class _Causa extends StatelessWidget {
  const _Causa(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('·  ', style: TextStyle(color: _textoFraco, fontSize: 14)),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: _textoFraco,
                fontSize: 14,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Detalhes extends StatelessWidget {
  const _Detalhes({
    required this.aberto,
    required this.texto,
    required this.aoAlternar,
  });

  final bool aberto;
  final String texto;
  final VoidCallback aoAlternar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton(
          onPressed: aoAlternar,
          child: Text(
            aberto ? 'Ocultar detalhes técnicos' : 'Ver detalhes técnicos',
            style: const TextStyle(color: _textoFraco, fontSize: 13),
          ),
        ),
        if (aberto)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _superficie,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              texto,
              style: const TextStyle(
                color: _textoFraco,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

/// Substitui a caixa cinza vazia que o release mostra quando um widget
/// específico falha no `build`. Não derruba o app: troca só a subárvore
/// quebrada por algo legível e copiável.
///
/// Envolvido em `Directionality` de propósito — o `ErrorWidget` padrão usa um
/// render object que não precisa dela, mas um widget comum precisa, e a falha
/// pode acontecer acima do `MaterialApp`, onde não há nenhuma no contexto.
Widget construirWidgetDeErro(FlutterErrorDetails detalhes) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Container(
      padding: const EdgeInsets.all(12),
      color: _fundo,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Esta parte da tela não pôde ser exibida.',
            style: TextStyle(
              color: _alerta,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: Text(
              '${detalhes.exception}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _textoFraco, fontSize: 11),
            ),
          ),
        ],
      ),
    ),
  );
}
