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

  test('dado corrompido (acertos > questões) é clampado, não estoura', () {
    // Import de CSV/JSON pode trazer acertos=50, questoes=10 — o clamp
    // impede que contamine o rating acima de uma sessão perfeita.
    final corrompido = DominioService.dominioDoTopico(
        [sessao('r1', dia, questoes: 10, acertos: 50)], 't1')!;
    final perfeito = DominioService.dominioDoTopico(
        [sessao('r2', dia, questoes: 10, acertos: 10)], 't1')!;
    expect(corrompido.dominio, perfeito.dominio);
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

  group('recência temporal (decaimento por tempo, não só ordem)', () {
    test('staleness: sem referência não decai; com referência distante '
        'regride em direção ao neutro (0.5)', () {
      final registros = [
        sessao('r1', DateTime(2026, 1, 1), questoes: 10, acertos: 10),
      ];
      final semRef = DominioService.dominioDoTopico(registros, 't1')!;
      // Referência 180 dias depois: 3 meias-vidas (H=60) -> rating cai a 1/8,
      // domínio muito mais perto de 0.5 do que o medido sem referência.
      final comRef = DominioService.dominioDoTopico(
        registros,
        't1',
        referencia: DateTime(2026, 6, 30),
      )!;
      expect(semRef.dominio, closeTo(0.5987, 0.0005));
      expect(comRef.dominio, lessThan(semRef.dominio));
      expect(comRef.dominio, greaterThan(0.5)); // regride ao neutro, não passa
      expect((comRef.dominio - 0.5).abs(),
          lessThan((semRef.dominio - 0.5).abs()));
    });

    test('lacuna longa antes de evidência recente: o recente domina mais do '
        'que domina quando as sessões são coladas', () {
      // Bom-antigo depois ruim-recente. Com lacuna grande, o bom-antigo já
      // regrediu quando o ruim chega -> domínio final mais baixo (o ruim
      // recente pesa mais) do que quando as duas são no mesmo dia.
      final comLacuna = DominioService.dominioDoTopico([
        sessao('bom', DateTime(2026, 1, 1), questoes: 10, acertos: 10),
        sessao('ruim', DateTime(2026, 6, 1), questoes: 10, acertos: 3),
      ], 't1')!;
      final coladas = DominioService.dominioDoTopico([
        sessao('bom', DateTime(2026, 6, 1), questoes: 10, acertos: 10),
        sessao('ruim', DateTime(2026, 6, 2), questoes: 10, acertos: 3),
      ], 't1')!;
      expect(comLacuna.dominio, lessThan(coladas.dominio));
    });
  });
}
