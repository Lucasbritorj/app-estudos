import 'package:app_estudos/domain/diagnostico_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contrato do diagnóstico: determinístico, honesto e sem crash em borda.
void main() {
  Diagnostico gerar({
    int totalMinutos = 3000,
    int minutosHoje = 60,
    int minutosSemana = 300,
    int metaSemana = 600,
    int streak = 5,
    bool streakEmRisco = false,
    int atrasadas = 0,
    int diasEstudados14 = 8,
    double? trueRetention,
    double? taxaAcertoGeral,
    double? prontidaoAjustada,
    int? diasAteProva,
    int falsoDominio = 0,
    String? materiaSugerida,
    int deficitMinutos = 0,
  }) => DiagnosticoService.gerar(
    totalMinutos: totalMinutos,
    minutosHoje: minutosHoje,
    minutosSemana: minutosSemana,
    metaSemana: metaSemana,
    streak: streak,
    streakEmRisco: streakEmRisco,
    atrasadas: atrasadas,
    diasEstudados14: diasEstudados14,
    trueRetention: trueRetention,
    taxaAcertoGeral: taxaAcertoGeral,
    prontidaoAjustada: prontidaoAjustada,
    diasAteProva: diasAteProva,
    falsoDominio: falsoDominio,
    materiaSugerida: materiaSugerida,
    deficitMinutos: deficitMinutos,
  );

  group('semDados', () {
    test('menos de 1h registrada não gera veredito', () {
      final d = gerar(totalMinutos: 59);
      expect(d.nivel, NivelDiagnostico.semDados);
      expect(d.evidencias, isEmpty);
      expect(d.acao, isNotEmpty);
    });

    test('a partir de 1h já diagnostica', () {
      final d = gerar(totalMinutos: 60);
      expect(d.nivel, isNot(NivelDiagnostico.semDados));
    });
  });

  group('crítico', () {
    test('backlog grande + dia zerado + constância baixa', () {
      final d = gerar(
        minutosHoje: 0,
        atrasadas: 8,
        diasEstudados14: 3,
        minutosSemana: 120,
      );
      expect(d.nivel, NivelDiagnostico.critico);
      // A ação prioriza zerar o backlog antes de conteúdo novo.
      expect(d.acao, contains('8'));
      expect(d.acao.toLowerCase(), contains('revis'));
      // Evidência de constância sempre presente e com o piso explícito.
      expect(d.evidencias.first, contains('3 de 14'));
      expect(d.evidencias.first, contains('15 min'));
    });

    test('semana abaixo de 50% da meta é crítico mesmo sem backlog', () {
      final d = gerar(minutosSemana: 200, metaSemana: 600, diasEstudados14: 10);
      expect(d.nivel, NivelDiagnostico.critico);
    });

    test('prova a 30 dias com prontidão baixa escala para crítico', () {
      final d = gerar(
        diasEstudados14: 11,
        minutosSemana: 600,
        prontidaoAjustada: 0.55,
        diasAteProva: 30,
      );
      expect(d.nivel, NivelDiagnostico.critico);
      expect(d.evidencias.join(' '), contains('30 dias da prova'));
    });
  });

  group('atenção', () {
    test('retenção entre 75 e 85% derruba para atenção', () {
      final d = gerar(
        diasEstudados14: 11,
        minutosSemana: 600,
        trueRetention: 0.78,
      );
      expect(d.nivel, NivelDiagnostico.atencao);
      // Sem backlog e sem déficit, a ação ataca a retenção via questões.
      expect(d.acao.toLowerCase(), contains('questões'));
    });

    test('falso domínio conta como furo de atenção', () {
      final d = gerar(
        diasEstudados14: 11,
        minutosSemana: 600,
        falsoDominio: 2,
      );
      expect(d.nivel, NivelDiagnostico.atencao);
      expect(d.evidencias.join(' '), contains('falso domínio'));
    });
  });

  group('forte e constante', () {
    test('todos os pilares verdes = forte, sem bajulação vazia', () {
      final d = gerar(
        diasEstudados14: 12,
        minutosSemana: 620,
        metaSemana: 600,
        trueRetention: 0.9,
        taxaAcertoGeral: 0.88,
      );
      expect(d.nivel, NivelDiagnostico.forte);
      // O texto forte reconhece com base em números, não em elogio genérico.
      expect(d.mensagem.toLowerCase(), contains('números'));
    });

    test('meio-termo sem furo grave = constante', () {
      // Constância ok (forte) + sem backlog (forte), sem meta e sem
      // questões: 2 fortes < 3 → constante.
      final d = gerar(diasEstudados14: 11, metaSemana: 0);
      expect(d.nivel, NivelDiagnostico.constante);
    });
  });

  group('bordas', () {
    test('meta zero, retenção e taxa nulas não quebram nem viram evidência', () {
      final d = gerar(
        metaSemana: 0,
        trueRetention: null,
        taxaAcertoGeral: null,
      );
      expect(d.evidencias.join(' '), isNot(contains('meta')));
      expect(d.evidencias.join(' '), isNot(contains('Retenção')));
    });

    test('prova no passado não entra na régua', () {
      final d = gerar(
        diasEstudados14: 11,
        minutosSemana: 600,
        prontidaoAjustada: 0.4,
        diasAteProva: -3,
      );
      expect(d.evidencias.join(' '), isNot(contains('da prova')));
      expect(d.nivel, isNot(NivelDiagnostico.critico));
    });

    test('determinístico: mesmos inputs, mesmo texto', () {
      final a = gerar(atrasadas: 2, diasEstudados14: 7);
      final b = gerar(atrasadas: 2, diasEstudados14: 7);
      expect(a.mensagem, b.mensagem);
      expect(a.acao, b.acao);
      expect(a.evidencias, b.evidencias);
    });

    test('singular/plural de revisão atrasada', () {
      final umaAtrasada = gerar(atrasadas: 1);
      expect(umaAtrasada.evidencias.join(' '), contains('1 revisão atrasada'));
      final varias = gerar(atrasadas: 3);
      expect(varias.evidencias.join(' '), contains('3 revisões atrasadas'));
    });

    test('ação de déficit usa a matéria sugerida com horas formatadas', () {
      final d = gerar(
        diasEstudados14: 11,
        minutosSemana: 400,
        materiaSugerida: 'Direito Constitucional',
        deficitMinutos: 90,
      );
      expect(d.acao, contains('Direito Constitucional'));
      expect(d.acao, contains('1h30'));
    });
  });
}
