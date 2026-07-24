import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';
import 'stats_service.dart';

class BadgeStatus {
  final String id;
  final String titulo;
  final String descricao;
  final bool conquistada;

  const BadgeStatus({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.conquistada,
  });
}

/// Gamificação leve, 100% derivada dos dados — nada é gravado, então nunca
/// dessincroniza do histórico real.
class GamificacaoService {
  static const xpPorRevisaoFeita = 50;
  static const xpPorDiaDeStreak = 10;

  /// Teto de revisões que rendem bônus por DIA de conclusão (M-02). Sem ele o
  /// loop "criar revisão manual → concluir em 1 clique → +50 XP" era infinito:
  /// 20 revisões fabricadas e concluídas no mesmo minuto valiam 1000 XP.
  /// Alinhado ao alvo de revisões das quests — 3 revisões/dia é o ritmo real.
  static const maxRevisoesComBonusPorDia = 3;

  /// Bônus de revisão com teto diário. Revisão feita sem [dataConclusao]
  /// (dado antigo, pré-carimbo) entra num balde próprio e continua contando —
  /// o teto não pode revogar XP já conquistado no histórico.
  static int bonusRevisoes(List<Revisao> revisoes) {
    var semData = 0;
    final porDia = <DateTime, int>{};
    for (final r in revisoes) {
      if (!r.feita) continue;
      final d = r.dataConclusao;
      if (d == null) {
        semData++;
        continue;
      }
      final dia = DateTime(d.year, d.month, d.day);
      porDia[dia] = (porDia[dia] ?? 0) + 1;
    }
    var contadas = semData;
    for (final n in porDia.values) {
      contadas += n > maxRevisoesComBonusPorDia ? maxRevisoesComBonusPorDia : n;
    }
    return contadas * xpPorRevisaoFeita;
  }

  /// 1 XP por minuto líquido estudado (XP base, usado no nível por matéria).
  static int xpTotal(List<RegistroHora> registros) =>
      registros.fold(0, (soma, r) => soma + r.minutos);

  /// Multiplicador de dificuldade: peso 1 do edital = ×1.0, cada ponto de
  /// peso soma 10%, teto ×1.5. Matéria difícil rende mais XP por minuto.
  static double multiplicadorPeso(int peso) =>
      (1 + 0.1 * (peso - 1)).clamp(1.0, 1.5);

  /// XP base ponderado pelo peso da matéria de cada registro. Sem mapa de
  /// pesos (ou matéria desconhecida) degrada para 1 XP/minuto.
  static int xpPonderado(
    List<RegistroHora> registros,
    Map<String, int> pesoPorMateria,
  ) {
    var total = 0.0;
    for (final r in registros) {
      total += r.minutos * multiplicadorPeso(pesoPorMateria[r.materiaId] ?? 1);
    }
    return total.round();
  }

  /// XP global com bônus: minutos ponderados por peso + 50 por revisão
  /// concluída + 10 por dia do MAIOR streak já alcançado. Tudo derivado e
  /// MONÓTONO: base (minutos) e revisões só crescem, e o bônus de streak usa
  /// o pico histórico ([StatsService.streakPico]) em vez do streak atual —
  /// assim o XP total nunca cai de um dia pro outro ao perder o streak
  /// (antes caía, e badges eram revogadas). Continua 100% derivado.
  static ({int base, int bonusRevisoes, int bonusStreak, int total})
  xpDetalhado(
    List<RegistroHora> registros,
    List<Revisao> revisoes,
    DateTime hoje, {
    Map<String, int> pesoPorMateria = const {},
  }) {
    final base = xpPonderado(registros, pesoPorMateria);
    final bonus = bonusRevisoes(revisoes);
    final bonusStreak = StatsService.streakPico(registros) * xpPorDiaDeStreak;
    return (
      base: base,
      bonusRevisoes: bonus,
      bonusStreak: bonusStreak,
      total: base + bonus + bonusStreak,
    );
  }

  /// Subir do nível n para n+1 custa 600·n XP (10h no primeiro degrau,
  /// crescendo linearmente). Nível mínimo: 1.
  static ({int nivel, int xpNoNivel, int xpParaProximo}) progressoNivel(
    int xp,
  ) {
    var nivel = 1;
    var resto = xp;
    var custo = 600;
    while (resto >= custo) {
      resto -= custo;
      nivel++;
      custo = 600 * nivel;
    }
    return (nivel: nivel, xpNoNivel: resto, xpParaProximo: custo);
  }

  static int nivelPara(int xp) => progressoNivel(xp).nivel;

  static List<BadgeStatus> badges(
    List<RegistroHora> registros,
    List<Revisao> revisoes,
    DateTime hoje,
  ) {
    final totalMinutos = xpTotal(registros);
    // Badge de streak deriva do PICO histórico — conquistou uma vez, não
    // perde. Perder o streak atual não revoga "Semana cheia"/"Mês de ferro".
    final streak = StatsService.streakPico(registros);
    final temRevisoes = revisoes.isNotEmpty;
    final nenhumaAtrasada = revisoes
        .where((r) => r.statusEm(hoje) == RevisaoStatus.atrasada)
        .isEmpty;

    return [
      BadgeStatus(
        id: 'primeira-sessao',
        titulo: 'Primeira sessão',
        descricao: 'Registrou a primeira hora de estudo',
        conquistada: registros.isNotEmpty,
      ),
      BadgeStatus(
        id: 'dez-sessoes',
        titulo: 'Constância',
        descricao: '10 sessões registradas',
        conquistada: registros.length >= 10,
      ),
      BadgeStatus(
        id: 'streak-7',
        titulo: 'Semana cheia',
        descricao: '7 dias seguidos de estudo',
        conquistada: streak >= 7,
      ),
      BadgeStatus(
        id: 'streak-30',
        titulo: 'Mês de ferro',
        descricao: '30 dias seguidos de estudo',
        conquistada: streak >= 30,
      ),
      BadgeStatus(
        id: 'horas-50',
        titulo: '50 horas',
        descricao: '50 horas líquidas acumuladas',
        conquistada: totalMinutos >= 50 * 60,
      ),
      BadgeStatus(
        id: 'horas-100',
        titulo: '100 horas',
        descricao: '100 horas líquidas acumuladas',
        conquistada: totalMinutos >= 100 * 60,
      ),
      BadgeStatus(
        id: 'primeira-revisao',
        titulo: 'Revisor',
        descricao: 'Concluiu a primeira revisão espaçada',
        conquistada: revisoes.any((r) => r.feita),
      ),
      BadgeStatus(
        id: 'revisoes-em-dia',
        titulo: 'Em dia',
        descricao: 'Nenhuma revisão atrasada',
        conquistada: temRevisoes && nenhumaAtrasada,
      ),
    ];
  }
}
