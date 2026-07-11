import 'package:app_estudos/domain/edital_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('numeração com pontos define profundidade', () {
    final itens = EditalParserService.parse(
        '1 Auditoria Governamental\n1.1 Conceitos\n1.1.1 NBASP\n2 AFO');
    expect(itens.map((i) => i.nome).toList(),
        ['Auditoria Governamental', 'Conceitos', 'NBASP', 'AFO']);
    expect(itens.map((i) => i.nivel).toList(), [0, 1, 2, 0]);
  });

  test('aceita sufixos "1." e "1)"', () {
    final itens = EditalParserService.parse('1. AFO\n2) Contabilidade');
    expect(itens.length, 2);
    expect(itens[0].nome, 'AFO');
    expect(itens[1].nome, 'Contabilidade');
    expect(itens.every((i) => i.nivel == 0), true);
  });

  test('marcador vira filho do último item numerado', () {
    final itens =
        EditalParserService.parse('1.1 Conceitos\n- princípio X\n• princípio Y');
    expect(itens[1].nome, 'princípio X');
    expect(itens[1].nivel, 2);
    expect(itens[2].nivel, 2);
  });

  test('marcador sem contexto anterior é raiz', () {
    final itens = EditalParserService.parse('- solto');
    expect(itens.single.nivel, 0);
  });

  test('linhas vazias ignoradas; linha sem prefixo é raiz', () {
    final itens = EditalParserService.parse('\n\nPortuguês\n\n');
    expect(itens.single.nome, 'Português');
    expect(itens.single.nivel, 0);
  });
}
