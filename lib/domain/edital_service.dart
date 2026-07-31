import '../data/models/materia.dart';
import '../data/models/registro_hora.dart';
import '../data/models/topico.dart';
import 'dominio_service.dart';

/// Situação de um tópico do edital verticalizado.
enum SituacaoTopico {
  /// Nenhuma sessão registrada nele. O buraco mais caro do edital.
  intocado,

  /// Estudado, mas sem questões suficientes para medir domínio.
  estudado,

  /// Elo confiável abaixo do limiar — sabe, mas erra.
  fragil,

  /// Elo confiável acima do limiar, ou marcado como concluído.
  dominado,
}

/// Linha do edital verticalizado.
typedef LinhaEdital = ({
  Topico topico,
  SituacaoTopico situacao,
  int minutos,
  int questoes,
  double? dominio,
});

/// Cobertura consolidada de uma matéria.
typedef CoberturaMateria = ({
  Materia materia,
  int totalTopicos,
  int intocados,
  int dominados,
  /// Fração do PESO dos tópicos já dominada (0..1).
  double cobertura,
  /// Fração do peso ao menos tocada (estudada), dominada ou não.
  double coberturaTocada,
});

/// Edital verticalizado: quanto do edital já foi coberto, ponderado por peso.
///
/// Horas estudadas não dizem se o edital acabou — dizem só que houve esforço.
/// O que decide aprovação é cobertura: quanto do que a banca vai cobrar já
/// está dominado. Este serviço cruza tópicos (o edital importado), sessões
/// (o que foi tocado) e o Elo (o que de fato entrou), tudo ponderado pelo peso
/// de cada tópico — porque um tópico de peso 5 intocado é um problema maior
/// que cinco de peso 1.
class EditalService {
  /// Domínio confiável a partir do qual o tópico conta como dominado.
  /// Mesmo limiar do desbloqueio do mapa ([MapaEstudosService.dominioLiberacao])
  /// — duas réguas diferentes para "sabe o suficiente" confundiriam o usuário.
  static const limiarDominio = 0.6;

  /// Situação de cada tópico, na ordem recebida.
  static List<LinhaEdital> linhas(
    List<Topico> topicos,
    List<RegistroHora> registros, {
    DateTime? referencia,
  }) {
    final minutos = <String, int>{};
    final questoes = <String, int>{};
    final porTopico = <String, List<RegistroHora>>{};
    final ids = {for (final t in topicos) t.id};
    for (final r in registros) {
      final id = r.topicoId;
      if (id == null || !ids.contains(id)) continue;
      minutos[id] = (minutos[id] ?? 0) + r.minutos;
      questoes[id] = (questoes[id] ?? 0) + (r.questoes ?? 0);
      (porTopico[id] ??= []).add(r);
    }

    return [
      for (final t in topicos)
        () {
          final medicao = DominioService.dominioDe(
            porTopico[t.id] ?? const [],
            referencia: referencia,
          );
          final min = minutos[t.id] ?? 0;
          final SituacaoTopico situacao;
          if (t.concluido) {
            situacao = SituacaoTopico.dominado;
          } else if (min == 0 && (questoes[t.id] ?? 0) == 0) {
            situacao = SituacaoTopico.intocado;
          } else if (medicao == null || !medicao.confiavel) {
            situacao = SituacaoTopico.estudado;
          } else {
            situacao = medicao.dominio >= limiarDominio
                ? SituacaoTopico.dominado
                : SituacaoTopico.fragil;
          }
          return (
            topico: t,
            situacao: situacao,
            minutos: min,
            questoes: questoes[t.id] ?? 0,
            dominio: medicao?.dominio,
          );
        }(),
    ];
  }

  /// Cobertura de uma matéria a partir das linhas dos seus tópicos.
  /// Matéria sem tópico cadastrado devolve cobertura 0 com `totalTopicos: 0` —
  /// nunca 100% (edital vazio não é edital coberto, é edital não cadastrado).
  static CoberturaMateria cobertura(
    Materia materia,
    List<LinhaEdital> linhasDaMateria,
  ) {
    var pesoTotal = 0;
    var pesoDominado = 0;
    var pesoTocado = 0;
    var intocados = 0;
    var dominados = 0;
    for (final l in linhasDaMateria) {
      pesoTotal += l.topico.peso;
      if (l.situacao == SituacaoTopico.dominado) {
        pesoDominado += l.topico.peso;
        dominados++;
      }
      if (l.situacao == SituacaoTopico.intocado) {
        intocados++;
      } else {
        pesoTocado += l.topico.peso;
      }
    }
    return (
      materia: materia,
      totalTopicos: linhasDaMateria.length,
      intocados: intocados,
      dominados: dominados,
      cobertura: pesoTotal == 0 ? 0.0 : pesoDominado / pesoTotal,
      coberturaTocada: pesoTotal == 0 ? 0.0 : pesoTocado / pesoTotal,
    );
  }

  /// Cobertura de todas as matérias ativas, numa passada só.
  static List<CoberturaMateria> coberturaPorMateria(
    List<Materia> materias,
    List<Topico> topicos,
    List<RegistroHora> registros, {
    DateTime? referencia,
  }) {
    final todasLinhas = linhas(topicos, registros, referencia: referencia);
    final porMateria = <String, List<LinhaEdital>>{};
    for (final l in todasLinhas) {
      (porMateria[l.topico.materiaId] ??= []).add(l);
    }
    return [
      for (final m in materias)
        if (!m.arquivada) cobertura(m, porMateria[m.id] ?? const []),
    ];
  }

  /// Cobertura do edital INTEIRO, ponderada pelo peso da matéria × peso do
  /// tópico. Null quando não há tópico cadastrado — sem edital não há o que
  /// medir, e devolver 0% acusaria o usuário de um atraso que não existe.
  static double? coberturaGeral(
    List<Materia> materias,
    List<Topico> topicos,
    List<RegistroHora> registros, {
    DateTime? referencia,
  }) {
    final pesoMateria = {for (final m in materias) m.id: m.peso};
    final ativas = {
      for (final m in materias)
        if (!m.arquivada) m.id,
    };
    var total = 0.0;
    var dominado = 0.0;
    for (final l in linhas(topicos, registros, referencia: referencia)) {
      if (!ativas.contains(l.topico.materiaId)) continue;
      final peso = (pesoMateria[l.topico.materiaId] ?? 1) * l.topico.peso;
      total += peso;
      if (l.situacao == SituacaoTopico.dominado) dominado += peso;
    }
    if (total == 0) return null;
    return dominado / total;
  }

  /// Buracos do edital: tópicos intocados ou frágeis, ordenados pelo custo de
  /// deixá-los como estão (peso da matéria × peso do tópico), maior primeiro.
  /// É a lista de "o que estudar em seguida" derivada do edital, não do humor.
  static List<({LinhaEdital linha, Materia materia, int prioridade})> buracos(
    List<Materia> materias,
    List<Topico> topicos,
    List<RegistroHora> registros, {
    DateTime? referencia,
    int? limite,
  }) {
    final porId = {for (final m in materias) m.id: m};
    final lista = [
      for (final l in linhas(topicos, registros, referencia: referencia))
        if (l.situacao == SituacaoTopico.intocado ||
            l.situacao == SituacaoTopico.fragil)
          if (porId[l.topico.materiaId] != null &&
              !porId[l.topico.materiaId]!.arquivada)
            (
              linha: l,
              materia: porId[l.topico.materiaId]!,
              prioridade:
                  porId[l.topico.materiaId]!.peso * l.topico.peso,
            ),
    ]..sort((a, b) {
      final porPrioridade = b.prioridade.compareTo(a.prioridade);
      if (porPrioridade != 0) return porPrioridade;
      // Intocado dói mais que frágil no mesmo peso: zero contato é risco maior
      // que contato insuficiente.
      final porSituacao = (a.linha.situacao == SituacaoTopico.intocado ? 0 : 1)
          .compareTo(b.linha.situacao == SituacaoTopico.intocado ? 0 : 1);
      if (porSituacao != 0) return porSituacao;
      return a.linha.topico.nome.toLowerCase().compareTo(
        b.linha.topico.nome.toLowerCase(),
      );
    });
    if (limite == null || limite >= lista.length) return lista;
    return lista.take(limite).toList();
  }

  /// Contagem por situação sobre o edital ativo — base do donut de cobertura.
  static Map<SituacaoTopico, int> distribuicao(
    List<Materia> materias,
    List<Topico> topicos,
    List<RegistroHora> registros, {
    DateTime? referencia,
  }) {
    final ativas = {
      for (final m in materias)
        if (!m.arquivada) m.id,
    };
    final contagem = {for (final s in SituacaoTopico.values) s: 0};
    for (final l in linhas(topicos, registros, referencia: referencia)) {
      if (!ativas.contains(l.topico.materiaId)) continue;
      contagem[l.situacao] = contagem[l.situacao]! + 1;
    }
    return contagem;
  }
}
