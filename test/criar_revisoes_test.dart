import 'dart:io';

import 'package:app_estudos/application/revisao_use_case.dart';
import 'package:app_estudos/application/sessao_estudo_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Cascata concluir aula → nasce a Revisão 1, e a linhagem da cadeia
/// (aulaId) sobrevive às conclusões seguintes. Exercita o fio inteiro sobre
/// Hive real via casos de uso. Notificações são no-op em teste
/// (NotificacoesService._pronto == false), então não tocam o plugin.
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_cadeia_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Aula aulaConcluida(String id) => Aula(
        id: id,
        materiaId: 'm1',
        nome: 'Aula 01',
        paginasTotais: 10,
        paginasLidas: 10,
        concluida: true,
        dataConclusao: DateTime(2026, 7, 10),
      );

  test('conclusão gera Revisão 1 no menor intervalo a partir da data',
      () async {
    final useCase = container.read(sessaoEstudoUseCaseProvider);
    final revisao =
        await useCase.criarCadeiaParaAula(aulaConcluida('a1'), 'AFO');
    expect(revisao, isNotNull);
    expect(revisao!.intervaloDias, 7); // menor da cadeia padrão
    // Revisão 1 nasce de dataConclusao + intervalo (10/07 + 7 = 17/07).
    expect(revisao.dataAgendada, DateTime(2026, 7, 17));
    expect(revisao.aulaId, 'a1');
    expect(revisao.materiaId, 'm1');
    expect(revisao.titulo, contains('AFO'));

    expect(container.read(revisoesProvider).length, 1);
  });

  test('não duplica: segunda chamada da mesma aula é no-op', () async {
    final useCase = container.read(sessaoEstudoUseCaseProvider);
    await useCase.criarCadeiaParaAula(aulaConcluida('a1'), 'AFO');
    final segunda =
        await useCase.criarCadeiaParaAula(aulaConcluida('a1'), 'AFO');
    expect(segunda, isNull); // já existe cadeia pendente da aula

    expect(container.read(revisoesProvider).length, 1);
  });

  test('concluir revisão preserva o aulaId na sucessora (linhagem da cadeia)',
      () async {
    final sessao = container.read(sessaoEstudoUseCaseProvider);
    final primeira =
        await sessao.criarCadeiaParaAula(aulaConcluida('a1'), 'AFO');

    final resultado =
        await container.read(revisaoUseCaseProvider).concluir(primeira!);
    final proxima = resultado.proxima;
    expect(proxima, isNotNull, reason: 'cadeia não pode encerrar no 1º passo');
    expect(proxima!.aulaId, 'a1');
    expect(proxima.materiaId, 'm1');

    // Com a sucessora pendente carregando o aulaId, o dedupe de
    // criarCadeiaParaAula continua enxergando a cadeia viva.
    final duplicada =
        await sessao.criarCadeiaParaAula(aulaConcluida('a1'), 'AFO');
    expect(duplicada, isNull);
  });
}
