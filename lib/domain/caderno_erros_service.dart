import '../data/models/materia.dart';
import '../data/models/questao_errada.dart';
import 'revisao_service.dart';

/// Agregado de erros de um escopo (matéria, tópico ou banca).
typedef ResumoErros = ({int total, int ativas, int dominadas, double? taxa});

/// Regras puras do caderno de erros — fila, agendamento e estatísticas.
///
/// O agendamento reusa [RevisaoService.proximoPassoFsrs]: a curva de
/// esquecimento não muda porque o item é uma questão em vez de um tópico, e
/// duplicar o motor criaria duas verdades sobre espaçamento.
class CadernoErrosService {
  /// Fila do dia: questões vencidas e ativas, mais urgentes primeiro.
  ///
  /// Ordem: peso do edital desc (matéria que vale mais na prova primeiro),
  /// depois atraso desc (o que está esperando há mais tempo), depois mais
  /// tentativas erradas (a questão que insiste em não entrar).
  static List<QuestaoErrada> fila(
    List<QuestaoErrada> questoes,
    DateTime hoje, {
    Map<String, int> pesoPorMateria = const {},
    int? limite,
  }) {
    final vencidas = [
      for (final q in questoes)
        if (q.venceEm(hoje)) q,
    ]..sort((a, b) {
      final peso = (pesoPorMateria[b.materiaId] ?? 1).compareTo(
        pesoPorMateria[a.materiaId] ?? 1,
      );
      if (peso != 0) return peso;
      final atraso = a.proximaTentativa.compareTo(b.proximaTentativa);
      if (atraso != 0) return atraso;
      final erros = (b.totalTentativas - b.totalAcertos).compareTo(
        a.totalTentativas - a.totalAcertos,
      );
      if (erros != 0) return erros;
      return a.criadaEm.compareTo(b.criadaEm);
    });
    if (limite == null || limite >= vencidas.length) return vencidas;
    return vencidas.take(limite).toList();
  }

  /// Registra uma tentativa de refazer e devolve a questão reagendada.
  ///
  /// Acertou: espaça pelo FSRS (taxa 1.0). [QuestaoErrada.acertosParaDominar]
  /// acertos seguidos arquivam a questão — o caderno precisa esvaziar, senão
  /// vira um passivo que só cresce e o candidato para de abrir.
  /// Errou: lapso (taxa 0.0) — estabilidade cai a 40% e a questão volta curto.
  static QuestaoErrada registrarTentativa(
    QuestaoErrada questao,
    bool acertou,
    DateTime hoje,
  ) {
    final tentativas = [...questao.tentativas, acertou];
    final acertosSeguidos = () {
      var n = 0;
      for (final a in tentativas.reversed) {
        if (!a) break;
        n++;
      }
      return n;
    }();

    final intervaloAtual = questao.estabilidade?.round() ?? 0;
    final passo = RevisaoService.proximoPassoFsrs(
      estabilidade: questao.estabilidade,
      dificuldade: questao.dificuldade,
      intervaloAtual: intervaloAtual,
      diasDeAtraso: DateTime(hoje.year, hoje.month, hoje.day)
          .difference(questao.proximaTentativa)
          .inDays,
      taxaAcerto: acertou ? 1.0 : 0.0,
    );

    // Cadeia encerrada pelo teto (intervalo > 120d) = domínio de sobra.
    final dominou =
        acertosSeguidos >= QuestaoErrada.acertosParaDominar || passo == null;
    final dias = passo?.dias ?? RevisaoService.tetoDiasFsrs;

    return questao.copyWith(
      tentativas: tentativas,
      estabilidade: passo?.estabilidade,
      dificuldade: passo?.dificuldade,
      proximaTentativa: DateTime(hoje.year, hoje.month, hoje.day + dias),
      arquivada: dominou,
    );
  }

  /// Reabre uma questão arquivada (voltou a errar em prova, quer revisar).
  static QuestaoErrada reabrir(QuestaoErrada questao, DateTime hoje) =>
      questao.copyWith(
        arquivada: false,
        proximaTentativa: DateTime(hoje.year, hoje.month, hoje.day),
      );

  /// Agregado por matéria: total no caderno, ativas, dominadas e taxa ao
  /// refazer. Só entra matéria com pelo menos uma questão — sem inventar 0%.
  static Map<String, ResumoErros> porMateria(List<QuestaoErrada> questoes) =>
      _agrupar(questoes, (q) => q.materiaId);

  /// Agregado por tópico (só questões com tópico).
  static Map<String, ResumoErros> porTopico(List<QuestaoErrada> questoes) =>
      _agrupar(questoes, (q) => q.topicoId);

  /// Agregado por banca (só questões com banca informada).
  static Map<String, ResumoErros> porBanca(List<QuestaoErrada> questoes) =>
      _agrupar(questoes, (q) => q.banca);

  static Map<String, ResumoErros> _agrupar(
    List<QuestaoErrada> questoes,
    String? Function(QuestaoErrada) chave,
  ) {
    final tentativas = <String, int>{};
    final acertos = <String, int>{};
    final total = <String, int>{};
    final ativas = <String, int>{};
    final dominadas = <String, int>{};
    for (final q in questoes) {
      final k = chave(q);
      if (k == null) continue;
      total[k] = (total[k] ?? 0) + 1;
      if (q.arquivada) {
        dominadas[k] = (dominadas[k] ?? 0) + 1;
      } else {
        ativas[k] = (ativas[k] ?? 0) + 1;
      }
      tentativas[k] = (tentativas[k] ?? 0) + q.totalTentativas;
      acertos[k] = (acertos[k] ?? 0) + q.totalAcertos;
    }
    return {
      for (final k in total.keys)
        k: (
          total: total[k]!,
          ativas: ativas[k] ?? 0,
          dominadas: dominadas[k] ?? 0,
          taxa: (tentativas[k] ?? 0) == 0
              ? null
              : (acertos[k] ?? 0) / tentativas[k]!,
        ),
    };
  }

  /// Matérias com mais erros ativos, piores primeiro — o "onde estou sangrando"
  /// do caderno. Empate desfeito pelo peso do edital.
  static List<({Materia materia, ResumoErros resumo})> ranking(
    List<QuestaoErrada> questoes,
    List<Materia> materias,
  ) {
    final agregado = porMateria(questoes);
    return [
      for (final m in materias)
        if (agregado[m.id] != null && agregado[m.id]!.ativas > 0)
          (materia: m, resumo: agregado[m.id]!),
    ]..sort((a, b) {
      final porAtivas = b.resumo.ativas.compareTo(a.resumo.ativas);
      if (porAtivas != 0) return porAtivas;
      return b.materia.peso.compareTo(a.materia.peso);
    });
  }

  /// Taxa de recuperação: fração das questões do caderno já dominadas.
  /// Null com caderno vazio.
  static double? taxaRecuperacao(List<QuestaoErrada> questoes) {
    if (questoes.isEmpty) return null;
    return questoes.where((q) => q.arquivada).length / questoes.length;
  }

  /// Previsão de carga: quantas questões vencem em cada um dos próximos
  /// [dias] dias. Atrasadas entram no dia 0 — espelha
  /// [RevisaoService.forecastCarga] para o card ter a mesma leitura.
  static List<({DateTime dia, int quantidade})> forecast(
    List<QuestaoErrada> questoes,
    DateTime hoje, {
    int dias = 14,
  }) {
    final base = DateTime(hoje.year, hoje.month, hoje.day);
    final contagem = <DateTime, int>{};
    for (final q in questoes) {
      if (q.arquivada) continue;
      final alvo = q.proximaTentativa.isBefore(base) ? base : q.proximaTentativa;
      final offset = alvo.difference(base).inDays;
      if (offset < 0 || offset >= dias) continue;
      contagem[alvo] = (contagem[alvo] ?? 0) + 1;
    }
    return List.generate(dias, (i) {
      final dia = DateTime(base.year, base.month, base.day + i);
      return (dia: dia, quantidade: contagem[dia] ?? 0);
    });
  }
}
