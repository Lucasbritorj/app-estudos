@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:app_estudos/core/theme/app_theme.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/ambiente.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/execucao_prova.dart';
import 'package:app_estudos/data/models/leitura.dart';
import 'package:app_estudos/data/models/questao_errada.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/resumo.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/features/dashboard/dashboard_providers.dart';
import 'package:app_estudos/features/ambientes/ambientes_screen.dart';
import 'package:app_estudos/features/aulas/aulas_screen.dart';
import 'package:app_estudos/features/caderno/caderno_screen.dart';
import 'package:app_estudos/features/configuracoes/configuracoes_screen.dart';
import 'package:app_estudos/features/cronometro/cronometro_screen.dart';
import 'package:app_estudos/features/dashboard/dashboard_screen.dart';
import 'package:app_estudos/features/edital/edital_screen.dart';
import 'package:app_estudos/features/busca/busca_screen.dart';
import 'package:app_estudos/features/caderno/questoes_orfas_screen.dart';
import 'package:app_estudos/features/leituras/leituras_screen.dart';
import 'package:app_estudos/features/mapa/mapa_estudos_screen.dart';
import 'package:app_estudos/features/materias/materias_screen.dart';
import 'package:app_estudos/features/planejamento/planejamento_screen.dart';
import 'package:app_estudos/features/resumos/resumos_screen.dart';
import 'package:app_estudos/features/simulados/prova_screen.dart';
import 'package:app_estudos/features/revisoes/revisoes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Captura de telas para revisão visual — NÃO é teste de regressão.
/// Roda só sob demanda:
///   flutter test --tags screenshots --update-goldens
/// As imagens saem em test/goldens/. Excluído da suíte normal por tag para
/// não transformar mudança de pixel em build vermelho.
/// Data congelada do cenário. O seed E o `hojeProvider` usam esta mesma data:
/// antes o seed vinha de `DateTime.now()` enquanto os goldens ficavam gravados
/// de um dia específico, então heatmap, streak e rótulos de data deslocavam a
/// cada dia que passava e o teste falhava sozinho sem ninguém ter mexido no
/// código. Golden que apodrece treina o time a ignorar falha vermelha.
final _hojeFixo = DateTime(2026, 7, 24);

void main() {
  late Directory dir;

  setUpAll(() async {
    // Sem fontes reais o flutter_test desenha caixas no lugar do texto. As do
    // Material vêm do cache do SDK; o caminho é resolvido em runtime para o
    // teste não ficar preso à máquina de quem gerou as imagens.
    final mf = _materialFonts();
    await _carregarFonte('Roboto', [
      if (mf != null) ...[
        '$mf/Roboto-Regular.ttf',
        '$mf/Roboto-Medium.ttf',
        '$mf/Roboto-Bold.ttf',
      ],
    ]);
    await _carregarFonte('Display', ['fonts/SpaceGrotesk-Variable.ttf']);
    await _carregarFonte('MaterialIcons', [
      if (mf != null) '$mf/MaterialIcons-Regular.otf',
    ]);
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_shot_');
    Hive.init(dir.path);
    await HiveBoxes.openAll();
    await HiveBoxes.migrarAmbientes();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  Future<void> semear() async {
    final hoje = _hojeFixo;
    DateTime dia(int atras) =>
        DateTime(hoje.year, hoje.month, hoje.day - atras, 9);

    final materias = [
      ('m1', 'Direito Constitucional', 5, 0),
      ('m2', 'Administração Financeira e Orçamentária', 4, 1),
      ('m3', 'Língua Portuguesa', 3, 2),
      ('m4', 'Raciocínio Lógico', 2, 3),
    ];
    for (final (id, nome, peso, slot) in materias) {
      await Hive.box<Map>(HiveBoxes.materias).put(
        id,
        Materia(
          id: id,
          nome: nome,
          peso: peso,
          corSlot: slot,
          intimidade: id == 'm2' ? 4 : 3,
          criadaEm: dia(120),
        ).toJson(),
      );
    }
    await Hive.box<Map>(HiveBoxes.topicos).put(
      't1',
      Topico(
        id: 't1',
        materiaId: 'm1',
        nome: 'Controle de constitucionalidade',
      ).toJson(),
    );
    await Hive.box<Map>(HiveBoxes.aulas).put(
      'a1',
      Aula(
        id: 'a1',
        materiaId: 'm1',
        nome: 'Aula 12 — Remédios constitucionais',
        paginasTotais: 40,
        paginasLidas: 40,
        concluida: true,
        dataConclusao: dia(9),
      ).toJson(),
    );

    // ~6 semanas de estudo com constância boa e desempenho variado.
    final box = Hive.box<Map>(HiveBoxes.registros);
    var n = 0;
    for (var d = 41; d >= 0; d--) {
      if (d % 7 == 6) continue; // um dia de folga por semana
      final mid = ['m1', 'm2', 'm3', 'm4'][d % 4];
      final pratica = d % 3 != 0;
      final questoes = pratica ? 20 : null;
      final acertos = pratica ? (mid == 'm2' ? 12 : 17) : null;
      await box.put(
        'r${n++}',
        RegistroHora(
          id: 'r$n',
          data: dia(d),
          materiaId: mid,
          topicoId: mid == 'm1' ? 't1' : null,
          tipo: pratica ? TipoEstudo.pratica : TipoEstudo.teoria,
          tarefa: pratica ? 'Questões' : 'Teoria + resumo',
          minutos: 95 + (d % 5) * 15,
          questoes: questoes,
          acertos: acertos,
        ).toJson(),
      );
    }


    // Edital de verdade (mais de um tópico) e caderno de erros com fila:
    // sem isso as telas novas ficavam sem cenário e o golden não provaria nada.
    final tb = Hive.box<Map>(HiveBoxes.topicos);
    for (final (id, mid, nome, peso, concluido) in [
      ('t2', 'm1', 'Direitos e garantias fundamentais', 5, false),
      ('t3', 'm1', 'Organização do Estado', 4, false),
      ('t4', 'm2', 'Lei 4.320/64', 5, false),
      ('t5', 'm2', 'Lei de Responsabilidade Fiscal', 4, false),
      ('t6', 'm3', 'Concordância verbal', 3, true),
      ('t7', 'm4', 'Probabilidade', 2, false),
    ]) {
      await tb.put(
        id,
        Topico(
          id: id,
          materiaId: mid,
          nome: nome,
          peso: peso,
          concluido: concluido,
        ).toJson(),
      );
    }
    final qb = Hive.box<Map>(HiveBoxes.questoesErradas);
    for (final (i, mid, tid, enunciado, banca) in [
      (1, 'm1', 't2', 'O direito de greve dos servidores públicos é norma de eficácia contida?', 'CEBRASPE'),
      (2, 'm2', 't4', 'Despesa de exercícios anteriores depende de crédito especial?', 'FGV'),
      (3, 'm2', 't5', 'A LRF fixa limite de despesa com pessoal em 60% da RCL para a União?', 'CEBRASPE'),
      (4, 'm4', 't7', 'Em um lançamento de dois dados, qual a probabilidade da soma ser 7?', 'FCC'),
    ]) {
      await qb.put(
        'q$i',
        QuestaoErrada(
          id: 'q$i',
          materiaId: mid,
          topicoId: tid,
          enunciado: enunciado,
          respostaMarcada: 'C',
          respostaCorreta: 'E',
          comentario: 'Troquei eficácia contida por limitada.',
          banca: banca,
          ano: 2024,
          orgao: 'TRF',
          criadaEm: dia(3),
          proximaTentativa: dia(0),
        ).toJson(),
      );
    }

    final rb = Hive.box<Map>(HiveBoxes.revisoes);
    await rb.put(
      'rv1',
      Revisao(
        id: 'rv1',
        materiaId: 'm1',
        topicoId: 't1',
        aulaId: 'a1',
        titulo: 'Aula 12 — Remédios constitucionais (7d)',
        dataAgendada: dia(3),
        intervaloDias: 7,
      ).toJson(),
    );
    await rb.put(
      'rv2',
      Revisao(
        id: 'rv2',
        materiaId: 'm2',
        titulo: 'Receita pública (15d)',
        dataAgendada: dia(1),
        intervaloDias: 15,
      ).toJson(),
    );
    await rb.put(
      'rv3',
      Revisao(
        id: 'rv3',
        materiaId: 'm3',
        titulo: 'Crase (30d)',
        dataAgendada: dia(-4),
        intervaloDias: 30,
      ).toJson(),
    );
    await rb.put(
      'rv4',
      Revisao(
        id: 'rv4',
        materiaId: 'm4',
        titulo: 'Proposições (7d)',
        dataAgendada: dia(-1),
        intervaloDias: 7,
        feita: true,
        dataConclusao: dia(1),
      ).toJson(),
    );
  }

  /// [antesDeCapturar] roda com a árvore já montada e assentada — é onde a
  /// tela recebe interação (digitar na busca, por exemplo) antes do snapshot.
  Future<void> capturar(
    WidgetTester tester,
    Widget tela,
    String nome, {
    Size tamanho = const Size(1180, 1500),
    Future<void> Function(WidgetTester tester)? antesDeCapturar,
    // Congela `agoraProvider` (dashboard_providers.dart) além do
    // `hojeProvider` de sempre — só a prova em execução precisa disto, pra
    // não ler `DateTime.now()` no cronômetro regressivo. `Override` (tipo de
    // retorno de `overrideWithValue`) não é exportado pelo barrel público do
    // Riverpod, então o parâmetro é tipado pelo valor concreto que a tela
    // precisa em vez do tipo genérico. Null por padrão: os 9 goldens
    // originais não passam nada aqui e continuam vendo a MESMA lista de
    // overrides de antes.
    DateTime Function()? agoraFixo,
    // A fase de execução da prova (prova_screen.dart) mantém um
    // Timer.periodic(1s) vivo por baixo — pumpAndSettle nunca assenta
    // enquanto ele reagenda frame, então aquele teste pede pump() simples em
    // vez de settle. Todo o resto continua no default (true == pumpAndSettle,
    // comportamento idêntico ao de antes desta flag existir).
    bool assentar = true,
  }) async {
    tester.view.physicalSize = tamanho;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        // Congela "hoje" na mesma data do seed. Sem isto o app renderizaria a
        // data real da máquina sobre dados semeados em [_hojeFixo], e o golden
        // voltaria a deslocar todo dia. Bônus: cancela o Timer de meia-noite
        // do hojeProvider (M-06), que deixaria timer pendente no teste.
        overrides: [
          hojeProvider.overrideWithValue(_hojeFixo),
          if (agoraFixo != null) agoraProvider.overrideWithValue(agoraFixo),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('pt', 'BR'),
          builder: (context, child) =>
              LuminaBackground(child: child ?? const SizedBox.shrink()),
          home: tela,
        ),
      ),
    );
    if (assentar) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    if (antesDeCapturar != null) {
      await antesDeCapturar(tester);
      if (assentar) {
        await tester.pumpAndSettle();
      } else {
        await tester.pump();
      }
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$nome.png'),
    );
  }

  /// Prova JÁ FINALIZADA, direto na fase de correção.
  ///
  /// A fase de EXECUÇÃO não é capturável de forma estável: o cronômetro
  /// regressivo lê `DateTime.now()` a cada segundo (prova_screen.dart:397) e
  /// mantém um `Timer.periodic` vivo — o golden mudaria a cada execução e o
  /// timer pendente derrubaria o teste. A correção é justamente a fase que
  /// concentra o comportamento novo (gabarito persistido, lista lazy,
  /// pluralização), então é ela que vale congelar.
  Future<void> semearProvaEmCorrecao() async {
    final iniciada = DateTime(
      _hojeFixo.year,
      _hojeFixo.month,
      _hojeFixo.day,
      14,
    );
    await Hive.box<Map>(HiveBoxes.execucaoProva).put(
      'atual',
      ExecucaoProva(
        id: 'exec-golden',
        nome: 'Simulado TRF — 1º turno',
        banca: 'CEBRASPE',
        iniciadaEm: iniciada,
        duracaoMinutos: 120,
        finalizadaEm: iniciada.add(const Duration(minutes: 96)),
        itens: [
          for (var n = 1; n <= 6; n++)
            ItemProva(
              numero: n,
              materiaId: n <= 3 ? 'm1' : 'm2',
              respostaMarcada: const ['A', 'C', 'E', 'B', 'D', 'A'][n - 1],
              gabarito: n <= 4 ? const ['A', 'C', 'B', 'B'][n - 1] : null,
            ),
        ],
      ).toJson(),
    );
  }

  /// Duas questões com matéria inexistente e uma com tópico inexistente — o
  /// resíduo que sobra quando o usuário exclui matéria/tópico e o caderno
  /// preserva o enunciado escrito à mão.
  Future<void> semearQuestoesOrfas() async {
    final box = Hive.box<Map>(HiveBoxes.questoesErradas);
    final base = DateTime(_hojeFixo.year, _hojeFixo.month, _hojeFixo.day - 5);
    for (final (id, materiaId, topicoId, enunciado) in [
      (
        'orfa-1',
        'materia-apagada',
        null,
        'A vedação ao confisco alcança as taxas?',
      ),
      (
        'orfa-2',
        'materia-apagada',
        null,
        'Servidor em estágio probatório pode ser cedido?',
      ),
      (
        'orfa-3',
        'm1',
        'topico-apagado',
        'O rol do art. 5º da CF é taxativo?',
      ),
    ]) {
      await box.put(
        id,
        QuestaoErrada(
          id: id,
          materiaId: materiaId,
          topicoId: topicoId,
          enunciado: enunciado,
          comentario: 'Confundi com a regra geral.',
          banca: 'FGV',
          ano: 2025,
          criadaEm: base,
          proximaTentativa: base,
        ).toJson(),
      );
    }
  }

  testWidgets('dashboard com dados', (tester) async {
    await tester.runAsync(semear);
    await capturar(tester, const DashboardScreen(), '01_dashboard');
  });

  testWidgets('caderno de erros', (tester) async {
    await tester.runAsync(semear);
    await capturar(
      tester,
      const CadernoScreen(),
      '04_caderno_erros',
      tamanho: const Size(900, 1000),
    );
  });

  testWidgets('edital verticalizado', (tester) async {
    await tester.runAsync(semear);
    await capturar(
      tester,
      const EditalScreen(),
      '05_edital',
      tamanho: const Size(900, 1200),
    );
  });

  testWidgets('prova cronometrada', (tester) async {
    await tester.runAsync(semear);
    await capturar(
      tester,
      const ProvaScreen(),
      '06_prova',
      tamanho: const Size(900, 700),
    );
  });

  testWidgets('prova — correção com gabarito', (tester) async {
    await tester.runAsync(() async {
      await semear();
      await semearProvaEmCorrecao();
    });
    await capturar(
      tester,
      const ProvaScreen(),
      '07_prova_correcao',
      tamanho: const Size(900, 1000),
    );
  });

  testWidgets('questões órfãs', (tester) async {
    await tester.runAsync(() async {
      await semear();
      await semearQuestoesOrfas();
    });
    await capturar(
      tester,
      const QuestoesOrfasScreen(),
      '08_questoes_orfas',
      tamanho: const Size(900, 800),
    );
  });

  testWidgets('busca global com resultados', (tester) async {
    // O campo de busca tem `autofocus`, e o cursor piscando muda pixel entre
    // execuções — o golden apodreceria sozinho sem isto.
    EditableText.debugDeterministicCursor = true;
    addTearDown(() => EditableText.debugDeterministicCursor = false);
    await tester.runAsync(() async {
      await semear();
      await semearQuestoesOrfas();
    });
    await capturar(
      tester,
      const BuscaScreen(),
      '09_busca',
      tamanho: const Size(900, 900),
      antesDeCapturar: (t) async {
        await t.enterText(find.byType(TextField).first, 'constitu');
      },
    );
  });

  testWidgets('dashboard vazio (primeira abertura)', (tester) async {
    await capturar(
      tester,
      const DashboardScreen(),
      '02_dashboard_vazio',
      tamanho: const Size(900, 800),
    );
  });

  testWidgets('revisões', (tester) async {
    await tester.runAsync(semear);
    await capturar(
      tester,
      const RevisoesScreen(),
      '03_revisoes',
      tamanho: const Size(900, 1000),
    );
  });

  // ---------------------------------------------------------------------
  // Telas adicionadas depois da leva inicial (10_ em diante). Seeds
  // específicos de cada uma ficam aqui, nunca em `semear()` — os goldens
  // 01..09 acima não podem mudar 1 pixel por causa de dado que eles nem
  // exibem.
  // ---------------------------------------------------------------------

  /// Prova cronometrada AINDA RODANDO (fase de execução) — companion de
  /// [semearProvaEmCorrecao], mas sem `finalizadaEm`: `ExecucaoProva.ativa`
  /// fica true e `ProvaScreen.initState` abre direto na folha de respostas
  /// em vez da correção.
  Future<void> semearProvaEmExecucao() async {
    final iniciada = DateTime(
      _hojeFixo.year,
      _hojeFixo.month,
      _hojeFixo.day,
      14,
    );
    await Hive.box<Map>(HiveBoxes.execucaoProva).put(
      'atual',
      ExecucaoProva(
        id: 'exec-golden-execucao',
        nome: 'Simulado TRF — 1º turno',
        banca: 'CEBRASPE',
        iniciadaEm: iniciada,
        duracaoMinutos: 120,
        itens: [
          for (var n = 1; n <= 6; n++)
            ItemProva(
              numero: n,
              materiaId: n <= 3 ? 'm1' : 'm2',
              respostaMarcada: n <= 3 ? const ['A', 'C', 'E'][n - 1] : null,
            ),
        ],
      ).toJson(),
    );
  }

  testWidgets('prova em execução', (tester) async {
    // A fase de execução mantém um Timer.periodic(1s) vivo (prova_screen.dart)
    // só para redesenhar o relógio — o valor exibido vem de `agoraProvider`,
    // nunca do timer em si. Por isso: (1) congela `agoraProvider` num
    // instante fixo, igual ao `hojeProvider`; (2) pump() simples em vez de
    // pumpAndSettle — um Timer real que nunca termina faz pumpAndSettle
    // girar sem nunca assentar; (3) desmonta a árvore no fim para o
    // dispose() cancelar o Timer antes do tearDown, senão o teste quebra com
    // "A Timer is still pending".
    final instanteFixo = DateTime(
      _hojeFixo.year,
      _hojeFixo.month,
      _hojeFixo.day,
      14,
      30,
    );
    await tester.runAsync(() async {
      await semear();
      await semearProvaEmExecucao();
    });
    await capturar(
      tester,
      const ProvaScreen(),
      '10_prova_execucao',
      tamanho: const Size(900, 700),
      agoraFixo: () => instanteFixo,
      assentar: false,
    );
    // Desmonta pra disparar dispose() e cancelar o Timer antes do tearDown.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('cronômetro parado', (tester) async {
    // CronometroController só liga o Timer.periodic(500ms) depois de
    // iniciar()/retomar(). Sem tocar em HiveBoxes.cronometro o estado nasce
    // "parado" (Duration zero) direto no build() — nenhum Timer chega a
    // existir, então esta tela não precisa do truque pump()/desmontar da
    // prova em execução acima.
    await tester.runAsync(semear);
    await capturar(
      tester,
      const CronometroScreen(),
      '11_cronometro',
      tamanho: const Size(900, 900),
    );
  });

  /// Cronograma semanal fixo — ver nota de determinismo no teste abaixo.
  Future<void> semearPlanejamento() async {
    await Hive.box<Map>(HiveBoxes.planejamento).put('semana', {
      '1': 120,
      '2': 90,
      '3': 120,
      '4': 90,
      '5': 120,
      '6': 60,
    });
  }

  testWidgets('planejamento', (tester) async {
    // ACHADO fora das duas armadilhas já mapeadas: PlanejamentoScreen.build()
    // (lib/features/planejamento/planejamento_screen.dart) usa
    // `DateTime.now()` real para "feito nesta semana" — não respeita o
    // `hojeProvider` congelado. Na prática o golden não apodrece: os
    // registros do `semear()` terminam em `_hojeFixo` (24/07/2026), e
    // qualquer execução real deste teste acontece depois disso — a "semana
    // corrente" do relógio de verdade nunca mais volta a cruzar com eles
    // (o intervalo só cresce com o tempo, nunca encolhe), então "feito"
    // fica em 0min hoje e permanece 0min em qualquer execução futura. Já o
    // "Ciclo sugerido" nem corre esse risco: cicloPorUtilidade é chamado
    // aqui SEM `referencia`, então o esquecimento temporal do Elo
    // (DominioService) nunca entra em jogo — é função pura dos dados
    // semeados.
    await tester.runAsync(() async {
      await semear();
      await semearPlanejamento();
    });
    await capturar(
      tester,
      const PlanejamentoScreen(),
      '12_planejamento',
      tamanho: const Size(900, 1100),
    );
  });

  testWidgets('mapa de estudos', (tester) async {
    await tester.runAsync(semear);
    await capturar(
      tester,
      const MapaEstudosScreen(),
      '13_mapa_estudos',
      tamanho: const Size(900, 800),
    );
  });

  testWidgets('matérias', (tester) async {
    await tester.runAsync(semear);
    await capturar(
      tester,
      const MateriasScreen(),
      '14_materias',
      tamanho: const Size(900, 700),
    );
  });

  testWidgets('aulas de uma matéria', (tester) async {
    // AulasScreen recebe a Materia por parâmetro (não busca por id) — lida
    // de volta do Hive já semeado em vez de duplicar os campos de `semear()`
    // aqui, pra não desalinhar se um deles mudar.
    final materiaM1 = await tester.runAsync(() async {
      await semear();
      final raw = Hive.box<Map>(HiveBoxes.materias).get('m1')!;
      return Materia.fromJson(Map<String, dynamic>.from(raw));
    });
    await capturar(
      tester,
      AulasScreen(materia: materiaM1!),
      '15_aulas',
      tamanho: const Size(900, 500),
    );
  });

  Future<void> semearLeituras() async {
    final box = Hive.box<Map>(HiveBoxes.leituras);
    await box.put(
      'lt1',
      Leitura(
        id: 'lt1',
        titulo: 'Manual de Direito Constitucional',
        materiaId: 'm1',
        paginaInicio: 1,
        paginaFim: 200,
        partes: 5,
        partesConcluidas: const [true, true, false, false, false],
        sessoes: [
          SessaoLeitura(
            data: _hojeFixo.subtract(const Duration(days: 3)),
            paginas: 40,
            minutos: 90,
          ),
          SessaoLeitura(
            data: _hojeFixo.subtract(const Duration(days: 1)),
            paginas: 35,
            minutos: 80,
          ),
        ],
      ).toJson(),
    );
    await box.put(
      'lt2',
      Leitura(
        id: 'lt2',
        titulo: 'Lei 4.320/64 esquematizada',
        materiaId: 'm2',
        paginaInicio: 1,
        paginaFim: 80,
        partes: 4,
        partesConcluidas: const [false, false, false, false],
      ).toJson(),
    );
  }

  testWidgets('leituras', (tester) async {
    await tester.runAsync(() async {
      await semear();
      await semearLeituras();
    });
    await capturar(
      tester,
      const LeiturasScreen(),
      '16_leituras',
      tamanho: const Size(900, 700),
    );
  });

  Future<void> semearResumo() async {
    await Hive.box<Map>(HiveBoxes.resumos).put(
      'DC',
      Resumo(
        sigla: 'DC',
        nome: 'Direito Constitucional',
        texto:
            'Controle de constitucionalidade: difuso (qualquer juiz, via '
            'incidental) e concentrado (STF, ação direta).',
        atualizadoEm: _hojeFixo.subtract(const Duration(days: 2)),
      ).toJson(),
    );
  }

  testWidgets('resumos por matéria', (tester) async {
    await tester.runAsync(() async {
      await semear();
      await semearResumo();
    });
    await capturar(
      tester,
      const ResumosScreen(),
      '17_resumos',
      tamanho: const Size(900, 700),
    );
  });

  Future<void> semearSegundoAmbiente() async {
    await Hive.box<Map>(HiveBoxes.ambientes).put(
      'amb2',
      Ambiente(
        id: 'amb2',
        nome: 'Concurso SEFAZ-RN 2026',
        corSlot: 1,
        criadoEm: _hojeFixo.subtract(const Duration(days: 30)),
        dataProva: _hojeFixo.add(const Duration(days: 60)),
      ).toJson(),
    );
  }

  testWidgets('ambientes', (tester) async {
    await tester.runAsync(() async {
      await semear();
      await semearSegundoAmbiente();
    });
    await capturar(
      tester,
      const AmbientesScreen(),
      '18_ambientes',
      tamanho: const Size(900, 500),
    );
  });

  testWidgets('configurações', (tester) async {
    await capturar(
      tester,
      const ConfiguracoesScreen(),
      '19_configuracoes',
      tamanho: const Size(900, 1100),
    );
  });
}

/// Pasta material_fonts do SDK: FLUTTER_ROOT quando definido, senão deduz a
/// partir do `flutter` no PATH. null quando não achar (aí o texto sai como
/// caixa, mas o teste não quebra).
String? _materialFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final candidatos = <String>[
    if (root != null && root.isNotEmpty) root,
    for (final p in (Platform.environment['PATH'] ?? '').split(
      Platform.isWindows ? ';' : ':',
    ))
      if (p.endsWith('flutter${Platform.pathSeparator}bin') ||
          p.endsWith('flutter/bin'))
        p.substring(0, p.length - 4),
  ];
  for (final c in candidatos) {
    final d = Directory(
      '$c${Platform.pathSeparator}bin${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}artifacts${Platform.pathSeparator}material_fonts',
    );
    if (d.existsSync()) return d.path;
  }
  return null;
}

Future<void> _carregarFonte(String familia, List<String> caminhos) async {
  final loader = FontLoader(familia);
  var algum = false;
  for (final c in caminhos) {
    final f = File(c);
    if (!f.existsSync()) continue;
    algum = true;
    final bytes = await f.readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  if (algum) await loader.load();
}
