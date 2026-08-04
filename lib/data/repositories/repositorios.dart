import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../local/hive_boxes.dart';
import '../models/ambiente.dart';
import '../models/aula.dart';
import '../models/execucao_prova.dart';
import '../models/leitura.dart';
import '../models/materia.dart';
import '../models/registro_hora.dart';
import '../models/resumo.dart';
import '../models/revisao.dart';
import '../models/questao_errada.dart';
import '../models/simulado.dart';
import '../models/topico.dart';

/// Repository pattern sobre Hive: o box é a fonte persistida, o state do
/// Notifier é a projeção em memória que a UI observa.
abstract class _HiveRepositorio<T> extends Notifier<List<T>> {
  String get boxName;
  T fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson(T item);
  String idDe(T item);
  int comparar(T a, T b);

  // Metadados de sincronização futura. Repositórios de entidades
  // sincronizáveis sobrescrevem os três: salvar passa a carimbar a última
  // modificação e remover vira tombstone (o registro fica no box com marca
  // de exclusão — um sync futuro precisa propagar deletes — mas some do
  // state). O default preserva o comportamento clássico: sem carimbo,
  // hard delete.
  T Function(T item, DateTime agora)? get carimbarAtualizacao => null;
  T Function(T item, DateTime agora)? get marcarExclusao => null;
  bool estaExcluido(T item) => false;

  Box<Map> get _box => Hive.box<Map>(boxName);

  @override
  List<T> build() => _carregar();

  // Isola erro por registro: Hive não tem transação entre boxes, então um
  // crash no meio de uma escrita anterior pode deixar um item malformado no
  // disco. Sem isso, um único registro corrompido derrubava a leitura da
  // coleção inteira (toda tela que dependesse dela quebrava).
  List<T> _carregar() {
    final itens = <T>[];
    for (final raw in _box.values) {
      try {
        final item = fromJson(Map<String, dynamic>.from(raw));
        if (!estaExcluido(item)) itens.add(item);
      } catch (e) {
        debugPrint('$boxName: registro corrompido ignorado ($e)');
      }
    }
    itens.sort(comparar);
    return itens;
  }

  // Escritas pontuais atualizam a projeção em memória de forma incremental:
  // o box é a fonte persistida, mas re-deserializar/reordenar a coleção
  // inteira a cada salvar custava O(box) por escrita. _carregar() fica para
  // o build() e para restaurações completas.

  Future<void> salvar(T item) async {
    final carimbar = carimbarAtualizacao;
    final gravado = carimbar == null ? item : carimbar(item, DateTime.now());
    await _box.put(idDe(gravado), toJson(gravado));
    final id = idDe(gravado);
    state = [
      for (final e in state)
        if (idDe(e) != id) e,
      gravado,
    ]..sort(comparar);
  }

  Future<void> remover(String id) async {
    final marcar = marcarExclusao;
    if (marcar == null) {
      await _box.delete(id);
    } else {
      // Tombstone: regrava o registro marcado em vez de apagar.
      final vivos = state.where((e) => idDe(e) == id).toList();
      if (vivos.isNotEmpty) {
        await _box.put(id, toJson(marcar(vivos.first, DateTime.now())));
      } else {
        await _box.delete(id);
      }
    }
    state = [
      for (final e in state)
        if (idDe(e) != id) e,
    ];
  }

  /// Restaura backup: apaga tudo e grava a coleção importada.
  Future<void> substituirTudo(List<T> itens) async {
    await _box.clear();
    await _box.putAll({for (final item in itens) idDe(item): toJson(item)});
    state = _carregar();
  }

  /// Import incremental: grava/sobrescreve os itens SEM apagar o resto.
  Future<void> mesclar(List<T> itens) async {
    if (itens.isEmpty) return;
    await _box.putAll({for (final item in itens) idDe(item): toJson(item)});
    final novos = {for (final item in itens) idDe(item): item};
    state = [
      for (final e in state)
        if (!novos.containsKey(idDe(e))) e,
      ...novos.values,
    ]..sort(comparar);
  }

  /// Remoção em lote por predicado (cascatas): um deleteAll/putAll, uma
  /// atualização de state. Entidades com tombstone marcam em vez de apagar.
  Future<void> removerOnde(bool Function(T) teste) async {
    final alvos = [
      for (final e in state)
        if (teste(e)) e,
    ];
    if (alvos.isEmpty) return;
    final marcar = marcarExclusao;
    if (marcar == null) {
      await _box.deleteAll([for (final e in alvos) idDe(e)]);
    } else {
      final agora = DateTime.now();
      await _box.putAll({
        for (final e in alvos) idDe(e): toJson(marcar(e, agora)),
      });
    }
    final removidos = {for (final e in alvos) idDe(e)};
    state = [
      for (final e in state)
        if (!removidos.contains(idDe(e))) e,
    ];
  }
}

class AmbientesRepositorio extends _HiveRepositorio<Ambiente> {
  @override
  String get boxName => HiveBoxes.ambientes;
  @override
  Ambiente fromJson(Map<String, dynamic> json) => Ambiente.fromJson(json);
  @override
  Map<String, dynamic> toJson(Ambiente item) => item.toJson();
  @override
  String idDe(Ambiente item) => item.id;
  @override
  int comparar(Ambiente a, Ambiente b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  int proximoCorSlot() {
    final usados = state.map((a) => a.corSlot).toList();
    for (var slot = 0; slot < 8; slot++) {
      if (!usados.contains(slot)) return slot;
    }
    return state.length % 8;
  }
}

class MateriasRepositorio extends _HiveRepositorio<Materia> {
  @override
  String get boxName => HiveBoxes.materias;
  @override
  Materia fromJson(Map<String, dynamic> json) => Materia.fromJson(json);
  @override
  Map<String, dynamic> toJson(Materia item) => item.toJson();
  @override
  String idDe(Materia item) => item.id;
  @override
  int comparar(Materia a, Materia b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  @override
  Materia Function(Materia, DateTime) get carimbarAtualizacao =>
      (m, agora) => m.comAtualizacao(agora);
  @override
  Materia Function(Materia, DateTime) get marcarExclusao =>
      (m, agora) => m.comExclusao(agora);
  @override
  bool estaExcluido(Materia item) => item.excluidaEm != null;

  /// Próximo slot de cor livre na ordem fixa da paleta (0-7, com repetição
  /// se passar de 8 matérias).
  int proximoCorSlot() {
    final usados = state.map((m) => m.corSlot).toList();
    for (var slot = 0; slot < 8; slot++) {
      if (!usados.contains(slot)) return slot;
    }
    return state.length % 8;
  }

  /// Peso do edital por matéria INCLUINDO as excluídas (tombstone).
  ///
  /// A cascata de exclusão preserva os registros de horas de propósito, mas
  /// tira a matéria do `state` — e o XP ponderado, montado só das vivas,
  /// degradava aqueles minutos para ×1.0 e DERRUBAVA o XP total (uma matéria
  /// peso 5 valia −9% do acumulado, podendo rebaixar o nível). O tombstone
  /// mantém o registro no box, então o peso histórico continua disponível sem
  /// nada de novo ser persistido e sem ressuscitar a matéria na UI.
  Map<String, int> pesosHistoricos() {
    final pesos = <String, int>{};
    for (final raw in _box.values) {
      try {
        final m = Materia.fromJson(Map<String, dynamic>.from(raw));
        pesos[m.id] = m.peso;
      } catch (_) {
        // Registro corrompido já é ignorado na leitura da coleção.
      }
    }
    return pesos;
  }

  /// Matérias INCLUINDO as excluídas (tombstone), por id.
  ///
  /// Mesma leitura de box de [pesosHistoricos], para o export de BI: a
  /// cascata preserva os registros de horas, então o modelo estrela tinha de
  /// inventar uma linha de dimensão sintética — rotulada igual para TODAS as
  /// matérias excluídas, o que fundia duas matérias distintas numa barra só
  /// em qualquer gráfico por nome. O tombstone guarda nome, peso, ambiente e
  /// intimidade intactos; o export só precisava enxergá-lo.
  ///
  /// Deliberadamente NÃO reescrito como base de [pesosHistoricos]: aquele
  /// método alimenta o XP, e a economia de meia dúzia de linhas não paga o
  /// risco de mexer no caminho da gamificação.
  Map<String, Materia> historicas() {
    final materias = <String, Materia>{};
    for (final raw in _box.values) {
      try {
        final m = Materia.fromJson(Map<String, dynamic>.from(raw));
        materias[m.id] = m;
      } catch (_) {
        // Registro corrompido já é ignorado na leitura da coleção.
      }
    }
    return materias;
  }
}

class TopicosRepositorio extends _HiveRepositorio<Topico> {
  @override
  String get boxName => HiveBoxes.topicos;
  @override
  Topico fromJson(Map<String, dynamic> json) => Topico.fromJson(json);
  @override
  Map<String, dynamic> toJson(Topico item) => item.toJson();
  @override
  String idDe(Topico item) => item.id;
  @override
  int comparar(Topico a, Topico b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  List<Topico> daMateria(String materiaId) =>
      state.where((t) => t.materiaId == materiaId).toList();
}

class AulasRepositorio extends _HiveRepositorio<Aula> {
  @override
  String get boxName => HiveBoxes.aulas;
  @override
  Aula fromJson(Map<String, dynamic> json) => Aula.fromJson(json);
  @override
  Map<String, dynamic> toJson(Aula item) => item.toJson();
  @override
  String idDe(Aula item) => item.id;
  @override
  int comparar(Aula a, Aula b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  List<Aula> daMateria(String materiaId) =>
      state.where((a) => a.materiaId == materiaId).toList();
}

class RegistrosRepositorio extends _HiveRepositorio<RegistroHora> {
  @override
  String get boxName => HiveBoxes.registros;
  @override
  RegistroHora fromJson(Map<String, dynamic> json) =>
      RegistroHora.fromJson(json);
  @override
  Map<String, dynamic> toJson(RegistroHora item) => item.toJson();
  @override
  String idDe(RegistroHora item) => item.id;
  @override
  int comparar(RegistroHora a, RegistroHora b) => b.data.compareTo(a.data);

  @override
  RegistroHora Function(RegistroHora, DateTime) get carimbarAtualizacao =>
      (r, agora) => r.comAtualizacao(agora);
  @override
  RegistroHora Function(RegistroHora, DateTime) get marcarExclusao =>
      (r, agora) => r.comExclusao(agora);
  @override
  bool estaExcluido(RegistroHora item) => item.excluidoEm != null;
}

class RevisoesRepositorio extends _HiveRepositorio<Revisao> {
  @override
  String get boxName => HiveBoxes.revisoes;
  @override
  Revisao fromJson(Map<String, dynamic> json) => Revisao.fromJson(json);
  @override
  Map<String, dynamic> toJson(Revisao item) => item.toJson();
  @override
  String idDe(Revisao item) => item.id;
  @override
  int comparar(Revisao a, Revisao b) =>
      a.dataAgendada.compareTo(b.dataAgendada);
}

class LeiturasRepositorio extends _HiveRepositorio<Leitura> {
  @override
  String get boxName => HiveBoxes.leituras;
  @override
  Leitura fromJson(Map<String, dynamic> json) => Leitura.fromJson(json);
  @override
  Map<String, dynamic> toJson(Leitura item) => item.toJson();
  @override
  String idDe(Leitura item) => item.id;
  @override
  int comparar(Leitura a, Leitura b) =>
      a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
}

class SimuladosRepositorio extends _HiveRepositorio<Simulado> {
  @override
  String get boxName => HiveBoxes.simulados;
  @override
  Simulado fromJson(Map<String, dynamic> json) => Simulado.fromJson(json);
  @override
  Map<String, dynamic> toJson(Simulado item) => item.toJson();
  @override
  String idDe(Simulado item) => item.id;
  @override
  int comparar(Simulado a, Simulado b) => b.data.compareTo(a.data);
}

class ResumosRepositorio extends _HiveRepositorio<Resumo> {
  @override
  String get boxName => HiveBoxes.resumos;
  @override
  Resumo fromJson(Map<String, dynamic> json) => Resumo.fromJson(json);
  @override
  Map<String, dynamic> toJson(Resumo item) => item.toJson();
  @override
  String idDe(Resumo item) => item.sigla;
  @override
  int comparar(Resumo a, Resumo b) =>
      a.nome.toLowerCase().compareTo(b.nome.toLowerCase());

  /// Grava o texto da página carimbando a data de edição.
  Future<void> salvarTexto(Resumo pagina, String texto) =>
      salvar(pagina.copyWith(texto: texto, atualizadoEm: DateTime.now()));
}

final resumosProvider = NotifierProvider<ResumosRepositorio, List<Resumo>>(
  ResumosRepositorio.new,
);

final simuladosProvider =
    NotifierProvider<SimuladosRepositorio, List<Simulado>>(
      SimuladosRepositorio.new,
    );
final ambientesProvider =
    NotifierProvider<AmbientesRepositorio, List<Ambiente>>(
      AmbientesRepositorio.new,
    );
final materiasProvider = NotifierProvider<MateriasRepositorio, List<Materia>>(
  MateriasRepositorio.new,
);
final leiturasProvider = NotifierProvider<LeiturasRepositorio, List<Leitura>>(
  LeiturasRepositorio.new,
);
final topicosProvider = NotifierProvider<TopicosRepositorio, List<Topico>>(
  TopicosRepositorio.new,
);
final aulasProvider = NotifierProvider<AulasRepositorio, List<Aula>>(
  AulasRepositorio.new,
);
final registrosProvider =
    NotifierProvider<RegistrosRepositorio, List<RegistroHora>>(
      RegistrosRepositorio.new,
    );
final revisoesProvider = NotifierProvider<RevisoesRepositorio, List<Revisao>>(
  RevisoesRepositorio.new,
);

/// Caderno de erros. Ordem: mais urgente primeiro (data de retomada asc),
/// desempate pela criação — a tela abre já na fila do dia.
class QuestoesErradasRepositorio extends _HiveRepositorio<QuestaoErrada> {
  @override
  String get boxName => HiveBoxes.questoesErradas;
  @override
  QuestaoErrada fromJson(Map<String, dynamic> json) =>
      QuestaoErrada.fromJson(json);
  @override
  Map<String, dynamic> toJson(QuestaoErrada item) => item.toJson();
  @override
  String idDe(QuestaoErrada item) => item.id;
  @override
  int comparar(QuestaoErrada a, QuestaoErrada b) {
    final porData = a.proximaTentativa.compareTo(b.proximaTentativa);
    return porData != 0 ? porData : a.criadaEm.compareTo(b.criadaEm);
  }

  List<QuestaoErrada> daMateria(String materiaId) => [
    for (final q in state)
      if (q.materiaId == materiaId) q,
  ];

  List<QuestaoErrada> get ativas => [
    for (final q in state)
      if (!q.arquivada) q,
  ];
}

final questoesErradasProvider =
    NotifierProvider<QuestoesErradasRepositorio, List<QuestaoErrada>>(
      QuestoesErradasRepositorio.new,
    );

/// Execução de prova cronometrada em andamento (ou finalizada, aguardando
/// correção). NÃO usa `_HiveRepositorio<T>`: não é uma coleção, é um slot
/// único — só UMA execução ativa por vez. Mesma técnica do
/// CronometroController (lib/features/cronometro/cronometro_controller.dart):
/// relógio de parede + Hive; tempo restante sempre recalculado por
/// diferença de datas na leitura (ProvaService.tempoRestante), nunca por
/// Stopwatch em memória — fechar o app não pausa a prova.
class ExecucaoProvaController extends Notifier<ExecucaoProva?> {
  static const _chave = 'atual';

  Box<Map> get _box => Hive.box<Map>(HiveBoxes.execucaoProva);

  @override
  ExecucaoProva? build() {
    final raw = _box.get(_chave);
    if (raw == null) return null;
    try {
      return ExecucaoProva.fromJson(Map<String, dynamic>.from(raw));
    } catch (e) {
      // Registro corrompido: mesma filosofia do _carregar() acima — trata
      // como "sem execução ativa" em vez de derrubar a tela de Simulados.
      debugPrint(
        '${HiveBoxes.execucaoProva}: registro corrompido ignorado ($e)',
      );
      return null;
    }
  }

  /// Começa uma prova nova — substitui qualquer execução ativa anterior
  /// (só uma por vez). Awaited: a tela só avança pra execução depois que o
  /// slot está gravado.
  Future<void> iniciar(ExecucaoProva execucao) async {
    await _box.put(_chave, execucao.toJson());
    state = execucao;
  }

  /// Atualiza a execução ativa (resposta marcada, finalização). O estado em
  /// memória muda na hora; a gravação em disco é fire-and-forget — mesmo
  /// trade-off do CronometroController._persistir: travar a UI a cada toque
  /// de resposta esperando I/O real seria pior que arriscar perder o ÚLTIMO
  /// toque num kill bem naquele instante.
  void atualizar(ExecucaoProva execucao) {
    state = execucao;
    _box.put(_chave, execucao.toJson());
  }

  /// Aplica [mutacao] sobre o estado ATUAL, não sobre uma cópia capturada por
  /// closure na tela.
  ///
  /// A tela guarda a `ExecucaoProva` do build corrente e monta a versão nova a
  /// partir dela; duas edições no MESMO frame (antes de o rebuild propagar o
  /// estado novo) partiriam ambas da mesma base e a segunda sobrescreveria a
  /// primeira. Lendo `state` aqui dentro, cada mutação enxerga a anterior.
  /// No-op quando não há execução ativa.
  void mutar(ExecucaoProva Function(ExecucaoProva atual) mutacao) {
    final atual = state;
    if (atual == null) return;
    atualizar(mutacao(atual));
  }

  /// Encerra a execução ativa (virou Simulado — nada mais a reter).
  Future<void> encerrar() async {
    await _box.delete(_chave);
    state = null;
  }
}

final execucaoProvaProvider =
    NotifierProvider<ExecucaoProvaController, ExecucaoProva?>(
      ExecucaoProvaController.new,
    );

// ---------------------------------------------------------------------------
// Anexos do caderno de erros (F1) — foto do enunciado
// ---------------------------------------------------------------------------

/// Bytes da foto do enunciado, por id de `QuestaoErrada` — ver
/// `QuestaoErrada.temAnexo` e `HiveBoxes.anexos` para o porquê do box
/// separado.
///
/// Fora do padrão `_HiveRepositorio<T>` de propósito: aquele espelha o box
/// inteiro em `state` (uma `List<T>` em memória) porque a UI historicamente
/// lê a coleção completa a cada rebuild — ótimo para JSON pequeno, péssimo
/// para bytes de imagem. Uma foto comprimida ainda pesa dezenas/centenas de
/// KB; se ela morasse em algum `state` do Riverpod, TODO provider que
/// observa `questoesErradasProvider` (fila do dia, ranking, estatísticas —
/// nenhum deles usa a imagem) recarregaria megabytes de foto à toa a cada
/// rebuild. Por isso os bytes são lidos/gravados sob demanda, por id, direto
/// do box — nunca entram em `state`.
class AnexosQuestaoRepositorio {
  Box<Uint8List> get _box => Hive.box<Uint8List>(HiveBoxes.anexos);

  /// Bytes da foto, ou null se a questão não tem anexo.
  Uint8List? ler(String questaoId) => _box.get(questaoId);

  Future<void> salvar(String questaoId, Uint8List bytes) =>
      _box.put(questaoId, bytes);

  /// Idempotente: apagar quem não tem anexo é um no-op silencioso — quem
  /// chama (exclusão de questão, botão "remover foto" no diálogo) não
  /// precisa checar `temAnexo` antes.
  Future<void> remover(String questaoId) => _box.delete(questaoId);

  /// Todos os anexos atuais (id da questão -> bytes) — insumo do backup
  /// completo (`ExportService.jsonCompleto`) e do snapshot de rollback.
  Map<String, Uint8List> todos() => Map<String, Uint8List>.from(_box.toMap());

  /// Restaura backup: apaga tudo e grava os anexos importados. Mesmo
  /// contrato de `_HiveRepositorio.substituirTudo` — hard delete, sem
  /// tombstone. Usado tanto por `ApagarDadosUseCase.apagarTudo` (com mapa
  /// vazio) quanto pela restauração de backup completo.
  Future<void> substituirTudo(Map<String, Uint8List> anexos) async {
    await _box.clear();
    await _box.putAll(anexos);
  }

  /// Import aditivo: grava/sobrescreve sem apagar o resto — mesmo contrato
  /// de `_HiveRepositorio.mesclar`.
  Future<void> mesclar(Map<String, Uint8List> anexos) async {
    if (anexos.isEmpty) return;
    await _box.putAll(anexos);
  }
}

final anexosQuestaoRepositorioProvider = Provider<AnexosQuestaoRepositorio>(
  (ref) => AnexosQuestaoRepositorio(),
);
