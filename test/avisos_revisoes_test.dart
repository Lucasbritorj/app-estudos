import 'package:flutter_test/flutter_test.dart';
import 'package:app_estudos/core/notificacoes/avisos_revisoes.dart';
import 'package:app_estudos/data/models/revisao.dart';

void main() {
  test('avisa só após hora local e ignora concluída/futura', () {
    final hoje = DateTime(2026, 9, 7);
    Revisao r(String id, DateTime data, {bool feita = false}) => Revisao(
      id: id,
      materiaId: 'm',
      titulo: id,
      dataAgendada: data,
      intervaloDias: 1,
      feita: feita,
    );
    final itens = [
      r('ontem', DateTime(2026, 9, 6)),
      r('hoje', hoje),
      r('feita', hoje, feita: true),
      r('amanha', DateTime(2026, 9, 8)),
    ];
    expect(
      revisoesParaAvisar(itens, DateTime(2026, 9, 7, 8), 9).map((r) => r.id),
      ['ontem'],
    );
    expect(
      revisoesParaAvisar(itens, DateTime(2026, 9, 7, 9), 9).map((r) => r.id),
      ['ontem', 'hoje'],
    );
  });
}
