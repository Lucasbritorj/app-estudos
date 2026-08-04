import 'package:app_estudos/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trava a convenção pt-BR dos formatadores.
///
/// Não havia teste nenhum sobre `core/utils/formatters.dart` — o que explica
/// como um `toStringAsFixed(1)` cru sobreviveu no PDF de exportação
/// mostrando "3.5 pág/h" no meio de um documento em português.
///
/// Regra do app, e o que estes testes protegem: decimal do USUÁRIO usa
/// vírgula; milhar usa ponto. O inverso disso (CSV do modelo estrela para
/// Power BI) é formato de MÁQUINA e fica deliberadamente fora daqui — quem
/// mexer em `ExportService` e "consertar" o ponto de lá quebra a importação.
void main() {
  group('formatarDecimal — vírgula, nunca ponto', () {
    test('meio: 3.5 -> "3,5"', () => expect(formatarDecimal(3.5), '3,5'));

    test('inteiro mantém a casa decimal pedida', () {
      expect(formatarDecimal(3), '3,0');
    });

    test('casas configuráveis', () {
      expect(formatarDecimal(3.14159, casas: 2), '3,14');
      expect(formatarDecimal(1.0, casas: 3), '1,000');
    });

    test('meio EXATO em binário arredonda para longe do zero', () {
      // 0.5, 2.5, 3.25 têm representação binária exata, então a regra visível
      // é "metade sobe". `toStringAsFixed` não faz arredondamento bancário.
      expect(formatarDecimal(3.25, casas: 1), '3,3');
      expect(formatarDecimal(2.5, casas: 0), '3');
      expect(formatarDecimal(0.5, casas: 0), '1');
      expect(formatarDecimal(-2.5, casas: 0), '-3');
    });

    test('meio INEXATO em binário arredonda pelo valor real, não pelo literal', () {
      // Armadilha que já me pegou escrevendo este arquivo: 3.15 parece pedir
      // "3,2", mas o double mais próximo é 3.1499999999999999112 — abaixo do
      // meio. `toStringAsFixed` arredonda o BINÁRIO, não o texto que se
      // digitou. Mesmo motivo de 1.005 -> "1,00" (real: 1.0049999999999998934).
      //
      // Isto não é defeito de `formatarDecimal`: é IEEE-754, e a alternativa
      // (Decimal/BigInt) custaria uma dependência inteira para formatar
      // pág/h e horas semanais. Fica documentado em vez de "consertado".
      expect(formatarDecimal(3.15, casas: 1), '3,1');
      expect(formatarDecimal(1.005, casas: 2), '1,00');
    });

    test('negativo preserva o sinal', () {
      expect(formatarDecimal(-2.5), '-2,5');
    });

    test('zero', () => expect(formatarDecimal(0), '0,0'));

    test('nenhuma saída contém ponto decimal', () {
      for (final v in [0.0, 1.05, -7.25, 99.9, 1234.5]) {
        expect(formatarDecimal(v), isNot(contains('.')), reason: 'v=$v');
      }
    });
  });

  group('formatarInteiro — ponto como milhar', () {
    test('48231 -> "48.231"', () => expect(formatarInteiro(48231), '48.231'));

    test('abaixo de mil não ganha separador', () {
      expect(formatarInteiro(999), '999');
      expect(formatarInteiro(0), '0');
    });

    test('milhão tem dois separadores', () {
      expect(formatarInteiro(1234567), '1.234.567');
    });

    test('convenção é o INVERSO da do decimal — vírgula nunca aparece', () {
      expect(formatarInteiro(48231), isNot(contains(',')));
    });
  });

  group('formatarMinutos', () {
    test('abaixo de 1h fica em minutos', () {
      expect(formatarMinutos(45), '45min');
      expect(formatarMinutos(0), '0min');
      expect(formatarMinutos(59), '59min');
    });

    test('hora cheia omite os minutos', () {
      expect(formatarMinutos(60), '1h');
      expect(formatarMinutos(120), '2h');
    });

    test('hora quebrada zera à esquerda', () {
      expect(formatarMinutos(135), '2h 15min');
      expect(formatarMinutos(65), '1h 05min');
    });
  });

  group('formatarHorasCompacto', () {
    test('despreza minutos e aplica milhar pt-BR', () {
      expect(formatarHorasCompacto(119999), '1.999h');
      expect(formatarHorasCompacto(60), '1h');
    });
  });

  group('datas em dd/MM', () {
    test('formatarData usa o padrão brasileiro, não o americano', () {
      // 03/08/2026: se saísse "08/03/2026" seria março nos EUA.
      expect(formatarData(DateTime(2026, 8, 3)), '03/08/2026');
    });

    test('formatarDiaMes', () {
      expect(formatarDiaMes(DateTime(2026, 12, 25)), '25/12');
    });
  });

  group('formatarCronometro', () {
    test('sempre dois dígitos em cada campo', () {
      expect(formatarCronometro(const Duration(seconds: 5)), '00:00:05');
      expect(
        formatarCronometro(const Duration(hours: 1, minutes: 23, seconds: 45)),
        '01:23:45',
      );
    });

    test('passa de 24h sem virar dia', () {
      expect(formatarCronometro(const Duration(hours: 30)), '30:00:00');
    });
  });

  group('plural', () {
    test('1 fica no singular, o resto no plural', () {
      expect(plural(1, 'erro', 'erros'), '1 erro');
      expect(plural(2, 'erro', 'erros'), '2 erros');
      expect(plural(0, 'erro', 'erros'), '0 erros');
    });
  });
}
