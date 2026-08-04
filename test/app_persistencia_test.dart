import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Round-trip real de disco: grava por um `ProviderContainer`, FECHA os boxes,
/// reabre e lê por um container novo.
///
/// Por que fechar e reabrir importa: um teste que só descarta o container e
/// cria outro prova apenas que o provider relê o Hive em memória. O que o
/// usuário sente ao matar e reabrir o app é o arquivo em disco — e essa
/// fronteira (`toJson` -> bytes -> `fromJson`) é onde um campo novo some sem
/// ninguém notar. O app é local-first: se isto quebra, não há servidor de onde
/// recuperar.
///
/// `test` e não `testWidgets`: não há UI aqui, e fora da zona fake-async do
/// `testWidgets` as escritas reais no Hive concluem sem precisar de
/// `tester.runAsync` (mesmo padrão de `test/backup_rollback_test.dart`).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_app_persist_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('registro gravado sobrevive a fechar e reabrir os boxes', () async {
    // Matéria antes do registro: `materiaId` é referência, e gravar registro
    // órfão testaria uma situação que a UI não produz.
    final materia = Materia(
      id: 'materia-afo',
      nome: 'AFO',
      corSlot: 0,
      criadaEm: DateTime(2026, 8, 1),
    );
    await Hive.box<Map>(HiveBoxes.materias).put(materia.id, materia.toJson());

    final registro = RegistroHora(
      id: 'registro-1',
      data: DateTime(2026, 8, 3),
      materiaId: materia.id,
      tipo: TipoEstudo.pratica,
      tarefa: 'Lei 14.133 — licitações',
      minutos: 95,
      questoes: 40,
      acertos: 31,
      banca: 'CEBRASPE',
    );

    final containerAntes = ProviderContainer();
    await containerAntes.read(registrosProvider.notifier).salvar(registro);
    expect(containerAntes.read(registrosProvider), hasLength(1));
    containerAntes.dispose();

    // "Restart": os boxes saem da memória e voltam do arquivo.
    await Hive.close();
    await HiveBoxes.openAll();

    final containerDepois = ProviderContainer();
    addTearDown(containerDepois.dispose);
    final lidos = containerDepois.read(registrosProvider);

    expect(lidos, hasLength(1));
    final lido = lidos.single;

    // Campo a campo, não `equals` do objeto: o defeito que isto pega é um
    // campo sumindo no `toJson`/`fromJson`, e comparar identidade esconderia
    // exatamente isso se `RegistroHora` não implementar `==`.
    expect(lido.id, registro.id);
    expect(lido.data, registro.data);
    expect(lido.materiaId, materia.id);
    expect(lido.tipo, TipoEstudo.pratica);
    expect(lido.tarefa, 'Lei 14.133 — licitações');
    expect(lido.minutos, 95);
    expect(lido.questoes, 40);
    expect(lido.acertos, 31);
    expect(lido.banca, 'CEBRASPE');
  });
}
