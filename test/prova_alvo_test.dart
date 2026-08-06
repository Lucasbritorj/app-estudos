import 'package:app_estudos/domain/prova_alvo.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contagem regressiva até a prova.
///
/// A conta e os quatro rótulos viviam duplicados: um `?:` aninhado dentro do
/// `build` de `card_prontidao.dart` e uma subtração solta em
/// `dashboard_providers.dart`. Nenhuma borda era coberta. Extraídos para
/// `domain/prova_alvo.dart`, as strings continuam idênticas — o que muda é
/// que agora existe teste.
///
/// Toda âncora é fixa: nada aqui depende do relógio do CI.
void main() {
  final hoje = DateTime(2026, 7, 29);

  group('diasAteProva', () {
    test('mesmo dia = 0; futuro positivo; passado negativo', () {
      expect(diasAteProva(hoje, DateTime(2026, 7, 29)), 0);
      expect(diasAteProva(hoje, DateTime(2026, 7, 30)), 1);
      expect(diasAteProva(hoje, DateTime(2026, 7, 31)), 2);
      expect(diasAteProva(hoje, DateTime(2026, 7, 28)), -1);
      expect(diasAteProva(hoje, DateTime(2026, 7, 26)), -3);
      expect(diasAteProva(hoje, DateTime(2026, 11, 12)), 106);
    });

    test('compara DIA, não instante: hora não desloca a contagem', () {
      // Sem o truncamento, "hoje 23:59 → prova hoje 00:00" daria -1 e o card
      // anunciaria que a prova já passou no dia da prova.
      final tarde = DateTime(2026, 7, 29, 23, 59);
      expect(diasAteProva(tarde, DateTime(2026, 7, 29)), 0);
      expect(diasAteProva(hoje, tarde), 0);
      final manha = DateTime(2026, 7, 30, 6);
      expect(diasAteProva(DateTime(2026, 7, 29, 18), manha), 1);
    });

    test('viradas de mês, de ano e fevereiro bissexto', () {
      expect(diasAteProva(DateTime(2026, 1, 31), DateTime(2026, 2, 1)), 1);
      expect(diasAteProva(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 1);
      // 2026 não é bissexto: 28/02 → 01/03 é 1 dia.
      expect(diasAteProva(DateTime(2026, 2, 28), DateTime(2026, 3, 1)), 1);
      // 2028 é: o 29/02 entra no meio e vira 2.
      expect(diasAteProva(DateTime(2028, 2, 28), DateTime(2028, 3, 1)), 2);
    });
  });

  group('rotuloRegressiva', () {
    test('singular e plural concordam', () {
      expect(rotuloRegressiva(0, hoje), 'É HOJE');
      expect(rotuloRegressiva(1, hoje), 'falta 1 dia');
      expect(rotuloRegressiva(2, hoje), 'faltam 2 dias');
      expect(rotuloRegressiva(106, hoje), 'faltam 106 dias');
    });

    test('prova passada mostra a data, não "faltam -N dias"', () {
      expect(
        rotuloRegressiva(-1, DateTime(2026, 7, 28)),
        'prova em 28/07/2026',
      );
      expect(
        rotuloRegressiva(-3, DateTime(2026, 7, 26)),
        'prova em 26/07/2026',
      );
    });

    test('limiar de 30 dias (onde a cor do card vira atenção) tem rótulo', () {
      expect(rotuloRegressiva(30, hoje), 'faltam 30 dias');
      expect(rotuloRegressiva(31, hoje), 'faltam 31 dias');
    });
  });

  test('composição ponta a ponta reproduz o que o card exibia', () {
    String rotulo(DateTime dataProva) =>
        rotuloRegressiva(diasAteProva(hoje, dataProva), dataProva);

    expect(rotulo(DateTime(2026, 7, 29)), 'É HOJE');
    expect(rotulo(DateTime(2026, 7, 30)), 'falta 1 dia');
    expect(rotulo(DateTime(2026, 8, 28)), 'faltam 30 dias');
    expect(rotulo(DateTime(2026, 7, 28)), 'prova em 28/07/2026');
  });
}
