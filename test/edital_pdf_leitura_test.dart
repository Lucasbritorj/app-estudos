import 'package:app_estudos/data/models/leitura.dart';
import 'package:app_estudos/domain/edital_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parse — texto colado de PDF', () {
    test('itens separados por ";" na MESMA linha viram tópicos separados',
        () {
      const texto =
          '1 Compreensão de textos; 2 Tipologia textual; 2.1 Gêneros; '
          '3 Ortografia oficial';
      final itens = EditalParserService.parse(texto);
      expect(itens.length, 4);
      expect(itens[0].nome, 'Compreensão de textos');
      expect(itens[2].nome, 'Gêneros');
      expect(itens[2].nivel, 1);
    });

    test('numeração embutida após ponto final é separada (caso 19→9)', () {
      const texto =
          '1 Auditoria. 2 Controle externo. 2.1 TCU. 2.2 Congresso. '
          '3 Controle interno. 4 Governança. 5 Riscos. 6 Compliance. '
          '7 Accountability. 8 Transparência.';
      final itens = EditalParserService.parse(texto);
      expect(itens.length, 10);
      expect(itens.map((i) => i.nome), contains('Accountability'));
      expect(itens.last.nome, 'Transparência');
    });

    test('numeração com hífen ("1 - Tema") e letra ("a) sub") funcionam',
        () {
      const texto = '1 - Direito Constitucional\na) conceito\nb) fontes';
      final itens = EditalParserService.parse(texto);
      expect(itens.length, 3);
      expect(itens[0].nome, 'Direito Constitucional');
      expect(itens[1].nivel, 1);
    });
  });

  group('parseSecoes — edital completo', () {
    test('cabeçalho em caixa alta vira matéria com seus tópicos', () {
      const texto = 'LÍNGUA PORTUGUESA: 1 Compreensão; 2 Crase. '
          'NOÇÕES DE INFORMÁTICA: 1 Hardware; 2 Redes; 2.1 TCP/IP';
      final secoes = EditalParserService.parseSecoes(texto);
      expect(secoes.length, 2);
      expect(secoes[0].materia, 'LÍNGUA PORTUGUESA');
      expect(secoes[0].itens.length, 2);
      expect(secoes[1].materia, 'NOÇÕES DE INFORMÁTICA');
      expect(secoes[1].itens.length, 3);
      expect(secoes[1].itens.last.nivel, 1);
    });

    test('sem cabeçalho: uma seção única com materia null', () {
      final secoes =
          EditalParserService.parseSecoes('1 Tema A; 2 Tema B');
      expect(secoes.length, 1);
      expect(secoes.single.materia, null);
      expect(secoes.single.itens.length, 2);
    });
  });

  group('Leitura — sessões diárias', () {
    final leitura = Leitura(
      id: 'l1',
      titulo: 'Manual AFO',
      paginaInicio: 1,
      paginaFim: 100,
      partes: 4,
      partesConcluidas: const [false, false, false, false],
      sessoes: [
        SessaoLeitura(
            data: DateTime(2026, 7, 9), paginas: 20, minutos: 60),
        SessaoLeitura(
            data: DateTime(2026, 7, 10), paginas: 10, minutos: 20),
        // Sem tempo: conta páginas, fica fora do ritmo.
        SessaoLeitura(data: DateTime(2026, 7, 8), paginas: 10),
      ],
    );

    test('agregados: páginas, minutos e min/pág ponderado', () {
      expect(leitura.paginasRegistradas, 40);
      expect(leitura.minutosRegistrados, 80);
      // 30 pág cronometradas em 80 min = 2,67 min/pág.
      expect(leitura.minutosPorPagina, closeTo(80 / 30, 1e-9));
    });

    test('projeção usa páginas restantes × ritmo', () {
      // Restam 60 páginas × 2,67 = 160 min.
      expect(leitura.minutosParaTerminar, 160);
    });

    test('sem sessão cronometrada: ritmo e projeção null', () {
      final semTempo = leitura.copyWith(sessoes: [
        SessaoLeitura(data: DateTime(2026, 7, 9), paginas: 15),
      ]);
      expect(semTempo.minutosPorPagina, null);
      expect(semTempo.minutosParaTerminar, null);
    });

    test('roundtrip JSON preserva sessões; dados antigos sem campo ok', () {
      final volta = Leitura.fromJson(leitura.toJson());
      expect(volta.sessoes.length, 3);
      expect(volta.sessoes.first.paginas, 20);
      final antigo = leitura.toJson()..remove('sessoes');
      expect(Leitura.fromJson(antigo).sessoes, isEmpty);
    });
  });
}
