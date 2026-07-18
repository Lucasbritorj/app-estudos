import 'dart:io';

import 'package:app_estudos/application/revisao_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Conclusão de revisão com desempenho (2b do plano de melhorias): o
/// resultado informado na hora vira sessão prática comum ANTES do cálculo
/// FSRS — uma só fonte de verdade de acerto; o intervalo responde à taxa.
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_rev_desemp_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrar();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Revisao pendente() => Revisao(
    id: 'rev1',
    materiaId: 'm1',
    topicoId: 't1',
    titulo: 'AFO — Orçamento (7d)',
    dataAgendada: DateTime.now(),
    intervaloDias: 7,
    estabilidade: 7,
    dificuldade: 5,
  );

  test('desempenho informado vira sessão prática e alimenta o FSRS', () async {
    final useCase = container.read(revisaoUseCaseProvider);
    final resultado = await useCase.concluir(
      pendente(),
      questoes: 10,
      acertos: 4,
    );

    final registros = container.read(registrosProvider);
    expect(registros, hasLength(1));
    final registro = registros.single;
    expect(registro.tipo, TipoEstudo.pratica);
    expect(registro.materiaId, 'm1');
    expect(registro.topicoId, 't1');
    expect(registro.questoes, 10);
    expect(registro.acertos, 4);
    expect(registro.tarefa, contains('Revisão'));

    // 40% < 75%: o passo seguinte tem que ser reforço curto.
    expect(resultado.taxaAcerto, closeTo(0.4, 0.001));
    expect(resultado.reforco, isTrue);
  });

  test('sem desempenho, nada é registrado e a cadeia espaça pleno', () async {
    final useCase = container.read(revisaoUseCaseProvider);
    final resultado = await useCase.concluir(pendente());

    expect(container.read(registrosProvider), isEmpty);
    expect(resultado.taxaAcerto, isNull);
    expect(resultado.reforco, isFalse);
    expect(resultado.proxima, isNotNull);
    expect(resultado.proxima!.intervaloDias, greaterThan(7));
  });

  test('questões sem acertos informados não cria registro', () async {
    final useCase = container.read(revisaoUseCaseProvider);
    await useCase.concluir(pendente(), questoes: 10);
    expect(container.read(registrosProvider), isEmpty);
  });
}
