import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/repositories/configuracoes_repositorio.dart';
import 'package:app_estudos/data/repositories/planejamento_repositorio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Cronograma escopado por ambiente: cada ambiente tem seus minutos
/// semanais; a visão consolidada usa a chave global legada; ambiente sem
/// cronograma próprio herda o global até a primeira edição.
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_plano_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> ativarAmbiente(String? id) async {
    final config = container.read(configuracoesProvider);
    await container.read(configuracoesProvider.notifier).salvar(id == null
        ? config.copyWith(limparAmbienteAtivo: true)
        : config.copyWith(ambienteAtivoId: id));
  }

  test('edição por ambiente não vaza para o global nem para outro ambiente',
      () async {
    // Visão consolidada: grava a chave global legada.
    await container
        .read(planejamentoProvider.notifier)
        .substituir({1: 120, 3: 60});
    expect(container.read(planejamentoProvider), {1: 120, 3: 60});

    // Ambiente A: herda o global na leitura...
    await ativarAmbiente('amb-a');
    expect(container.read(planejamentoProvider), {1: 120, 3: 60});
    // ...e a primeira edição vira snapshot próprio.
    await container.read(planejamentoProvider.notifier).definirDia(1, 300);
    expect(container.read(planejamentoProvider), {1: 300, 3: 60});

    // Ambiente B continua herdando o global intocado.
    await ativarAmbiente('amb-b');
    expect(container.read(planejamentoProvider), {1: 120, 3: 60});

    // Consolidada segue com o global original.
    await ativarAmbiente(null);
    expect(container.read(planejamentoProvider), {1: 120, 3: 60});

    // E o ambiente A mantém o snapshot editado.
    await ativarAmbiente('amb-a');
    expect(container.read(planejamentoProvider), {1: 300, 3: 60});
  });

  test('sem cronograma nenhum: mapa vazio (sem dados, sem inventar)',
      () async {
    await ativarAmbiente('amb-novo');
    expect(container.read(planejamentoProvider), isEmpty);
    expect(container.read(configuracoesProvider),
        isA<Configuracoes>()); // sanidade do harness
  });
}
