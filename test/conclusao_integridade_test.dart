import 'dart:io';
import 'package:app_estudos/application/revisao_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/repositories/conclusoes_revisao_repositorio.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory dir;
  late ProviderContainer c;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('conclusao_real_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrar();
    c = ProviderContainer();
  });
  tearDown(() async {
    c.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });
  Revisao r(String id) => Revisao(
    id: id,
    materiaId: 'm',
    titulo: id,
    dataAgendada: DateTime.now(),
    intervaloDias: 7,
  );
  test('mesmo ID simultaneo produz uma sessao e uma sucessora', () async {
    final use = c.read(revisaoUseCaseProvider);
    final results = await Future.wait(
      List.generate(5, (_) => use.concluir(r('a'), questoes: 10, acertos: 8)),
    );
    expect(c.read(registrosProvider), hasLength(1));
    expect(c.read(revisoesProvider), hasLength(2));
    expect(results.map((e) => e.proxima!.id).toSet(), hasLength(1));
  });
  test(
    'excluir concluidas e reabrir nao renova teto nem repete efeitos',
    () async {
      for (var i = 0; i < 3; i++) {
        await c
            .read(revisaoUseCaseProvider)
            .concluir(r('$i'), questoes: 10, acertos: 8);
        await c.read(revisoesProvider.notifier).remover('$i');
      }
      c.dispose();
      await Hive.close();
      await HiveBoxes.openAll();
      await HiveBoxes.migrar();
      c = ProviderContainer();
      await c
          .read(revisaoUseCaseProvider)
          .concluir(r('0'), questoes: 10, acertos: 8);
      await c
          .read(revisaoUseCaseProvider)
          .concluir(r('4'), questoes: 10, acertos: 8);
      expect(c.read(registrosProvider), hasLength(4));
      expect(
        c.read(registrosProvider).where((e) => e.minutos == 0),
        hasLength(1),
      );
      expect(c.read(revisoesProvider).where((e) => e.id == '0'), isEmpty);
    },
  );
  for (final etapa in ['sessao', 'feita', 'proxima']) {
    test('falha apos $etapa recupera mesmos IDs no boot', () async {
      c.dispose();
      c = ProviderContainer(
        overrides: [
          revisaoUseCaseProvider.overrideWith(
            (ref) => RevisaoUseCase(
              ref,
              aposEtapaPersistida: (atual) async {
                if (atual == etapa) throw StateError('failpoint $etapa');
              },
            ),
          ),
        ],
      );
      await expectLater(
        c
            .read(revisaoUseCaseProvider)
            .concluir(r('interrompida'), questoes: 10, acertos: 8),
        throwsStateError,
      );
      final intencao = Map.from(
        ConclusoesRevisaoRepositorio.box.get('interrompida')!,
      );
      expect(intencao['aplicada'], false);
      final sessaoId = (intencao['sessao'] as Map)['id'];
      final proximaId = (intencao['proxima'] as Map)['id'];
      c.dispose();
      await Hive.close();
      await HiveBoxes.openAll();
      await HiveBoxes.migrar();
      c = ProviderContainer();
      final repetida = await c
          .read(revisaoUseCaseProvider)
          .concluir(r('interrompida'), questoes: 2, acertos: 0);
      expect(repetida.proxima!.id, proximaId);
      expect(repetida.taxaAcerto, 0.8);
      expect(c.read(registrosProvider).single.id, sessaoId);
      expect(c.read(registrosProvider).single.questoes, 10);
      expect(c.read(revisoesProvider), hasLength(2));
      expect(
        ConclusoesRevisaoRepositorio.box.get('interrompida')!['aplicada'],
        true,
      );
    });
  }
  test(
    'conclusoes diferentes concorrentes compartilham apenas tres creditos',
    () async {
      await Future.wait(
        List.generate(
          12,
          (i) => c
              .read(revisaoUseCaseProvider)
              .concluir(r('r$i'), questoes: 10, acertos: 8),
        ),
      );
      expect(
        c.read(registrosProvider).where((e) => e.minutos > 0),
        hasLength(3),
      );
      expect(c.read(registrosProvider), hasLength(12));
    },
  );
  test('legado concluido migra sem criar efeitos e consome quota', () async {
    for (var i = 0; i < 3; i++) {
      await Hive.box<Map>(HiveBoxes.revisoes).put(
        'l$i',
        r('l$i').copyWith(feita: true, dataConclusao: DateTime.now()).toJson(),
      );
    }
    await HiveBoxes.migrar();
    c.invalidate(revisoesProvider);
    final repetida = await c
        .read(revisaoUseCaseProvider)
        .concluir(r('l0'), questoes: 10, acertos: 8);
    expect(repetida.proxima, isNull);
    expect(c.read(registrosProvider), isEmpty);
    await c
        .read(revisaoUseCaseProvider)
        .concluir(r('nova'), questoes: 10, acertos: 8);
    expect(c.read(registrosProvider).single.minutos, 0);
  });
}
