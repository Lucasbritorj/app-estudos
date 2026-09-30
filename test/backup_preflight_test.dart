import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:app_estudos/application/backup_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:app_estudos/domain/import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late ProviderContainer container;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('backup_preflight_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    container = ProviderContainer();
  });
  tearDown(() async {
    container.dispose();
    await Hive.close();
    await dir.delete(recursive: true);
  });
  test('backup legado não remove pai de questão preservada', () async {
    await container
        .read(materiasProvider.notifier)
        .salvar(
          Materia(
            id: 'm',
            nome: 'Dados',
            corSlot: 0,
            peso: 1,
            criadaEm: DateTime(2026),
          ),
        );
    await container
        .read(questoesErradasProvider.notifier)
        .salvar(
          QuestaoErrada(
            id: 'q',
            materiaId: 'm',
            enunciado: 'Preservar',
            criadaEm: DateTime(2026),
          ),
        );
    final useCase = container.read(backupUseCaseProvider);
    await expectLater(
      useCase.restaurarSubstituindo(
        ImportService.parseBackup('{"versao":1,"materias":[]}'),
      ),
      throwsA(isA<StateError>()),
    );
    expect(container.read(materiasProvider).single.id, 'm');
    expect(
      container.read(questoesErradasProvider).single.enunciado,
      'Preservar',
    );
    expect(
      useCase.podeDesfazer,
      isFalse,
      reason: 'recusa anterior a qualquer escrita',
    );
  });
}
