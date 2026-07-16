import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/dominio_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora sessao(String id, DateTime data,
        {int? questoes, int? acertos, String topico = 't1'}) =>
    RegistroHora(
      id: id,
      data: data,
      materiaId: 'm1',
      topicoId: topico,
      minutos: 60,
      questoes: questoes,
      acertos: acertos,
    );

void main() {
  final dia = DateTime(2026, 7, 1);

  test('sem questões registradas: null, nunca valor inventado', () {
    final soTeoria = [sessao('r1', dia)]; // minutos sem questões
    expect(DominioService.dominioDoTopico(soTeoria, 't1'), isNull);
    expect(DominioService.dominioDoTopico(const [], 't1'), isNull);
  });

  test('sessão cheia perfeita parte do neutro e sobe ~10 p.p.', () {
    final d = DominioService.dominioDoTopico(
        [sessao('r1', dia, questoes: 10, acertos: 10)], 't1')!;
    // rating = 0.8 * 1.0 * (1.0 - 0.5) = 0.4 -> sigmoide(0.4)
    expect(d.dominio, closeTo(0.5987, 0.0005));
    expect(d.questoes, 10);
    expect(d.confiavel, isTrue);
  });

  test('sessão ruim desce abaixo do neutro', () {
    final d = DominioService.dominioDoTopico(
        [sessao('r1', dia, questoes: 10, acertos: 2)], 't1')!;
    // rating = 0.8 * 1.0 * (0.2 - 0.5) = -0.24 -> sigmoide(-0.24)
    expect(d.dominio, closeTo(0.4403, 0.0005));
  });

  test('sessão pequena move menos que sessão cheia e não é confiável', () {
    final pequena = DominioService.dominioDoTopico(
        [sessao('r1', dia, questoes: 2, acertos: 2)], 't1')!;
    final cheia = DominioService.dominioDoTopico(
        [sessao('r1', dia, questoes: 10, acertos: 10)], 't1')!;
    expect(pequena.dominio, lessThan(cheia.dominio));
    expect(pequena.confiavel, isFalse); // 2 < amostraMinima
    expect(cheia.confiavel, isTrue);
  });

  test('sessões consistentes convergem para domínio alto', () {
    final registros = [
      for (var i = 0; i < 5; i++)
        sessao('r$i', DateTime(2026, 7, 1 + i), questoes: 10, acertos: 10),
    ];
    final d = DominioService.dominioDoTopico(registros, 't1')!;
    expect(d.dominio, greaterThan(0.75));
    expect(d.questoes, 50);
  });

  test('evidência recente pesa mais que a antiga (ordem cronológica)', () {
    // Mesmas sessões, ordens opostas: quem termina mal fica abaixo de quem
    // termina bem — exatamente o que a taxa acumulada não distingue.
    final terminaMal = DominioService.dominioDoTopico([
      sessao('bom', DateTime(2026, 7, 1), questoes: 10, acertos: 10),
      sessao('ruim', DateTime(2026, 7, 10), questoes: 10, acertos: 2),
    ], 't1')!;
    final terminaBem = DominioService.dominioDoTopico([
      sessao('ruim', DateTime(2026, 7, 1), questoes: 10, acertos: 2),
      sessao('bom', DateTime(2026, 7, 10), questoes: 10, acertos: 10),
    ], 't1')!;
    expect(terminaMal.dominio, lessThan(terminaBem.dominio));
  });

  test('só registros do tópico entram na projeção', () {
    final registros = [
      sessao('r1', dia, questoes: 10, acertos: 10),
      sessao('r2', dia, questoes: 10, acertos: 0, topico: 'outro'),
    ];
    final d = DominioService.dominioDoTopico(registros, 't1')!;
    expect(d.questoes, 10);
    expect(d.dominio, greaterThan(0.5));
  });
}
