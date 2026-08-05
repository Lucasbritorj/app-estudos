// ignore_for_file: avoid_print
/// Massa fake determinística do UAT — sem random sem seed e sem DateTime.now():
/// tudo ancorado em [hoje] para o resultado ser reproduzível.
library;

import 'dart:math';

import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/topico.dart';

/// Âncora temporal do UAT (quarta-feira).
final hoje = DateTime(2026, 7, 29);

DateTime dias(int n) => DateTime(hoje.year, hoje.month, hoje.day + n);

class Massa {
  final Ambiente ambiente;
  final List<Materia> materias;
  final List<Topico> topicos;
  final List<Aula> aulas;
  final List<RegistroHora> registros;
  final List<Revisao> revisoes;
  final Map<int, int> planejamento;

  Massa({
    required this.ambiente,
    required this.materias,
    required this.topicos,
    required this.aulas,
    required this.registros,
    required this.revisoes,
    required this.planejamento,
  });

  Materia porNome(String nome) => materias.firstWhere((m) => m.nome == nome);
  Topico topico(String nome) => topicos.firstWhere((t) => t.nome == nome);
}

Massa construirMassa() {
  final ambiente = Ambiente(
    id: 'amb-trf',
    nome: 'Concurso TRF 2026',
    corSlot: 0,
    criadoEm: dias(-90),
    dataProva: dias(109),
  );

  Materia m(String id, String nome, int slot, int peso, int intimidade) =>
      Materia(
        id: id,
        nome: nome,
        ambienteId: ambiente.id,
        corSlot: slot,
        peso: peso,
        intimidade: intimidade,
        criadaEm: dias(-90),
      );

  final materias = [
    m('mat-port', 'Portugues', 0, 3, 3),
    m('mat-const', 'Direito Constitucional', 1, 5, 2),
    m('mat-adm', 'Direito Administrativo', 2, 4, 2),
    m('mat-rlm', 'Raciocinio Logico', 3, 2, 4),
    m('mat-info', 'Informatica', 4, 1, 5),
  ];

  final topicos = <Topico>[
    const Topico(id: 'top-df', materiaId: 'mat-const', nome: 'Direitos Fundamentais', peso: 5),
    const Topico(id: 'top-art5', materiaId: 'mat-const', parentId: 'top-df', nome: 'Art. 5o', peso: 5),
    const Topico(id: 'top-remedios', materiaId: 'mat-const', parentId: 'top-df', nome: 'Remedios constitucionais', peso: 3, prerequisitos: ['top-art5']),
    const Topico(id: 'top-org', materiaId: 'mat-const', nome: 'Organizacao do Estado', peso: 4),
    const Topico(id: 'top-lic', materiaId: 'mat-adm', nome: 'Licitacoes', peso: 5),
    const Topico(id: 'top-atos', materiaId: 'mat-adm', nome: 'Atos administrativos', peso: 4),
    const Topico(id: 'top-crase', materiaId: 'mat-port', nome: 'Crase', peso: 2),
    const Topico(id: 'top-conc', materiaId: 'mat-port', nome: 'Concordancia', peso: 4),
    const Topico(id: 'top-prob', materiaId: 'mat-rlm', nome: 'Probabilidade', peso: 3),
  ];

  final aulas = [
    Aula(id: 'aula-lic00', materiaId: 'mat-adm', nome: 'Aula 00 - Licitacoes', paginasTotais: 80, paginasLidas: 80, concluida: true, dataConclusao: dias(-30)),
    Aula(id: 'aula-lic01', materiaId: 'mat-adm', nome: 'Aula 01 - Contratos', paginasTotais: 60, paginasLidas: 25),
    Aula(id: 'aula-df00', materiaId: 'mat-const', nome: 'Aula 00 - Direitos Fundamentais', paginasTotais: 100, paginasLidas: 100, concluida: true, dataConclusao: dias(-20)),
  ];

  final rnd = Random(42);
  final registros = <RegistroHora>[];
  final planoDia = <({String mat, String top, bool questoes})>[
    (mat: 'mat-const', top: 'top-art5', questoes: true),
    (mat: 'mat-adm', top: 'top-lic', questoes: true),
    (mat: 'mat-port', top: 'top-conc', questoes: false),
    (mat: 'mat-rlm', top: 'top-prob', questoes: true),
    (mat: 'mat-const', top: 'top-org', questoes: false),
    (mat: 'mat-adm', top: 'top-atos', questoes: true),
    (mat: 'mat-port', top: 'top-crase', questoes: true),
  ];

  var n = 0;
  for (var d = -59; d <= 0; d++) {
    final data = dias(d);
    // Domingo descansa; furos deliberados em d=-12 e d=-3 (congelamento/recuperacao).
    if (data.weekday == DateTime.sunday) continue;
    if (d == -12 || d == -3) continue;
    final blocos = 1 + rnd.nextInt(2);
    for (var b = 0; b < blocos; b++) {
      final p = planoDia[(n + b) % planoDia.length];
      final minutos = 35 + rnd.nextInt(60);
      final questoes = p.questoes ? 10 + rnd.nextInt(21) : null;
      final taxa = 0.55 + 0.30 * ((d + 59) / 59.0);
      final acertos = questoes == null ? null : (questoes * taxa).round().clamp(0, questoes);
      registros.add(
        RegistroHora(
          id: 'reg-${n + b}',
          data: DateTime(data.year, data.month, data.day, 20, 0),
          materiaId: p.mat,
          topicoId: p.top,
          aulaId: p.mat == 'mat-adm' && p.top == 'top-lic' ? 'aula-lic00' : null,
          tipo: p.questoes ? TipoEstudo.pratica : TipoEstudo.teoria,
          tarefa: 'Sessao ${n + b}',
          minutos: minutos,
          paginaInicial: p.questoes ? null : 1 + (n * 3),
          paginaFinal: p.questoes ? null : 1 + (n * 3) + 12,
          questoes: questoes,
          acertos: acertos,
        ),
      );
    }
    n += blocos;
  }

  final revisoes = <Revisao>[
    Revisao(id: 'rev-atr-1', materiaId: 'mat-const', topicoId: 'top-art5', titulo: 'Art. 5o (7d)', dataAgendada: dias(-4), intervaloDias: 7),
    Revisao(id: 'rev-atr-2', materiaId: 'mat-adm', topicoId: 'top-lic', aulaId: 'aula-lic00', titulo: 'Aula 00 - Licitacoes (15d)', dataAgendada: dias(-1), intervaloDias: 15, estabilidade: 15.0, dificuldade: 5.0),
    Revisao(id: 'rev-hoje-1', materiaId: 'mat-port', topicoId: 'top-conc', titulo: 'Concordancia (7d)', dataAgendada: hoje, intervaloDias: 7),
    Revisao(id: 'rev-hoje-2', materiaId: 'mat-rlm', topicoId: 'top-prob', titulo: 'Probabilidade (30d)', dataAgendada: hoje, intervaloDias: 30, estabilidade: 30.0, dificuldade: 4.0),
    Revisao(id: 'rev-fut-1', materiaId: 'mat-const', topicoId: 'top-org', titulo: 'Organizacao do Estado (15d)', dataAgendada: dias(3), intervaloDias: 15),
    Revisao(id: 'rev-fut-2', materiaId: 'mat-adm', topicoId: 'top-atos', titulo: 'Atos administrativos (7d)', dataAgendada: dias(6), intervaloDias: 7),
    Revisao(id: 'rev-fut-3', materiaId: 'mat-port', topicoId: 'top-crase', titulo: 'Crase (60d)', dataAgendada: dias(41), intervaloDias: 60, estabilidade: 60.0, dificuldade: 6.0),
    for (var i = 0; i < 4; i++)
      Revisao(id: 'rev-feita-$i', materiaId: 'mat-const', topicoId: 'top-art5', titulo: 'Art. 5o (7d)', dataAgendada: dias(-30 + i * 3), intervaloDias: 7, feita: true, dataConclusao: dias(-30 + i * 3)),
  ];

  return Massa(
    ambiente: ambiente,
    materias: materias,
    topicos: topicos,
    aulas: aulas,
    registros: registros,
    revisoes: revisoes,
    planejamento: {1: 90, 2: 90, 3: 90, 4: 90, 5: 90, 6: 90, 7: 0},
  );
}

// ---------------------------------------------------------------------------
// Massa longa — 4 meses
// ---------------------------------------------------------------------------

/// Seed própria: a massa longa NÃO é superconjunto de [construirMassa]. O
/// gerador consome o `Random` na ordem do laço, então mudar o horizonte muda
/// toda a sequência. Seed distinta deixa isso explícito em vez de sugerir
/// continuidade que não existe.
const seedMassaLonga = 4242;

/// Horizonte da massa longa. Com a âncora [hoje] (2026-07-29) cobre
/// 2026-04-01 a 2026-07-29 — quatro meses-calendário, três comparativos MoM
/// com base não-zero e um com base zero (abril, que não tem março).
const diasMassaLonga = 120;

/// Minutos das sessões-token: abaixo de `StatsService.pisoMinutosStreak` (15).
/// A massa curta não tem UM dia abaixo do piso — o mínimo por sessão dela é 35
/// —, então nenhum teste sobre ela consegue provar que o piso REJEITA um dia.
/// Estes dias são a contraprova.
const minutosTokenMassaLonga = 8;

/// Massa de ~4 meses para métricas que precisam de horizonte: MoM encadeado,
/// streak longo com furos, piso rejeitando dia fraco.
///
/// Reaproveita ambiente, matérias, tópicos e aulas de [construirMassa] — só os
/// registros e as revisões são outros. Um gerador, duas janelas.
Massa construirMassaLonga() {
  final base = construirMassa();
  final rnd = Random(seedMassaLonga);
  final registros = <RegistroHora>[];
  final plano = <({String mat, String top, bool questoes})>[
    (mat: 'mat-const', top: 'top-art5', questoes: true),
    (mat: 'mat-adm', top: 'top-lic', questoes: true),
    (mat: 'mat-port', top: 'top-conc', questoes: false),
    (mat: 'mat-rlm', top: 'top-prob', questoes: true),
    (mat: 'mat-const', top: 'top-org', questoes: false),
    (mat: 'mat-adm', top: 'top-atos', questoes: true),
    (mat: 'mat-port', top: 'top-crase', questoes: true),
  ];

  var n = 0;
  for (var d = -(diasMassaLonga - 1); d <= 0; d++) {
    final data = dias(d);
    if (data.weekday == DateTime.sunday) continue;
    // Furo a cada 23 dias: quebra o streak algumas vezes na janela.
    if (d % 23 == 0 && d != 0) continue;
    // Dia-token a cada 17: um único bloco curto, abaixo do piso.
    final token = d % 17 == 0 && d != 0;
    final blocos = token ? 1 : 1 + rnd.nextInt(2);
    for (var b = 0; b < blocos; b++) {
      final p = plano[(n + b) % plano.length];
      final minutos = token ? minutosTokenMassaLonga : 35 + rnd.nextInt(60);
      final questoes = (p.questoes && !token) ? 10 + rnd.nextInt(21) : null;
      // Taxa sobe de 55% para 85% ao longo da janela — evolução, não ruído.
      final taxa =
          0.55 + 0.30 * ((d + diasMassaLonga - 1) / (diasMassaLonga - 1));
      final acertos = questoes == null
          ? null
          : (questoes * taxa).round().clamp(0, questoes);
      registros.add(
        RegistroHora(
          id: 'long-${n + b}',
          data: DateTime(data.year, data.month, data.day, 20, 0),
          materiaId: p.mat,
          topicoId: p.top,
          tipo: p.questoes && !token ? TipoEstudo.pratica : TipoEstudo.teoria,
          tarefa: 'Sessao ${n + b}',
          minutos: minutos,
          questoes: questoes,
          acertos: acertos,
        ),
      );
    }
    n += blocos;
  }

  final revisoes = <Revisao>[
    Revisao(id: 'lrev-atr-1', materiaId: 'mat-const', topicoId: 'top-art5', titulo: 'Art. 5o', dataAgendada: dias(-5), intervaloDias: 7),
    Revisao(id: 'lrev-atr-2', materiaId: 'mat-adm', topicoId: 'top-lic', titulo: 'Licitacoes', dataAgendada: dias(-2), intervaloDias: 15),
    Revisao(id: 'lrev-hoje', materiaId: 'mat-port', topicoId: 'top-conc', titulo: 'Concordancia', dataAgendada: hoje, intervaloDias: 7),
    for (var i = 0; i < 6; i++)
      Revisao(id: 'lrev-fut-$i', materiaId: 'mat-rlm', topicoId: 'top-prob', titulo: 'Probabilidade $i', dataAgendada: dias(2 + i * 5), intervaloDias: 15),
    for (var i = 0; i < 12; i++)
      Revisao(id: 'lrev-feita-$i', materiaId: 'mat-const', topicoId: 'top-art5', titulo: 'Art. 5o', dataAgendada: dias(-110 + i * 8), intervaloDias: 7, feita: true, dataConclusao: dias(-110 + i * 8)),
  ];

  return Massa(
    ambiente: base.ambiente,
    materias: base.materias,
    topicos: base.topicos,
    aulas: base.aulas,
    registros: registros,
    revisoes: revisoes,
    planejamento: base.planejamento,
  );
}
