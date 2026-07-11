import 'package:app_estudos/data/models/leitura.dart';
import 'package:app_estudos/domain/leitura_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('divide intervalo exato em partes iguais', () {
    final blocos = LeituraService.dividir(1, 100, 4);
    expect(blocos, [
      (inicio: 1, fim: 25),
      (inicio: 26, fim: 50),
      (inicio: 51, fim: 75),
      (inicio: 76, fim: 100),
    ]);
  });

  test('resto vai para as primeiras partes (diferença máxima de 1)', () {
    final blocos = LeituraService.dividir(1, 10, 3);
    expect(blocos, [
      (inicio: 1, fim: 4),
      (inicio: 5, fim: 7),
      (inicio: 8, fim: 10),
    ]);
  });

  test('mais partes que páginas: uma página por parte', () {
    final blocos = LeituraService.dividir(1, 3, 5);
    expect(blocos.length, 3);
    expect(blocos.first, (inicio: 1, fim: 1));
    expect(blocos.last, (inicio: 3, fim: 3));
  });

  test('intervalo inválido retorna vazio', () {
    expect(LeituraService.dividir(10, 5, 3), isEmpty);
    expect(LeituraService.dividir(1, 10, 0), isEmpty);
  });

  test('páginas concluídas e progresso por parte', () {
    final leitura = Leitura(
      id: 'l1',
      titulo: 'Manual AFO',
      paginaInicio: 1,
      paginaFim: 10,
      partes: 3,
      partesConcluidas: const [true, false, false],
    );
    // Parte 1 = págs 1-4 (4 páginas de 10).
    expect(LeituraService.paginasConcluidas(leitura), 4);
    expect(LeituraService.progresso(leitura), 0.4);
  });
}
