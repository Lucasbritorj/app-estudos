import '../data/models/registro_hora.dart';

/// "True retention" (à la Anki): taxa de acerto NAS REVISÕES concluídas —
/// recall no vencimento —, não em qualquer prática. Mede se o intervalo de
/// spaced repetition está calibrado: retenção real muito abaixo da alvo
/// significa intervalos longos demais; muito acima, curtos demais.
///
/// Fonte: ao concluir uma revisão com desempenho, o app grava uma sessão
/// prática marcada com [marcadorRevisao] no início da tarefa
/// (revisao_use_case) — é essa sessão, e só ela, que conta aqui.
class RetencaoService {
  /// Prefixo da tarefa dos registros criados ao concluir uma revisão.
  static const marcadorRevisao = 'Revisão:';

  static bool _ehRecall(RegistroHora r) =>
      r.tarefa.startsWith(marcadorRevisao) && (r.questoes ?? 0) > 0;

  /// True retention geral (todas as matérias); null sem recall registrado —
  /// sem dado, sem número inventado.
  static double? geral(List<RegistroHora> registros) {
    var questoes = 0;
    var acertos = 0;
    for (final r in registros) {
      if (!_ehRecall(r)) continue;
      questoes += r.questoes!;
      acertos += r.acertos ?? 0;
    }
    return questoes == 0 ? null : acertos / questoes;
  }

  /// True retention por matéria (só matérias com recall registrado). O mapa
  /// não traz matérias sem revisão concluída — o consumidor decide como
  /// exibir a ausência.
  static Map<String, ({int questoes, int acertos, double taxa})> porMateria(
    List<RegistroHora> registros,
  ) {
    final acc = <String, ({int questoes, int acertos})>{};
    for (final r in registros) {
      if (!_ehRecall(r)) continue;
      final atual = acc[r.materiaId] ?? (questoes: 0, acertos: 0);
      acc[r.materiaId] = (
        questoes: atual.questoes + r.questoes!,
        acertos: atual.acertos + (r.acertos ?? 0),
      );
    }
    return {
      for (final e in acc.entries)
        e.key: (
          questoes: e.value.questoes,
          acertos: e.value.acertos,
          taxa: e.value.acertos / e.value.questoes,
        ),
    };
  }
}
