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

  /// 1 XP por minuto líquido estudado (XP base, usado no nível por matéria).
  static int xpTotal(List<RegistroHora> registros) =>
      registros.fold(0, (soma, r) => soma + r.minutos);

  /// XP global com bônus: minutos + 50 por revisão concluída + 10 por dia
  /// do streak atual. Tudo derivado, recalculado a cada leitura.
  static ({int base, int bonusRevisoes, int bonusStreak, int total})
      xpDetalhado(List<RegistroHora> registros, List<Revisao> revisoes,
          DateTime hoje) {
    final base = xpTotal(registros);
    final bonusRevisoes =
        revisoes.where((r) => r.feita).length * xpPorRevisaoFeita;
    final bonusStreak =
        StatsService.streakAtual(registros, hoje) * xpPorDiaDeStreak;
    return (
      base: base,
      bonusRevisoes: bonusRevisoes,
      bonusStreak: bonusStreak,
      total: base + bonusRevisoes + bonusStreak,
    );
  }

  /// Subir do nível n para n+1 custa 600·n XP (10h no primeiro degrau,
  /// crescendo linearmente). Nível mínimo: 1.
  static ({int nivel, int xpNoNivel, int xpParaProximo}) progressoNivel(
      int xp) {
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
      List<RegistroHora> registros, List<Revisao> revisoes, DateTime hoje) {
    final totalMinutos = xpTotal(registros);
    final streak = StatsService.streakAtual(registros, hoje);
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
