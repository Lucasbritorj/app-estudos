import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/execucao_prova.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// B15 — duas edições no MESMO frame não podem se sobrescrever.
///
/// A tela guarda a `ExecucaoProva` do build corrente. Enquanto o rebuild não
/// propaga o estado novo, uma segunda edição partiria da mesma base e o write
/// dela apagaria o primeiro. `ExecucaoProvaController.mutar` lê o estado atual
/// dentro da própria chamada, então cada mutação enxerga a anterior.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_race_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  ExecucaoProva provaDeTres() => ExecucaoProva(
    id: 'exec-1',
    nome: 'Simulado TRF',
    iniciadaEm: DateTime(2026, 7, 30, 9),
    duracaoMinutos: 60,
    itens: [for (var n = 1; n <= 3; n++) ItemProva(numero: n)],
  );

  Future<ExecucaoProvaController> comProvaAtiva() async {
    final notifier = container.read(execucaoProvaProvider.notifier);
    await notifier.iniciar(provaDeTres());
    return notifier;
  }

  String? gabaritoDe(ExecucaoProva? e, int numero) =>
      e?.itens.firstWhere((i) => i.numero == numero).gabarito;

  test('mutar: dois gabaritos no mesmo frame preservam os dois', () async {
    final notifier = await comProvaAtiva();

    // Sem rebuild entre as duas: é exatamente a janela da race.
    notifier.mutar(
      (atual) =>
          atual.comItemAtualizado(1, (i) => i.copyWith(gabarito: 'A')),
    );
    notifier.mutar(
      (atual) =>
          atual.comItemAtualizado(2, (i) => i.copyWith(gabarito: 'B')),
    );

    final estado = container.read(execucaoProvaProvider);
    expect(gabaritoDe(estado, 1), 'A');
    expect(gabaritoDe(estado, 2), 'B');
    expect(gabaritoDe(estado, 3), isNull);
  });

  test('contraprova: `atualizar` com base capturada perde a 1ª edição', () async {
    final notifier = await comProvaAtiva();
    // Base capturada uma vez — o padrão ANTIGO da tela.
    final base = container.read(execucaoProvaProvider)!;

    notifier.atualizar(
      base.comItemAtualizado(1, (i) => i.copyWith(gabarito: 'A')),
    );
    notifier.atualizar(
      base.comItemAtualizado(2, (i) => i.copyWith(gabarito: 'B')),
    );

    final estado = container.read(execucaoProvaProvider);
    expect(
      gabaritoDe(estado, 1),
      isNull,
      reason: 'documenta o defeito que `mutar` corrige',
    );
    expect(gabaritoDe(estado, 2), 'B');
  });

  test('mutar: marcação de resposta em rajada preserva todas', () async {
    final notifier = await comProvaAtiva();

    for (final (numero, letra) in [(1, 'C'), (2, 'D'), (3, 'E')]) {
      notifier.mutar(
        (atual) => atual.comItemAtualizado(
          numero,
          (i) => i.copyWith(respostaMarcada: letra),
        ),
      );
    }

    final estado = container.read(execucaoProvaProvider)!;
    expect(
      estado.itens.map((i) => i.respostaMarcada).toList(),
      ['C', 'D', 'E'],
    );
  });

  test('mutar persiste no Hive, não só em memória', () async {
    final notifier = await comProvaAtiva();
    notifier.mutar(
      (atual) =>
          atual.comItemAtualizado(2, (i) => i.copyWith(gabarito: 'E')),
    );

    // Lê o box direto: prova que o write saiu, sem depender do state.
    final bruto = Hive.box<Map>(HiveBoxes.execucaoProva).get('atual');
    expect(bruto, isNotNull);
    final doDisco = ExecucaoProva.fromJson(
      Map<String, dynamic>.from(bruto!),
    );
    expect(gabaritoDe(doDisco, 2), 'E');
  });

  test('mutar sem execução ativa é no-op (não lança)', () async {
    final notifier = container.read(execucaoProvaProvider.notifier);
    expect(container.read(execucaoProvaProvider), isNull);

    notifier.mutar(
      (atual) =>
          atual.comItemAtualizado(1, (i) => i.copyWith(gabarito: 'A')),
    );

    expect(container.read(execucaoProvaProvider), isNull);
  });
}
