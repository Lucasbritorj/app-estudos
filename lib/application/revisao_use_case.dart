import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:hive_ce/hive.dart';
import '../data/local/hive_boxes.dart';
import '../data/repositories/conclusoes_revisao_repositorio.dart';

import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';
import '../data/repositories/configuracoes_repositorio.dart';
import '../data/repositories/repositorios.dart';
import '../domain/gamificacao_service.dart';
import '../domain/revisao_service.dart';
import 'notificacoes_revisao.dart';

/// Resultado da conclusão; [proxima] null = cadeia encerrada.
typedef ResultadoConclusao = ({
  Revisao? proxima,
  double? taxaAcerto,
  bool reforco,
});

/// Conclusão, adiamento e criação manual de revisões — a orquestração que
/// vivia em RevisoesScreen, agora testável sem UI.
class RevisaoUseCase {
  RevisaoUseCase(this._ref, {this.aposEtapaPersistida});

  @visibleForTesting
  final Future<void> Function(String etapa)? aposEtapaPersistida;
  final Ref _ref;

  /// Conclui e emenda a próxima revisão — FSRS-lite adaptativo pelo
  /// desempenho do tópico: <75% de acerto derruba a estabilidade e agenda
  /// reforço curto; 75-84% cresce devagar; >=85% (ou sem questões) espaça
  /// pleno, com bônus quando revisada perto do esquecimento. Intervalo além
  /// do teto encerra a cadeia.
  ///
  /// [questoes]/[acertos] opcionais: desempenho medido NA revisão vira uma
  /// sessão prática comum ANTES do cálculo — alimenta o Elo e a taxa do
  /// FSRS pelo canal que já existe (uma só fonte de verdade de acerto), em
  /// vez de criar um segundo caminho de dado.
  Future<ResultadoConclusao> concluir(
    Revisao revisao, {
    int? questoes,
    int? acertos,
    int? minutos,
  }) => ConclusoesRevisaoRepositorio.exclusivo(() async {
    await ConclusoesRevisaoRepositorio.recuperar();
    _ref.invalidate(registrosProvider);
    _ref.invalidate(revisoesProvider);
    final anterior = ConclusoesRevisaoRepositorio.box.get(revisao.id);
    if (anterior != null) return _resultado(anterior);

    // O estado persistido prevalece sobre o objeto obsoleto recebido da UI.
    final raw = Hive.box<Map>(HiveBoxes.revisoes).get(revisao.id);
    final atual = raw == null
        ? revisao
        : Revisao.fromJson(Map<String, dynamic>.from(raw));
    final agora = DateTime.now();
    final config = _ref.read(configuracoesProvider);
    final dentroDoTeto =
        ConclusoesRevisaoRepositorio.concluidasNoDia(agora) <
        GamificacaoService.maxRevisoesComBonusPorDia;
    final minutosDaSessao =
        minutos ?? (dentroDoTeto ? config.minutosPadraoRevisao : 0);
    final temDesempenho = questoes != null && questoes > 0 && acertos != null;
    final sessao = temDesempenho
        ? RegistroHora(
            id: const Uuid().v4(),
            data: agora,
            materiaId: atual.materiaId,
            topicoId: atual.topicoId,
            tipo: TipoEstudo.pratica,
            tarefa: 'Revisão: ${atual.titulo}',
            minutos: minutosDaSessao,
            questoes: questoes,
            acertos: acertos,
          )
        : null;
    final taxa = temDesempenho
        ? acertos.clamp(0, questoes) / questoes
        : RevisaoService.taxaAcertoDe(
            _ref.read(registrosProvider),
            materiaId: atual.materiaId,
            topicoId: atual.topicoId,
          );
    final agendada = DateTime(
      atual.dataAgendada.year,
      atual.dataAgendada.month,
      atual.dataAgendada.day,
    );
    final diasDeAtraso = DateTime(
      agora.year,
      agora.month,
      agora.day,
    ).difference(agendada).inDays;
    final passo = RevisaoService.proximoPassoFsrs(
      estabilidade: atual.estabilidade,
      dificuldade: atual.dificuldade,
      intervaloAtual: atual.intervaloDias,
      diasDeAtraso: diasDeAtraso,
      taxaAcerto: taxa,
    );
    final tituloBase = atual.titulo.replaceFirst(
      RegExp(r' \((\d+d|reforço)\)$'),
      '',
    );
    final proxima = passo == null
        ? null
        : Revisao(
            id: const Uuid().v4(),
            materiaId: atual.materiaId,
            topicoId: atual.topicoId,
            aulaId: atual.aulaId,
            titulo: passo.reforco
                ? '$tituloBase (reforço)'
                : '$tituloBase (${passo.dias}d)',
            dataAgendada: DateTime(
              agora.year,
              agora.month,
              agora.day + passo.dias,
            ),
            intervaloDias: passo.intervalo,
            estabilidade: passo.estabilidade,
            dificuldade: passo.dificuldade,
          );
    final feita = atual.copyWith(feita: true, dataConclusao: agora);
    final operacao = <String, dynamic>{
      'id': atual.id,
      'feita': feita.toJson(),
      'sessao': sessao?.toJson(),
      'proxima': proxima?.toJson(),
      'taxaAcerto': taxa,
      'reforco': passo?.reforco ?? false,
      'aplicada': false,
    };
    await ConclusoesRevisaoRepositorio.guardar(operacao);
    await ConclusoesRevisaoRepositorio.aplicar(
      operacao,
      aposEtapa: aposEtapaPersistida,
    );
    _ref.invalidate(registrosProvider);
    _ref.invalidate(revisoesProvider);
    await NotificacoesRevisao.sincronizar(feita, config.horaNotificacao);
    if (proxima != null) {
      await NotificacoesRevisao.sincronizar(proxima, config.horaNotificacao);
    }
    return _resultado(operacao);
  });

  ResultadoConclusao _resultado(Map operacao) => (
    proxima: operacao['proxima'] == null
        ? null
        : Revisao.fromJson(
            Map<String, dynamic>.from(operacao['proxima'] as Map),
          ),
    taxaAcerto: (operacao['taxaAcerto'] as num?)?.toDouble(),
    reforco: operacao['reforco'] as bool,
  );

  Future<Revisao> adiar(Revisao revisao, int dias) async {
    final base = revisao.dataAgendada;
    final nova = revisao.copyWith(
      dataAgendada: DateTime(base.year, base.month, base.day + dias),
    );
    await _ref.read(revisoesProvider.notifier).salvar(nova);
    await NotificacoesRevisao.sincronizar(
      nova,
      _ref.read(configuracoesProvider).horaNotificacao,
    );
    return nova;
  }

  /// Revisão manual avulsa (intervalo 0 = entra no início da cadeia).
  Future<Revisao> criarManual({
    required String materiaId,
    required String titulo,
    required DateTime data,
  }) async {
    final revisao = Revisao(
      id: const Uuid().v4(),
      materiaId: materiaId,
      titulo: titulo,
      dataAgendada: data,
      intervaloDias: 0,
    );
    await _ref.read(revisoesProvider.notifier).salvar(revisao);
    await NotificacoesRevisao.sincronizar(
      revisao,
      _ref.read(configuracoesProvider).horaNotificacao,
    );
    return revisao;
  }
}

final revisaoUseCaseProvider = Provider((ref) => RevisaoUseCase(ref));
