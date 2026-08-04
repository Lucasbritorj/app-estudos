import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';
import 'stats_service.dart';

/// Uma quest do dia com progresso mensurável (atual/alvo).
class QuestDia {
  final String id;
  final String titulo;
  final String descricao;
  final int atual;
  final int alvo;

  const QuestDia({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.atual,
    required this.alvo,
  });

  bool get concluida => atual >= alvo;
}

/// Quests diárias derivadas do planejador — moldura de checklist sobre o
/// algoritmo que já existe (déficit do ciclo, revisões espaçadas, mapa).
/// Nada é gravado; concluir = os dados do dia satisfazem a regra. De
/// propósito as quests NÃO dão XP: o bônus dependeria do plano vigente em
/// cada dia passado e não seria reproduzível — quebraria a derivação.
class QuestsService {
  /// Máximo de revisões pedidas na quest do dia.
  static const alvoMaxRevisoes = 3;

  /// [pisoMinutos] é costura de teste; produção usa o piso do streak.
  static List<QuestDia> questsDoDia({
    required DateTime hoje,
    required List<RegistroHora> registros,
    required List<Revisao> revisoes,
    String? materiaDeficitId,
    String? materiaDeficitNome,
    required bool temTopicos,
    int pisoMinutos = StatsService.pisoMinutosStreak,
  }) {
    final h = StatsService.dataSemHora(hoje);
    final registrosHoje = registros
        .where((r) => StatsService.dataSemHora(r.data) == h)
        .toList();

    // M-08 — mesma régua da chama do dashboard. Sem isto, uma sessão-token de
    // 1 minuto fechava a quest de estudo com o visto verde no MESMO scroll em
    // que a chama do streak zerava, porque `_diasComEstudoReal` exige o piso.
    // Quest de revisão fica de fora de propósito: concluir revisão é ato
    // próprio, não depende de ter estudado 15 minutos antes.
    //
    // Só afeta o dia corrente por construção — este serviço nunca computa
    // quest de dia passado (filtra `registrosHoje`), e quest não paga XP
    // (ver doc da classe). A monotonicidade de `GamificacaoService.xpDetalhado`
    // segue intocada.
    final minutosHoje = registrosHoje.fold<int>(0, (s, r) => s + r.minutos);
    final diaDeEstudoReal = minutosHoje >= pisoMinutos;

    final quests = <QuestDia>[];

    // 1. Sessão na matéria com maior déficit do ciclo (ou qualquer sessão,
    // sem cronograma).
    if (materiaDeficitId != null) {
      quests.add(
        QuestDia(
          id: 'estudar-deficit',
          titulo: 'Estudar ${materiaDeficitNome ?? 'a matéria do ciclo'}',
          descricao: 'É a matéria com maior déficit no ciclo desta semana',
          atual:
              diaDeEstudoReal &&
                  registrosHoje.any((r) => r.materiaId == materiaDeficitId)
              ? 1
              : 0,
          alvo: 1,
        ),
      );
    } else {
      quests.add(
        QuestDia(
          id: 'estudar-hoje',
          titulo: 'Estudar hoje',
          descricao: 'Pelo menos $pisoMinutos minutos somados no dia',
          atual: diaDeEstudoReal ? 1 : 0,
          alvo: 1,
        ),
      );
    }

    // 2. Revisões do dia: alvo estável = feitas hoje + pendentes até hoje,
    // teto de 3 — concluir revisões não encolhe o alvo no meio do dia.
    final feitasHoje = revisoes
        .where(
          (r) =>
              r.feita &&
              r.dataConclusao != null &&
              StatsService.dataSemHora(r.dataConclusao!) == h,
        )
        .length;
    final pendentesAteHoje = revisoes.where((r) {
      if (r.feita) return false;
      final agendada = StatsService.dataSemHora(r.dataAgendada);
      return !agendada.isAfter(h);
    }).length;
    final alvoRevisoes = (feitasHoje + pendentesAteHoje).clamp(
      0,
      alvoMaxRevisoes,
    );
    if (alvoRevisoes > 0) {
      quests.add(
        QuestDia(
          id: 'revisoes-do-dia',
          titulo:
              'Concluir $alvoRevisoes '
              '${alvoRevisoes == 1 ? 'revisão' : 'revisões'}',
          descricao: 'Revisão espaçada em dia é retenção garantida',
          atual: feitasHoje.clamp(0, alvoRevisoes),
          alvo: alvoRevisoes,
        ),
      );
    }

    // 3. Avançar no mapa: uma sessão de hoje amarrada a um tópico.
    if (temTopicos) {
      quests.add(
        QuestDia(
          id: 'topico-mapa',
          titulo: 'Estudar 1 tópico do mapa',
          descricao: 'Sessão com tópico marcado move o grafo de progresso',
          atual:
              diaDeEstudoReal &&
                  registrosHoje.any((r) => r.topicoId != null)
              ? 1
              : 0,
          alvo: 1,
        ),
      );
    }

    return quests;
  }
}
