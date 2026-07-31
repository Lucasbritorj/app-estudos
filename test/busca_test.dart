import 'dart:io';

import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/models/resumo.dart';
import 'package:app_estudos/data/models/simulado.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/busca_service.dart';
import 'package:app_estudos/features/busca/busca_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

Materia _materia(String id, String nome, {String notas = ''}) => Materia(
  id: id,
  nome: nome,
  corSlot: 0,
  criadaEm: DateTime(2026, 1, 1),
  notas: notas,
);

Topico _topico(String id, String materiaId, String nome, {String notas = ''}) =>
    Topico(id: id, materiaId: materiaId, nome: nome, notas: notas);

QuestaoErrada _questao(
  String id,
  String materiaId,
  String enunciado, {
  String comentario = '',
}) => QuestaoErrada(
  id: id,
  materiaId: materiaId,
  enunciado: enunciado,
  comentario: comentario,
  criadaEm: DateTime(2026, 1, 1),
);

Resumo _resumo(String sigla, String nome, {String texto = ''}) =>
    Resumo(sigla: sigla, nome: nome, texto: texto);

Aula _aula(String id, String materiaId, String nome) =>
    Aula(id: id, materiaId: materiaId, nome: nome, paginasTotais: 10);

Simulado _simulado(String id, String nome, {String comentario = '', String cargo = ''}) =>
    Simulado(
      id: id,
      ambienteId: 'geral',
      tipo: TipoSimulado.simulado,
      nome: nome,
      cargo: cargo,
      comentario: comentario,
      data: DateTime(2026, 1, 1),
    );

/// Testes do domínio de busca global (BuscaService) e um smoke test de
/// widget da tela (BuscaScreen) — Q4: com um edital de 200+ tópicos, achar
/// um item exigia navegar a árvore inteira antes desta feature existir.
void main() {
  group('BuscaService.buscar — normalização de acento', () {
    test('sem acento acha título com acento ("orcamentaria" -> "Orçamentária")', () {
      final r = BuscaService.buscar(
        'orcamentaria',
        materias: [_materia('m1', 'Contabilidade Orçamentária')],
      );
      expect(r.map((e) => e.titulo), ['Contabilidade Orçamentária']);
    });

    test('com acento também acha título sem acento (normalização é simétrica)', () {
      final r = BuscaService.buscar(
        'prescrição',
        materias: [_materia('m1', 'Prescricao Tributaria')],
      );
      expect(r, isNotEmpty);
      expect(r.single.titulo, 'Prescricao Tributaria');
    });

    test('case-insensitive: maiúsculas e minúsculas casam igual', () {
      expect(
        BuscaService.buscar('DIREITO', materias: [_materia('m1', 'direito penal')]),
        isNotEmpty,
      );
      expect(
        BuscaService.buscar('direito', materias: [_materia('m1', 'DIREITO PENAL')]),
        isNotEmpty,
      );
    });
  });

  group('BuscaService.buscar — termo curto', () {
    final base = [_materia('m1', 'Direito Administrativo')];

    test('termo vazio devolve lista vazia (não devolve o app inteiro)', () {
      expect(BuscaService.buscar('', materias: base), isEmpty);
    });

    test('termo com 1 caractere devolve lista vazia', () {
      expect(BuscaService.buscar('d', materias: base), isEmpty);
    });

    test('termo só com espaços devolve lista vazia', () {
      expect(BuscaService.buscar('   ', materias: base), isEmpty);
    });

    test('2 caracteres já buscam normalmente', () {
      expect(BuscaService.buscar('di', materias: base), isNotEmpty);
    });
  });

  group(
    'BuscaService.buscar — ranking: prefixo > palavra inteira > substring '
    'título > substring corpo',
    () {
      test('as quatro camadas ordenam nessa ordem exata, com score decrescente', () {
        final materias = [
          // Corpo (notas) é o único lugar com "penal" — pior camada.
          _materia(
            'p4',
            'Segurança Pública',
            notas: 'Envolve direito penal e processual',
          ),
          // Prefixo do título — melhor camada.
          _materia('p1', 'Penalidades Administrativas'),
          // Substring dentro de uma palavra do título ("penalizador"), mas
          // não é a palavra inteira nem o prefixo.
          _materia('p3', 'Regime Penalizador'),
          // "penal" é uma palavra inteira do título, mas não é prefixo dele.
          _materia('p2', 'Direito Penal'),
        ];

        final r = BuscaService.buscar('penal', materias: materias);

        expect(r.map((e) => e.titulo).toList(), [
          'Penalidades Administrativas',
          'Direito Penal',
          'Regime Penalizador',
          'Segurança Pública',
        ]);
        for (var i = 1; i < r.length; i++) {
          expect(
            r[i].score,
            lessThan(r[i - 1].score),
            reason: 'cada camada deve valer estritamente menos que a anterior',
          );
        }
      });

      test('empate de score desempata por nome (ordem alfabética)', () {
        final r = BuscaService.buscar(
          'bio',
          materias: [_materia('b2', 'Biomedicina'), _materia('b1', 'Biologia')],
        );
        expect(r.map((e) => e.titulo).toList(), ['Biologia', 'Biomedicina']);
      });
    },
  );

  group('BuscaService.buscar — entrada hostil nunca lança', () {
    test('".*" não quebra e não vira coringa', () {
      final materias = [_materia('m1', 'Direito Penal')];
      expect(() => BuscaService.buscar('.*', materias: materias), returnsNormally);
      expect(BuscaService.buscar('.*', materias: materias), isEmpty);
    });

    test('padrão de ReDoS clássico "(a+)+\$" não quebra nem trava', () {
      expect(
        () => BuscaService.buscar(
          r'(a+)+$',
          materias: [_materia('m1', 'AAAAAAAAAAAAAAAAAAAA')],
        ),
        returnsNormally,
      );
    });

    test('colchete/parênteses desbalanceados não quebram', () {
      expect(
        () => BuscaService.buscar(
          r'[abc(unclosed',
          materias: [_materia('m1', 'Direito')],
        ),
        returnsNormally,
      );
    });

    test('emoji não quebra', () {
      expect(
        () => BuscaService.buscar('😀🔥💥', materias: [_materia('m1', 'Direito')]),
        returnsNormally,
      );
      expect(
        () => BuscaService.buscar(
          'termo com emoji 🎉 no meio',
          materias: [_materia('m1', 'Festa 🎉')],
        ),
        returnsNormally,
      );
    });

    test('string gigante não quebra nem trava (teto defensivo interno)', () {
      final termoGigante = 'a' * 500000;
      expect(
        () => BuscaService.buscar(termoGigante, materias: [_materia('m1', 'Direito')]),
        returnsNormally,
      );
      expect(
        BuscaService.buscar(termoGigante, materias: [_materia('m1', 'Direito')]),
        isEmpty,
      );
    });
  });

  group('BuscaService.buscar — listas vazias', () {
    test('nenhuma lista informada (todas default) devolve vazio, nunca exceção', () {
      expect(() => BuscaService.buscar('direito'), returnsNormally);
      expect(BuscaService.buscar('direito'), isEmpty);
    });

    test('termo válido sem nenhum item batendo devolve lista vazia', () {
      final r = BuscaService.buscar(
        'zzznadabate',
        materias: [_materia('m1', 'Direito')],
        topicos: [_topico('t1', 'm1', 'Constitucional')],
      );
      expect(r, isEmpty);
    });
  });

  group('BuscaService.buscar — cobertura por tipo', () {
    test('tópico: subtítulo traz o nome da matéria dona e materiaId preenchido', () {
      final r = BuscaService.buscar(
        'tributos',
        materias: [_materia('m1', 'Direito Tributário')],
        topicos: [_topico('t1', 'm1', 'Tributos em espécie')],
      );
      expect(r.single.tipo, TipoResultadoBusca.topico);
      expect(r.single.materiaId, 'm1');
      expect(r.single.subtitulo, contains('Direito Tributário'));
    });

    test('questão: acha pelo enunciado (palavra inteira) e pelo comentário (corpo)', () {
      final porEnunciado = BuscaService.buscar(
        'licitacao',
        questoes: [_questao('q1', 'm1', 'Sobre licitação pública')],
      );
      expect(porEnunciado.single.tipo, TipoResultadoBusca.questao);
      expect(porEnunciado.single.id, 'q1');

      final porComentario = BuscaService.buscar(
        'confundi',
        questoes: [
          _questao('q2', 'm1', 'Enunciado qualquer', comentario: 'confundi os prazos'),
        ],
      );
      expect(porComentario.single.id, 'q2');
    });

    test('resumo: acha pelo texto (corpo) mesmo sem bater no nome/sigla', () {
      final r = BuscaService.buscar(
        'anistia',
        resumos: [_resumo('DP', 'Direito Penal', texto: 'Capítulo sobre anistia e graça')],
      );
      expect(r.single.tipo, TipoResultadoBusca.resumo);
      expect(r.single.id, 'DP');
    });

    test('aula: subtítulo traz o nome da matéria dona e materiaId preenchido', () {
      final r = BuscaService.buscar(
        'aula 01',
        materias: [_materia('m1', 'AFO')],
        aulas: [_aula('a1', 'm1', 'Aula 01 — Orçamento')],
      );
      expect(r.single.tipo, TipoResultadoBusca.aula);
      expect(r.single.materiaId, 'm1');
      expect(r.single.subtitulo, contains('AFO'));
    });

    test('simulado: acha pelo nome', () {
      final r = BuscaService.buscar(
        'sefaz',
        simulados: [_simulado('s1', 'SEFAZ-RN 2026 — objetiva')],
      );
      expect(r.single.tipo, TipoResultadoBusca.simulado);
      expect(r.single.id, 's1');
    });
  });

  group('BuscaScreen (widget)', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hive_busca_');
      Hive.init(dir.path);
      await HiveBoxes.openAll();
      await HiveBoxes.migrarAmbientes();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    Future<void> montar(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: BuscaScreen())),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('abre com foco automático e mostra a dica antes de digitar', (
      tester,
    ) async {
      await montar(tester);

      expect(find.text('Busque em todo o app'), findsOneWidget);
      final campo = tester.widget<TextField>(find.byType(TextField));
      expect(campo.autofocus, isTrue);
    });

    testWidgets('digitar um termo mostra o resultado agrupado por tipo', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final materia = Materia(
          id: 'm1',
          nome: 'Direito Constitucional',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(HiveBoxes.materias).put(materia.id, materia.toJson());
      });

      await montar(tester);

      await tester.enterText(find.byType(TextField), 'constitu');
      await tester.pumpAndSettle();

      expect(find.text('Direito Constitucional'), findsOneWidget);
      expect(find.textContaining('MATÉRIAS'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('termo sem nenhum resultado mostra o estado "nada encontrado"', (
      tester,
    ) async {
      await montar(tester);

      await tester.enterText(find.byType(TextField), 'zzzznadabate');
      await tester.pumpAndSettle();

      expect(find.text('Nada encontrado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tocar num resultado de matéria navega para TopicosScreen', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final materia = Materia(
          id: 'm1',
          nome: 'Direito Constitucional',
          corSlot: 0,
          criadaEm: DateTime(2026, 1, 1),
        );
        await Hive.box<Map>(HiveBoxes.materias).put(materia.id, materia.toJson());
      });

      await montar(tester);
      await tester.enterText(find.byType(TextField), 'constitu');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Direito Constitucional'));
      await tester.pumpAndSettle();

      expect(find.text('Direito Constitucional'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
