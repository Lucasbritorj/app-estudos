import '../data/models/registro_hora.dart';
import '../data/models/simulado.dart';

/// Desempenho consolidado numa banca.
typedef DesempenhoBanca = ({
  String banca,
  int questoes,
  int acertos,
  double taxa,
  int simulados,
});

/// Análise de desempenho por banca organizadora — funções puras.
///
/// Concurso não se estuda "em geral": cada banca tem um estilo (CEBRASPE em
/// certo/errado com pegadinha de literalidade, FGV com raciocínio longo, FCC
/// com letra de lei). Um candidato com 80% na FCC e 55% na CEBRASPE não tem um
/// problema de conteúdo — tem um problema de banca, e é uma leitura que a taxa
/// geral esconde.
class BancaService {
  /// Amostra mínima para a taxa por banca sair do ruído. Mesma régua do
  /// [InsightsService.amostraMinimaQuestoes]: 3/3 não é 100%.
  static const amostraMinima = 10;

  /// Questões e acertos somados por banca, considerando sessões (prática) e
  /// simulados. Sessão sem banca informada fica de fora — não existe balde
  /// "outras", que misturaria estilos e mentiria na comparação.
  static Map<String, ({int questoes, int acertos, int simulados})> agregar(
    List<RegistroHora> registros,
    List<Simulado> simulados,
  ) {
    final questoes = <String, int>{};
    final acertos = <String, int>{};
    final provas = <String, int>{};
    for (final r in registros) {
      final banca = r.banca;
      if (banca == null || (r.questoes ?? 0) <= 0) continue;
      questoes[banca] = (questoes[banca] ?? 0) + r.questoes!;
      acertos[banca] = (acertos[banca] ?? 0) + (r.acertos ?? 0);
    }
    for (final s in simulados) {
      final banca = s.banca;
      if (banca == null || s.totalQuestoes <= 0) continue;
      questoes[banca] = (questoes[banca] ?? 0) + s.totalQuestoes;
      acertos[banca] = (acertos[banca] ?? 0) + s.totalAcertos;
      provas[banca] = (provas[banca] ?? 0) + 1;
    }
    return {
      for (final b in questoes.keys)
        b: (
          questoes: questoes[b]!,
          acertos: acertos[b] ?? 0,
          simulados: provas[b] ?? 0,
        ),
    };
  }

  /// Ranking por taxa de acerto, melhor primeiro. Bancas abaixo de
  /// [amostraMinima] questões ficam de fora do ranking (mas seguem no
  /// agregado) — ordenar por ruído induz a decisão errada.
  static List<DesempenhoBanca> ranking(
    List<RegistroHora> registros,
    List<Simulado> simulados, {
    int amostraMinimaQuestoes = amostraMinima,
  }) {
    final agregado = agregar(registros, simulados);
    return [
      for (final e in agregado.entries)
        if (e.value.questoes >= amostraMinimaQuestoes)
          (
            banca: e.key,
            questoes: e.value.questoes,
            acertos: e.value.acertos,
            taxa: e.value.acertos / e.value.questoes,
            simulados: e.value.simulados,
          ),
    ]..sort((a, b) {
      final porTaxa = b.taxa.compareTo(a.taxa);
      if (porTaxa != 0) return porTaxa;
      return b.questoes.compareTo(a.questoes);
    });
  }

  /// Taxa numa banca específica; null sem questões dela.
  static double? taxaDaBanca(
    List<RegistroHora> registros,
    List<Simulado> simulados,
    String banca,
  ) {
    final d = agregar(registros, simulados)[banca];
    if (d == null || d.questoes == 0) return null;
    return d.acertos / d.questoes;
  }

  /// Matriz banca × matéria: onde exatamente o estilo da banca dói.
  /// Chave externa = banca, interna = matéria. Só sessões (o simulado agrega
  /// por matéria, mas sem banca por resultado — a banca é da prova inteira,
  /// então também entra).
  static Map<String, Map<String, ({int questoes, int acertos})>> porBancaEMateria(
    List<RegistroHora> registros,
    List<Simulado> simulados,
  ) {
    final matriz = <String, Map<String, ({int questoes, int acertos})>>{};
    void somar(String banca, String materiaId, int q, int a) {
      final linha = matriz.putIfAbsent(banca, () => {});
      final atual = linha[materiaId] ?? (questoes: 0, acertos: 0);
      linha[materiaId] = (questoes: atual.questoes + q, acertos: atual.acertos + a);
    }

    for (final r in registros) {
      final banca = r.banca;
      if (banca == null || (r.questoes ?? 0) <= 0) continue;
      somar(banca, r.materiaId, r.questoes!, r.acertos ?? 0);
    }
    for (final s in simulados) {
      final banca = s.banca;
      if (banca == null) continue;
      for (final res in s.resultados) {
        if (res.questoes <= 0) continue;
        somar(banca, res.materiaId, res.questoes, res.acertos);
      }
    }
    return matriz;
  }

  /// Pior par (banca, matéria) com amostra suficiente — a recomendação mais
  /// acionável do módulo. Null quando nenhum par atinge a amostra mínima.
  static ({String banca, String materiaId, double taxa, int questoes})? pontoFraco(
    List<RegistroHora> registros,
    List<Simulado> simulados, {
    int amostraMinimaQuestoes = amostraMinima,
  }) {
    ({String banca, String materiaId, double taxa, int questoes})? pior;
    porBancaEMateria(registros, simulados).forEach((banca, linha) {
      linha.forEach((materiaId, d) {
        if (d.questoes < amostraMinimaQuestoes) return;
        final taxa = d.acertos / d.questoes;
        if (pior == null || taxa < pior!.taxa) {
          pior = (
            banca: banca,
            materiaId: materiaId,
            taxa: taxa,
            questoes: d.questoes,
          );
        }
      });
    });
    return pior;
  }

  /// Bancas já registradas pelo usuário, mais usadas primeiro — alimenta a
  /// sugestão do formulário com o histórico real antes do catálogo fixo.
  static List<String> bancasUsadas(
    List<RegistroHora> registros,
    List<Simulado> simulados,
  ) {
    final uso = <String, int>{};
    for (final r in registros) {
      final b = r.banca;
      if (b != null) uso[b] = (uso[b] ?? 0) + 1;
    }
    for (final s in simulados) {
      final b = s.banca;
      if (b != null) uso[b] = (uso[b] ?? 0) + 1;
    }
    final ordenadas = uso.keys.toList()
      ..sort((a, b) {
        final porUso = uso[b]!.compareTo(uso[a]!);
        return porUso != 0 ? porUso : a.compareTo(b);
      });
    return ordenadas;
  }
}
