import 'package:flutter_test/flutter_test.dart';
import 'package:app_estudos/features/concursos/estado_concursos.dart';

void main() {
  test('legado sem estado e estado vazio válidos', () {
    validarEstadoConcursos(null);
    validarEstadoConcursos({});
  });
  test('coleções e tipos malformados rejeitados', () {
    for (final input in [
      [],
      {'perfil': 42},
      {
        'acompanhados': ['fgv:https://evil'],
      },
      {
        'publicacoes': {'x': {}},
      },
      {
        'consultas': {
          'fgv:': {'sucesso': false},
        },
      },
      {
        'aprovadas': {'id': false},
      },
    ]) {
      expect(() => validarEstadoConcursos(input), throwsFormatException);
    }
  });
  test(
    'URL restaurada não oficial rejeitada',
    () => expect(
      () => validarEstadoConcursos({
        'publicacoes': {
          'x': {
            'id': 'x',
            'versao': 'v',
            'titulo': 't',
            'fonte': 'fgv',
            'url': 'https://evil.example/test',
          },
        },
      }),
      throwsFormatException,
    ),
  );
}
