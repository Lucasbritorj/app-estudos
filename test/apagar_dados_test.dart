import 'dart:io';

import 'package:app_estudos/application/apagar_dados_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/models/leitura.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/resumo.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/simulado.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/data/repositories/configuracoes_repositorio.dart';
import 'package:app_estudos/data/repositories/planejamento_repositorio.dart';
import 'package:app_estudos/data/repositories/repositorios.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Wipe out (B2): apagarTudo() precisa esvaziar as 9 coleções + o
/// planejamento + o ambienteAtivoId, sobre Hive real (mesmo setUp de
/// dashboard_screen_test.dart).
void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_apagar_');
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

  Future<void> semear() async {
    await container.read(ambientesProvider.notifier).salvar(
          Ambiente(id: 'amb1', nome: 'SEFAZ', criadoEm: DateTime(2026, 1, 1)),
        );
    await container.read(materiasProvider.notifier).salvar(
          Materia(
            id: 'm1',
            nome: 'AFO',
            corSlot: 0,
            ambienteId: 'amb1',
            criadaEm: DateTime(2026, 1, 1),
          ),
        );
    await container
        .read(topicosProvider.notifier)
        .salvar(const Topico(id: 't1', materiaId: 'm1', nome: 'Receita'));
    await container.read(aulasProvider.notifier).salvar(
          Aula(
            id: 'a1',
            materiaId: 'm1',
            nome: 'Aula 01',
            paginasTotais: 10,
            paginasLidas: 10,
            concluida: true,
            dataConclusao: DateTime(2026, 1, 5),
          ),
        );
    await container.read(registrosProvider.notifier).salvar(
          RegistroHora(
            id: 'r1',
            data: DateTime(2026, 1, 2),
            materiaId: 'm1',
            minutos: 60,
            questoes: 10,
            acertos: 8,
          ),
        );
    await container.read(revisoesProvider.notifier).salvar(
          Revisao(
            id: 'rev1',
            materiaId: 'm1',
            titulo: 'Revisão AFO',
            dataAgendada: DateTime(2026, 1, 9),
            intervaloDias: 7,
          ),
        );
    await container
        .read(resumosProvider.notifier)
        .salvar(const Resumo(sigla: 'AFO', nome: 'AFO', texto: 'anotações'));
    await container.read(leiturasProvider.notifier).salvar(
          const Leitura(
            id: 'l1',
            titulo: 'Lei 4320',
            paginaInicio: 1,
            paginaFim: 20,
            partes: 2,
            partesConcluidas: [false, false],
          ),
        );
    await container.read(simuladosProvider.notifier).salvar(
          Simulado(
            id: 's1',
            ambienteId: 'amb1',
            tipo: TipoSimulado.simulado,
            nome: 'Simulado 1',
            data: DateTime(2026, 1, 3),
          ),
        );
    await container.read(planejamentoProvider.notifier).definirDia(1, 120);
    await container
        .read(configuracoesProvider.notifier)
        .salvar(const Configuracoes(ambienteAtivoId: 'amb1'));
  }

  test('apagarTudo esvazia as 9 coleções, planejamento e ambienteAtivoId',
      () async {
    await semear();

    // Sanidade do seed antes do wipe.
    expect(container.read(ambientesProvider).length, 2); // Geral + amb1
    expect(container.read(materiasProvider), isNotEmpty);
    expect(container.read(topicosProvider), isNotEmpty);
    expect(container.read(aulasProvider), isNotEmpty);
    expect(container.read(registrosProvider), isNotEmpty);
    expect(container.read(revisoesProvider), isNotEmpty);
    expect(container.read(resumosProvider), isNotEmpty);
    expect(container.read(leiturasProvider), isNotEmpty);
    expect(container.read(simuladosProvider), isNotEmpty);
    expect(container.read(planejamentoProvider), isNotEmpty);
    expect(container.read(configuracoesProvider).ambienteAtivoId, 'amb1');

    final antes =
        container.read(apagarDadosUseCaseProvider).contarRegistrosParaApagar();
    expect(antes.registros, 1);
    expect(antes.materias, 1);
    expect(antes.topicos, 1);
    expect(antes.aulas, 1);
    expect(antes.revisoes, 1);
    expect(antes.resumos, 1);
    expect(antes.leituras, 1);
    expect(antes.simulados, 1);
    expect(antes.ambientes, 2);

    await container.read(apagarDadosUseCaseProvider).apagarTudo();

    expect(container.read(ambientesProvider), isEmpty);
    expect(container.read(materiasProvider), isEmpty);
    expect(container.read(topicosProvider), isEmpty);
    expect(container.read(aulasProvider), isEmpty);
    expect(container.read(registrosProvider), isEmpty);
    expect(container.read(revisoesProvider), isEmpty);
    expect(container.read(resumosProvider), isEmpty);
    expect(container.read(leiturasProvider), isEmpty);
    expect(container.read(simuladosProvider), isEmpty);
    expect(container.read(planejamentoProvider), isEmpty);
    expect(container.read(configuracoesProvider).ambienteAtivoId, isNull);

    final depois =
        container.read(apagarDadosUseCaseProvider).contarRegistrosParaApagar();
    expect(depois.registros, 0);
    expect(depois.materias, 0);
    expect(depois.topicos, 0);
    expect(depois.aulas, 0);
    expect(depois.revisoes, 0);
    expect(depois.resumos, 0);
    expect(depois.leituras, 0);
    expect(depois.simulados, 0);
    expect(depois.ambientes, 0);
  });

  test('apagarTudo em base já vazia não lança exceção', () async {
    await container.read(apagarDadosUseCaseProvider).apagarTudo();

    expect(container.read(materiasProvider), isEmpty);
    expect(container.read(ambientesProvider), isEmpty);
  });
}
