import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/quests_service.dart';
import 'package:flutter_test/flutter_test.dart';

RegistroHora reg(DateTime data, String materiaId, {String? topicoId}) =>
    RegistroHora(
      id: '${data.toIso8601String()}-$materiaId-$topicoId',
      data: data,
      materiaId: materiaId,
      topicoId: topicoId,
      minutos: 30,
    );

Revisao rev(String id,
        {required DateTime agendada, bool feita = false,
        DateTime? conclusao}) =>
    Revisao(
      id: id,
      materiaId: 'm1',
      titulo: id,
      dataAgendada: agendada,
      intervaloDias: 7,
      feita: feita,
      dataConclusao: conclusao,
    );

void main() {
  final hoje = DateTime(2026, 7, 15);

  QuestDia porId(List<QuestDia> quests, String id) =>
      quests.firstWhere((q) => q.id == id);

  test('com matéria em déficit: quest da matéria, concluída por sessão nela',
      () {
    final pendente = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [reg(hoje, 'm2')],
      revisoes: [],
      materiaDeficitId: 'm1',
      materiaDeficitNome: 'Direito',
      temTopicos: false,
    );
    expect(porId(pendente, 'estudar-deficit').concluida, false);

    final feita = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [reg(hoje, 'm1')],
      revisoes: [],
      materiaDeficitId: 'm1',
      materiaDeficitNome: 'Direito',
      temTopicos: false,
    );
    expect(porId(feita, 'estudar-deficit').concluida, true);
    expect(porId(feita, 'estudar-deficit').titulo, contains('Direito'));
  });

  test('sem cronograma: quest genérica de estudar hoje', () {
    final quests = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [],
      revisoes: [],
      temTopicos: false,
    );
    expect(porId(quests, 'estudar-hoje').concluida, false);
    expect(quests.any((q) => q.id == 'estudar-deficit'), false);
  });

  test('revisões: alvo = feitas hoje + pendentes até hoje, teto 3; '
      'futuras não contam', () {
    final quests = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [],
      revisoes: [
        rev('atrasada', agendada: DateTime(2026, 7, 1)),
        rev('de-hoje', agendada: hoje),
        rev('futura', agendada: DateTime(2026, 7, 20)),
        rev('feita-hoje',
            agendada: DateTime(2026, 7, 10), feita: true, conclusao: hoje),
        rev('feita-ontem',
            agendada: DateTime(2026, 7, 8),
            feita: true,
            conclusao: DateTime(2026, 7, 14)),
      ],
      temTopicos: false,
    );
    final q = porId(quests, 'revisoes-do-dia');
    expect(q.alvo, 3); // 1 feita hoje + 2 pendentes (atrasada + de hoje)
    expect(q.atual, 1);
    expect(q.concluida, false);
  });

  test('alvo não encolhe ao concluir: 3 feitas hoje e 0 pendentes = 3/3', () {
    final quests = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [],
      revisoes: [
        for (var i = 0; i < 3; i++)
          rev('r$i',
              agendada: DateTime(2026, 7, 10), feita: true, conclusao: hoje),
      ],
      temTopicos: false,
    );
    final q = porId(quests, 'revisoes-do-dia');
    expect(q.alvo, 3);
    expect(q.concluida, true);
  });

  test('sem revisões no sistema: quest de revisão nem aparece', () {
    final quests = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [],
      revisoes: [],
      temTopicos: false,
    );
    expect(quests.any((q) => q.id == 'revisoes-do-dia'), false);
  });

  test('quest do mapa só com tópicos; concluída por sessão com tópico', () {
    final sem = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [reg(hoje, 'm1')],
      revisoes: [],
      temTopicos: false,
    );
    expect(sem.any((q) => q.id == 'topico-mapa'), false);

    final quests = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [reg(hoje, 'm1', topicoId: 't1')],
      revisoes: [],
      temTopicos: true,
    );
    expect(porId(quests, 'topico-mapa').concluida, true);
  });

  test('sessão de ontem não conta para hoje', () {
    final quests = QuestsService.questsDoDia(
      hoje: hoje,
      registros: [reg(DateTime(2026, 7, 14), 'm1', topicoId: 't1')],
      revisoes: [],
      materiaDeficitId: 'm1',
      materiaDeficitNome: 'Direito',
      temTopicos: true,
    );
    expect(porId(quests, 'estudar-deficit').concluida, false);
    expect(porId(quests, 'topico-mapa').concluida, false);
  });
}
