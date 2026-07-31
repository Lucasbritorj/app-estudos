// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import '_massa_fake.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/revisao_service.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:app_estudos/domain/gamificacao_service.dart';
import 'package:app_estudos/domain/dominio_service.dart';

/// Transcricao FIEL de RevisaoUseCase.concluir
/// (lib/application/revisao_use_case.dart:37-115), sem Riverpod/Hive:
/// mesma ordem de efeitos, mesmos parametros, mesmo fallback de taxa.
class Mundo {
  List<RegistroHora> registros;
  List<Revisao> revisoes;
  var seq = 0;
  Mundo(this.registros, this.revisoes);

  ({Revisao? proxima, double? taxaAcerto, bool reforco}) concluir(
    Revisao revisao, {
    int? questoes,
    int? acertos,
    int minutos = 0, // <- default do use case; revisoes_screen NAO passa minutos
    required DateTime agora,
  }) {
    if (questoes != null && questoes > 0 && acertos != null) {
      registros = [
        ...registros,
        RegistroHora(
          id: 'rev-reg-${seq++}',
          data: agora,
          materiaId: revisao.materiaId,
          topicoId: revisao.topicoId,
          tipo: TipoEstudo.pratica,
          tarefa: 'Revisão: ${revisao.titulo}',
          minutos: minutos,
          questoes: questoes,
          acertos: acertos,
        ),
      ];
    }
    final feita = revisao.copyWith(feita: true, dataConclusao: agora);
    revisoes = [
      for (final r in revisoes)
        if (r.id != revisao.id) r,
      feita,
    ];

    final taxaDaRevisao = (questoes != null && questoes > 0 && acertos != null)
        ? (acertos.clamp(0, questoes)) / questoes
        : null;
    final taxaJanela = RevisaoService.taxaAcertoDe(registros,
        materiaId: revisao.materiaId, topicoId: revisao.topicoId);
    final taxa = taxaDaRevisao ?? taxaJanela;
    final agendada = DateTime(
        revisao.dataAgendada.year, revisao.dataAgendada.month, revisao.dataAgendada.day);
    final passo = RevisaoService.proximoPassoFsrs(
      estabilidade: revisao.estabilidade,
      dificuldade: revisao.dificuldade,
      intervaloAtual: revisao.intervaloDias,
      diasDeAtraso:
          DateTime(agora.year, agora.month, agora.day).difference(agendada).inDays,
      taxaAcerto: taxa,
    );
    if (passo == null) return (proxima: null, taxaAcerto: taxa, reforco: false);

    final tituloBase = revisao.titulo.replaceFirst(RegExp(r' \((\d+d|reforço)\)$'), '');
    final proxima = Revisao(
      id: 'rev-prox-${seq++}',
      materiaId: revisao.materiaId,
      topicoId: revisao.topicoId,
      aulaId: revisao.aulaId,
      titulo: passo.reforco ? '$tituloBase (reforço)' : '$tituloBase (${passo.dias}d)',
      dataAgendada: DateTime(agora.year, agora.month, agora.day + passo.dias),
      intervaloDias: passo.intervalo,
      estabilidade: passo.estabilidade,
      dificuldade: passo.dificuldade,
    );
    revisoes = [...revisoes, proxima];
    return (proxima: proxima, taxaAcerto: taxa, reforco: passo.reforco);
  }
}

String snapshot(Mundo m, DateTime agora) {
  final xp = GamificacaoService.xpDetalhado(m.registros, m.revisoes, agora);
  final atrasadas = m.revisoes.where((r) => r.statusEm(agora) == RevisaoStatus.atrasada).length;
  final resumo = StatsService.resumoDiario(m.registros);
  return 'min_hoje=${StatsService.minutosNoDia(m.registros, agora)} '
      'questoes=${StatsService.desempenhoPorMateria(m.registros).values.fold<int>(0, (s, e) => s + e.questoes)} '
      'taxa=${StatsService.taxaAcertoGeral(m.registros)?.toStringAsFixed(4)} '
      'atrasadas=$atrasadas XP=${xp.total}(rev=${xp.bonusRevisoes}) '
      'sessoes=${m.registros.length} minimo_diario=${resumo.minimo}';
}

void main() {
  final agora = DateTime(2026, 7, 29, 21, 30);

  test('UAT-H1 concluir SEM informacoes: dashboard nao registra hora nem questao', () {
    final massa = construirMassa();
    final m = Mundo([...massa.registros], [...massa.revisoes]);
    print('[H1] antes : ${snapshot(m, agora)}');
    final r = m.concluir(m.revisoes.firstWhere((x) => x.id == 'rev-atr-1'), agora: agora);
    print('[H1] depois: ${snapshot(m, agora)}');
    print('[H1] proxima=${r.proxima?.titulo} em ${r.proxima?.dataAgendada} '
        'taxa usada=${r.taxaAcerto?.toStringAsFixed(4)} (fallback janela) reforco=${r.reforco}');
    expect(m.registros.length, massa.registros.length, reason: 'nenhuma sessao criada');
    expect(r.taxaAcerto, isNotNull, reason: 'usa a janela das ultimas 10 sessoes do topico');
    expect(r.proxima, isNotNull);
  });

  test('UAT-H2 concluir COM informacoes: cria sessao pratica de 0 min', () {
    final massa = construirMassa();
    final m = Mundo([...massa.registros], [...massa.revisoes]);
    final antesMin = StatsService.minutosNoDia(m.registros, agora);
    final antesMinimo = StatsService.resumoDiario(m.registros).minimo;
    final r = m.concluir(m.revisoes.firstWhere((x) => x.id == 'rev-hoje-1'),
        questoes: 20, acertos: 19, agora: agora);
    final nova = m.registros.last;
    print('[H2] sessao criada: tarefa="${nova.tarefa}" minutos=${nova.minutos} '
        'q=${nova.questoes} a=${nova.acertos} tipo=${nova.tipo.name}');
    print('[H2] min_hoje $antesMin -> ${StatsService.minutosNoDia(m.registros, agora)} | '
        'minimo_diario $antesMinimo -> ${StatsService.resumoDiario(m.registros).minimo}');
    print('[H2] taxa da revisao=${r.taxaAcerto} (primaria, ignora a janela) '
        'proxima=${r.proxima?.titulo}');
    expect(nova.minutos, 0, reason: 'revisoes_screen nao pergunta minutos');
    expect(r.taxaAcerto, closeTo(0.95, 1e-12));
    expect(StatsService.minutosNoDia(m.registros, agora), antesMin,
        reason: 'horas nao se movem');
    expect(StatsService.desempenhoPorMateria(m.registros)['mat-port']!.questoes,
        greaterThan(0));
  });

  test('UAT-H3 lapso na revisao (com informacao ruim) agenda reforco', () {
    final massa = construirMassa();
    final m = Mundo([...massa.registros], [...massa.revisoes]);
    final r = m.concluir(m.revisoes.firstWhere((x) => x.id == 'rev-hoje-2'),
        questoes: 20, acertos: 8, agora: agora);
    print('[H3] taxa=${r.taxaAcerto} reforco=${r.reforco} '
        'proxima="${r.proxima?.titulo}" em ${r.proxima?.dataAgendada} '
        'S=${r.proxima?.estabilidade} D=${r.proxima?.dificuldade}');
    expect(r.reforco, isTrue);
    expect(r.proxima!.titulo.endsWith('(reforço)'), isTrue);
    expect(r.proxima!.estabilidade, closeTo(12.0, 1e-9), reason: 'S 30 -> 40%');
  });

  test('UAT-H4 colocar TODA a fila em dia sem informacoes: efeito no dashboard', () {
    final massa = construirMassa();
    final m = Mundo([...massa.registros], [...massa.revisoes]);
    print('[H4] antes : ${snapshot(m, agora)}');
    final fila = m.revisoes
        .where((r) => !r.feita && r.statusEm(agora) != RevisaoStatus.aFazer)
        .toList();
    final vencendoHoje = m.revisoes
        .where((r) => !r.feita &&
            StatsService.dataSemHora(r.dataAgendada) == StatsService.dataSemHora(agora))
        .toList();
    for (final r in [...fila, ...vencendoHoje]) {
      m.concluir(r, agora: agora);
    }
    print('[H4] depois: ${snapshot(m, agora)}');
    final atrasadas = m.revisoes.where((r) => r.statusEm(agora) == RevisaoStatus.atrasada).length;
    final badge = GamificacaoService.badges(m.registros, m.revisoes, agora)
        .firstWhere((b) => b.id == 'revisoes-em-dia');
    print('[H4] atrasadas=$atrasadas badge "Em dia" conquistada=${badge.conquistada}');
    print('[H4] >>> TETO DIARIO: ${GamificacaoService.maxRevisoesComBonusPorDia} revisoes com bonus; '
        '${fila.length + vencendoHoje.length} concluidas no mesmo dia');
    expect(atrasadas, 0);
    expect(badge.conquistada, isTrue);
  });

  test('UAT-H5 teto diario de bonus: 4 conclusoes no mesmo dia pagam 3', () {
    final base = [
      for (var i = 0; i < 4; i++)
        Revisao(id: 'r$i', materiaId: 'm', titulo: 't$i', dataAgendada: hoje,
            intervaloDias: 7, feita: true, dataConclusao: agora),
    ];
    final xp = GamificacaoService.bonusRevisoes(base);
    print('[H5] 4 revisoes no mesmo dia -> bonus=$xp '
        '(teto ${GamificacaoService.maxRevisoesComBonusPorDia} x ${GamificacaoService.xpPorRevisaoFeita})');
    expect(xp, 150);
    final espalhadas = [
      for (var i = 0; i < 4; i++)
        Revisao(id: 'e$i', materiaId: 'm', titulo: 't$i', dataAgendada: hoje,
            intervaloDias: 7, feita: true, dataConclusao: dias(-i)),
    ];
    print('[H5] 4 revisoes em 4 dias -> bonus=${GamificacaoService.bonusRevisoes(espalhadas)}');
    expect(GamificacaoService.bonusRevisoes(espalhadas), 200);
  });

  test('UAT-H6 cadeia completa de um topico: 6 conclusoes seguidas com desempenho real', () {
    final massa = construirMassa();
    final m = Mundo([...massa.registros], [...massa.revisoes]);
    var atual = m.revisoes.firstWhere((x) => x.id == 'rev-fut-1');
    var dia = DateTime(2026, 8, 1, 20, 0);
    final trilha = <String>[];
    for (var i = 0; i < 6; i++) {
      final r = m.concluir(atual, questoes: 20, acertos: 18, agora: dia);
      if (r.proxima == null) {
        trilha.add('FIM');
        break;
      }
      trilha.add('${r.proxima!.intervaloDias}d');
      atual = r.proxima!;
      dia = DateTime(atual.dataAgendada.year, atual.dataAgendada.month,
          atual.dataAgendada.day, 20, 0);
    }
    print('[H6] cadeia com 90% de acerto: ${trilha.join(" -> ")}');
    print('[H6] revisoes no banco=${m.revisoes.length} '
        'sessoes criadas=${m.registros.length - massa.registros.length}');
    final elo = DominioService.dominioDoTopico(m.registros, 'top-org', referencia: dia);
    print('[H6] Elo do topico apos a cadeia=${elo?.dominio.toStringAsFixed(4)} '
        'q=${elo?.questoes} confiavel=${elo?.confiavel}');
    expect(trilha.last, anyOf('FIM', matches(r'^\d+d$')));
  });

  test('UAT-H7 BORDA: concluir revisao adiantada nao encurta o intervalo', () {
    final massa = construirMassa();
    final m = Mundo([...massa.registros], [...massa.revisoes]);
    final futura = m.revisoes.firstWhere((x) => x.id == 'rev-fut-3'); // 60d, +41d
    // Acerto alto de proposito: sem informacao a taxa da janela do topico fica
    // em ~70% (<75%) e o resultado seria LAPSO, nao o freio de antecipacao.
    final r = m.concluir(futura, questoes: 20, acertos: 20, agora: agora);
    final diasAteProxima = StatsService.dataSemHora(r.proxima!.dataAgendada)
        .difference(StatsService.dataSemHora(agora)).inDays;
    print('[H7] concluida ${StatsService.dataSemHora(futura.dataAgendada).difference(StatsService.dataSemHora(agora)).inDays}d '
        'antes do vencimento -> proxima em ${diasAteProxima}d (S=${r.proxima!.estabilidade!.toStringAsFixed(2)})');
    final diasDeAtraso = StatsService.dataSemHora(agora)
        .difference(StatsService.dataSemHora(futura.dataAgendada))
        .inDays;
    print('[H7] diasDeAtraso passado ao FSRS=$diasDeAtraso '
        '(instante cru daria ${agora.difference(StatsService.dataSemHora(futura.dataAgendada)).inDays})');
    expect(diasDeAtraso, -41, reason: 'REGRESSAO: antecipacao inteira, sem truncar 1 dia');
    print('[H7] reforco=${r.reforco} taxa=${r.taxaAcerto}');
    expect(r.reforco, isFalse);
    expect(diasAteProxima, greaterThanOrEqualTo(60), reason: 'freio de antecipacao');

    // Contraprova: MESMA revisao concluida sem informacao cai em lapso pela
    // janela de desempenho do topico (~70%) — nao pelo freio.
    final m2 = Mundo([...construirMassa().registros], [...construirMassa().revisoes]);
    final semInfo = m2.concluir(
        m2.revisoes.firstWhere((x) => x.id == 'rev-fut-3'), agora: agora);
    print('[H7] contraprova sem info: taxa=${semInfo.taxaAcerto?.toStringAsFixed(4)} '
        'reforco=${semInfo.reforco} S=${semInfo.proxima!.estabilidade} '
        'proxima=${semInfo.proxima!.intervaloDias}d');
    expect(semInfo.reforco, isTrue);
  });

  test('UAT-H8 BORDA: revisao com titulo sem sufixo nao acumula parenteses', () {
    final massa = construirMassa();
    final m = Mundo([...massa.registros], [...massa.revisoes]);
    var atual = Revisao(id: 'nu', materiaId: 'mat-port', topicoId: 'top-crase',
        titulo: 'Crase', dataAgendada: hoje, intervaloDias: 7);
    m.revisoes = [...m.revisoes, atual];
    final titulos = <String>[];
    for (var i = 0; i < 3; i++) {
      final r = m.concluir(atual, agora: agora);
      if (r.proxima == null) break;
      titulos.add(r.proxima!.titulo);
      atual = r.proxima!;
    }
    print('[H8] titulos=${titulos.join(" | ")}');
    expect(titulos.every((t) => RegExp(r'^Crase \((\d+d|reforço)\)$').hasMatch(t)), isTrue);
  });
}
