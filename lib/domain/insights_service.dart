import '../data/models/materia.dart';
import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';
import 'stats_service.dart';

/// Categorias do card "O que melhorar hoje" — a UI escolhe ícone/cor por
/// tipo, a mensagem já vem pronta e acionável.
enum TipoInsight { desempenho, revisao, streak, ritmo, positivo }

class InsightAcao {
  final TipoInsight tipo;
  final String mensagem;

  /// Matéria alvo (quando o insight aponta uma) — vira atalho de registro.
  final String? materiaId;

  const InsightAcao(this.tipo, this.mensagem, {this.materiaId});
}

/// Rankings e recomendações do dashboard — funções puras, 100% testáveis.
/// Amostra mínima de questões evita ranking por ruído (2/2 = "100%").
class InsightsService {
  static const amostraMinimaQuestoes = 10;

  /// Matéria com mais minutos acumulados; null sem registros.
  static ({String materiaId, int minutos})? maisEstudada(
      List<RegistroHora> registros) {
    final porMateria = StatsService.minutosPorMateria(registros);
    if (porMateria.isEmpty) return null;
    final top =
        porMateria.entries.reduce((a, b) => b.value > a.value ? b : a);
    return (materiaId: top.key, minutos: top.value);
  }

  /// Ranking de acertos/erros por matéria, maior taxa primeiro. Só entra
  /// matéria com pelo menos [minQuestoes] questões registradas.
  static List<({String materiaId, int questoes, int acertos, double taxa})>
      rankingAcertos(List<RegistroHora> registros,
          {int minQuestoes = amostraMinimaQuestoes}) {
    final desempenho = StatsService.desempenhoPorMateria(registros);
    final linhas = [
      for (final e in desempenho.entries)
        if (e.value.questoes >= minQuestoes)
          (
            materiaId: e.key,
            questoes: e.value.questoes,
            acertos: e.value.acertos,
            taxa: e.value.acertos / e.value.questoes,
          ),
    ]..sort((a, b) => b.taxa.compareTo(a.taxa));
    return linhas;
  }

  /// Dia da semana com mais minutos (1=segunda..7=domingo); null sem dados.
  static ({int diaSemana, int minutos})? melhorDiaSemana(
      List<RegistroHora> registros) {
    final porDia = StatsService.minutosPorDiaSemana(registros);
    if (porDia.isEmpty) return null;
    final top = porDia.entries.reduce((a, b) => b.value > a.value ? b : a);
    return (diaSemana: top.key, minutos: top.value);
  }

  /// Minutos por ambiente no período — agregação registro→matéria→ambiente.
  /// Registro de matéria apagada é ignorado (sem ambiente rastreável).
  static Map<String, int> minutosPorAmbiente(
      List<RegistroHora> registros, List<Materia> materias,
      {DateTime? de, DateTime? ate}) {
    final ambienteDaMateria = {
      for (final m in materias) m.id: m.ambienteId,
    };
    final resultado = <String, int>{};
    final porMateria =
        StatsService.minutosPorMateria(registros, de: de, ate: ate);
    for (final e in porMateria.entries) {
      final ambienteId = ambienteDaMateria[e.key];
      if (ambienteId == null) continue;
      resultado[ambienteId] = (resultado[ambienteId] ?? 0) + e.value;
    }
    return resultado;
  }

  /// Recomendações acionáveis de hoje, em ordem de urgência:
  /// revisões atrasadas > pior desempenho > streak em risco. Vazio nunca:
  /// sem pendência devolve um insight positivo.
  static List<InsightAcao> melhorarHoje({
    required List<RegistroHora> registros,
    required List<Materia> materias,
    required List<Revisao> revisoes,
    required DateTime hoje,
  }) {
    final acoes = <InsightAcao>[];
    final nomes = {for (final m in materias) m.id: m.nome};

    final atrasadas = revisoes
        .where((r) => r.statusEm(hoje) == RevisaoStatus.atrasada)
        .length;
    if (atrasadas > 0) {
      acoes.add(InsightAcao(
        TipoInsight.revisao,
        atrasadas == 1
            ? 'Você tem 1 revisão atrasada — 20 minutos resolvem.'
            : 'Você tem $atrasadas revisões atrasadas — comece por elas '
                '(15-20 min cada).',
      ));
    }

    final ranking = rankingAcertos(registros);
    if (ranking.isNotEmpty && ranking.last.taxa < 0.75) {
      final pior = ranking.last;
      final nome = nomes[pior.materiaId];
      if (nome != null) {
        acoes.add(InsightAcao(
          TipoInsight.desempenho,
          'Baixo desempenho em $nome '
          '(${(pior.taxa * 100).toStringAsFixed(0)}% em ${pior.questoes} '
          'questões) — recomendo 2h de questões dela esta semana.',
          materiaId: pior.materiaId,
        ));
      }
    }

    final streak = StatsService.streakAtual(registros, hoje);
    final estudouHoje = StatsService.minutosNoDia(registros, hoje) > 0;
    if (streak > 0 && !estudouHoje) {
      acoes.add(InsightAcao(
        TipoInsight.streak,
        'Streak de $streak ${streak == 1 ? 'dia' : 'dias'} em risco — '
        '25 minutos hoje mantêm a chama acesa.',
      ));
    }

    if (acoes.isEmpty) {
      acoes.add(const InsightAcao(
        TipoInsight.positivo,
        'Tudo em dia. Avance na aula mais próxima de concluir '
        'ou puxe questões da matéria de menor taxa.',
      ));
    }
    return acoes;
  }
}
