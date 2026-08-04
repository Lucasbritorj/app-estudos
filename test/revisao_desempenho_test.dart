import 'dart:io';

import 'package:app_estudos/application/revisao_use_case.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/configuracoes.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/domain/gamificacao_service.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/repositories/configuracoes_repositorio.dart';
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

  group('âncora do espelho UAT', () {
    // O harness `Mundo` de test/uat/uat_revisoes_em_dia_test.dart é uma
    // transcrição à mão deste use case (não dá para instanciá-lo lá: pede Ref
    // do Riverpod). Ele JÁ derivou uma vez — ficou com `minutos = 0` depois
    // que a produção passou a creditar `config.minutosPadraoRevisao`, e a UAT
    // seguiu verde medindo um modelo inexistente.
    //
    // Estes dois testes são o elo que fecha a corrente:
    //   produção  == const Configuracoes().minutosPadraoRevisao   (aqui)
    //   espelho   == const Configuracoes().minutosPadraoRevisao   (UAT-H2)
    //   ⇒ espelho == produção
    // Sem isto, "reconciliei o espelho" seria promessa, não garantia.

    test('sem minutos informados, credita o padrão da configuração', () async {
      final useCase = container.read(revisaoUseCaseProvider);
      await useCase.concluir(pendente(), questoes: 10, acertos: 9);

      final sessao = container.read(registrosProvider).single;
      expect(sessao.minutos, const Configuracoes().minutosPadraoRevisao);
      expect(
        sessao.minutos,
        container.read(configuracoesProvider).minutosPadraoRevisao,
      );
    });

    test('minutos explícitos vencem o padrão', () async {
      final useCase = container.read(revisaoUseCaseProvider);
      await useCase.concluir(
        pendente(),
        questoes: 10,
        acertos: 9,
        minutos: 45,
      );
      expect(container.read(registrosProvider).single.minutos, 45);
    });
  });

  group('M-02 — teto diário do tempo estimado', () {
    Revisao avulsa(String id) => Revisao(
      id: id,
      materiaId: 'm1',
      topicoId: 't1',
      titulo: 'AFO — Orçamento ($id)',
      dataAgendada: DateTime.now(),
      intervaloDias: 7,
      estabilidade: 7,
      dificuldade: 5,
    );

    test('da 4ª conclusão do dia em diante a sessão entra com 0 min', () async {
      final useCase = container.read(revisaoUseCaseProvider);
      final padrao = container
          .read(configuracoesProvider)
          .minutosPadraoRevisao;

      for (var i = 0; i < 5; i++) {
        await useCase.concluir(avulsa('r$i'), questoes: 10, acertos: 9);
      }

      // Só as sessões criadas por ESTAS conclusões (a cadeia agenda outras
      // revisões, mas elas não geram registro).
      final minutos = container
          .read(registrosProvider)
          .map((r) => r.minutos)
          .toList();
      expect(minutos, hasLength(5));
      expect(
        minutos.fold<int>(0, (s, m) => s + m),
        GamificacaoService.maxRevisoesComBonusPorDia * padrao,
        reason: 'o dia inteiro credita no máximo 3 × o padrão',
      );
      expect(minutos.where((m) => m == padrao).length, 3);
      expect(minutos.where((m) => m == 0).length, 2);
    });

    test('questões e acertos NUNCA são descartados pelo teto', () async {
      final useCase = container.read(revisaoUseCaseProvider);
      for (var i = 0; i < 5; i++) {
        await useCase.concluir(avulsa('q$i'), questoes: 10, acertos: 7);
      }
      final registros = container.read(registrosProvider);
      expect(registros, hasLength(5));
      // Desempenho é dado real: alimenta Elo, FSRS e taxa mesmo sem tempo.
      expect(registros.every((r) => r.questoes == 10), isTrue);
      expect(registros.every((r) => r.acertos == 7), isTrue);
    });

    test('tempo INFORMADO passa inteiro, mesmo acima do teto', () async {
      final useCase = container.read(revisaoUseCaseProvider);
      for (var i = 0; i < 5; i++) {
        await useCase.concluir(
          avulsa('m$i'),
          questoes: 10,
          acertos: 9,
          minutos: 30,
        );
      }
      // Medição não é estimativa: o teto não corta o que o usuário cronometrou.
      expect(
        container.read(registrosProvider).every((r) => r.minutos == 30),
        isTrue,
      );
    });

    test('monotonicidade: o teto não rebaixa XP já gravado', () async {
      final useCase = container.read(revisaoUseCaseProvider);
      var anterior = 0;
      for (var i = 0; i < 6; i++) {
        await useCase.concluir(avulsa('x$i'), questoes: 10, acertos: 9);
        final xp = GamificacaoService.xpDetalhado(
          container.read(registrosProvider),
          container.read(revisoesProvider),
          DateTime.now(),
        ).total;
        expect(
          xp,
          greaterThanOrEqualTo(anterior),
          reason: 'XP nunca cai — o teto corta ganho futuro, não o passado',
        );
        anterior = xp;
      }
    });
  });
}
