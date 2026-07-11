import 'package:app_estudos/features/dashboard/frases_do_dia.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('366 frases — uma por dia do ano, bissexto incluso', () {
    expect(frasesDoDia.length, 366);
  });

  test('nenhuma frase repetida e nenhuma vazia', () {
    expect(frasesDoDia.toSet().length, frasesDoDia.length);
    expect(frasesDoDia.every((f) => f.trim().isNotEmpty), true);
  });

  test('indexação por dia-do-ano cobre 1º de janeiro e 31 de dezembro', () {
    int diaDoAno(DateTime d) =>
        d.difference(DateTime(d.year, 1, 1)).inDays;
    // Ano bissexto (2028): 31/12 é o dia 365 (0-based) — usa a frase 366.
    expect(diaDoAno(DateTime(2028, 12, 31)) % frasesDoDia.length, 365);
    // Ano comum (2026): 31/12 é o dia 364.
    expect(diaDoAno(DateTime(2026, 12, 31)) % frasesDoDia.length, 364);
    expect(diaDoAno(DateTime(2026, 1, 1)) % frasesDoDia.length, 0);
  });
}
