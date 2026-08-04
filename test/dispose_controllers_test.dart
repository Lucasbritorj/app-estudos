import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guarda estrutural: todo controller criado em `lib/` tem `dispose()`.
///
/// Por que varrer o FONTE em vez de detectar vazamento em runtime:
///
/// - `testWidgets(experimentalLeakTesting:)` existe no Flutter 3.44.8, mas
///   `LeakTesting` vem de `leak_tracker_flutter_testing`, dependência
///   TRANSITIVA. Usá-la exigiria promovê-la a `dev_dependency` direta, e a
///   própria documentação do Flutter marca a API como experimental e não
///   recomendada.
/// - Observar de fora é impossível: os controllers que vazavam eram locais de
///   função de diálogo, sem superfície pública.
///
/// O que este teste pega: a regressão de AUSÊNCIA (alguém adiciona um
/// controller e esquece o dispose). O que ele NÃO pega: dispose PREMATURO —
/// liberar enquanto o widget ainda vive. Esse segundo caso só aparece em teste
/// de widget que abra o diálogo, e hoje só `revisoes_no_dashboard_test.dart`
/// faz isso. Registrado para ninguém confundir a cobertura com garantia total.
///
/// Escape hatch: uma linha com `// dispose-exempt: <motivo>` imediatamente
/// acima da criação isenta aquele controller (caso legítimo: a posse passa
/// para um widget que dispõe por conta).
void main() {
  const tipos = [
    'TextEditingController',
    'AnimationController',
    'ScrollController',
    'TabController',
    'PageController',
    'FocusNode',
    'TransformationController',
  ];

  final criacao = RegExp(
    r'^\s*(?:late\s+)?(?:final\s+)?(?:\w+\s+)?(_?\w+)\s*=\s*'
    '(${tipos.join('|')})'
    r'[.(]',
  );

  test('nenhum controller em lib/ fica sem dispose', () {
    final raiz = Directory('lib');
    expect(
      raiz.existsSync(),
      isTrue,
      reason:
          'teste roda a partir da raiz do pacote; cwd atual = '
          '${Directory.current.path}',
    );

    final arquivos =
        raiz
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    final faltando = <String>[];
    var conferidos = 0;

    for (final arquivo in arquivos) {
      final linhas = arquivo.readAsStringSync().replaceAll('\r\n', '\n').split(
        '\n',
      );
      final texto = linhas.join('\n');
      final dispostos = RegExp(
        r'(\w+)\.dispose\(\)',
      ).allMatches(texto).map((m) => m.group(1)).toSet();

      for (var i = 0; i < linhas.length; i++) {
        final m = criacao.firstMatch(linhas[i]);
        if (m == null) continue;
        if (i > 0 && linhas[i - 1].contains('dispose-exempt:')) continue;

        conferidos++;
        final variavel = m.group(1)!;
        if (!dispostos.contains(variavel)) {
          faltando.add(
            '${arquivo.path.replaceAll(r'\', '/')}:${i + 1}  '
            '$variavel (${m.group(2)})',
          );
        }
      }
    }

    // Sanidade do próprio teste: se o regex parar de casar, ele passaria
    // vazio e daria falsa segurança.
    expect(
      conferidos,
      greaterThanOrEqualTo(60),
      reason:
          'só $conferidos controllers encontrados — o padrão de detecção '
          'provavelmente quebrou, não o código',
    );

    expect(
      faltando,
      isEmpty,
      reason:
          'controllers sem dispose (${faltando.length}):\n'
          '  ${faltando.join('\n  ')}\n\n'
          'Em função que abre diálogo: libere depois do `await showDialog`. '
          'Em State: no `dispose()`. Se a posse é de outro widget, marque a '
          'linha anterior com `// dispose-exempt: <motivo>`.',
    );
  });

  test('toda isenção tem motivo escrito e está na lista conhecida', () {
    // A isenção existe porque `Route.didComplete` (navigator.dart:480)
    // completa o Future do showDialog no POP, não quando a rota sai da
    // árvore. Diálogo que continua mexendo em estado global depois do pop
    // força um rebuild de si mesmo enquanto ainda anima a saída — e aí um
    // controller já liberado explode. `.whenComplete` não resolve (roda no
    // mesmo instante) e `addPostFrameCallback` também não (a saída dura
    // vários frames).
    //
    // Lista fechada de propósito: isenção nova exige editar este teste, o que
    // obriga o revisor a ler o motivo no diff.
    const conhecidas = {'lib/features/configuracoes/configuracoes_screen.dart'};

    final encontradas = <String, String>{};
    for (final arquivo in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final linhas = arquivo.readAsStringSync().split('\n');
      for (var i = 0; i < linhas.length; i++) {
        if (!linhas[i].contains('dispose-exempt:')) continue;
        final caminho = arquivo.path.replaceAll(r'\', '/');
        final motivo = linhas[i].split('dispose-exempt:').last.trim();
        encontradas[caminho] = motivo;
        expect(
          motivo,
          isNotEmpty,
          reason: '$caminho:${i + 1} — isenção sem motivo escrito',
        );
      }
    }

    expect(
      encontradas.keys.toSet(),
      conhecidas,
      reason:
          'isenções mudaram. Se adicionou uma, escreva o motivo na linha e '
          'inclua o arquivo em `conhecidas` — isenção silenciosa vira '
          'vazamento esquecido.',
    );
  });
}
