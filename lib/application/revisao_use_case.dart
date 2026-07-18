import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';
import '../data/repositories/configuracoes_repositorio.dart';
import '../data/repositories/repositorios.dart';
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
  RevisaoUseCase(this._ref);
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
    int minutos = 0,
  }) async {
    final agora = DateTime.now();
    final config = _ref.read(configuracoesProvider);
    if (questoes != null && questoes > 0 && acertos != null) {
      await _ref
          .read(registrosProvider.notifier)
          .salvar(
            RegistroHora(
              id: const Uuid().v4(),
              data: agora,
              materiaId: revisao.materiaId,
              topicoId: revisao.topicoId,
              tipo: TipoEstudo.pratica,
              tarefa: 'Revisão: ${revisao.titulo}',
              minutos: minutos,
              questoes: questoes,
              acertos: acertos,
            ),
          );
    }
    final feita = revisao.copyWith(feita: true, dataConclusao: agora);
    await _ref.read(revisoesProvider.notifier).salvar(feita);
    await NotificacoesRevisao.sincronizar(feita, config.horaNotificacao);

    final taxa = RevisaoService.taxaAcertoDe(
      _ref.read(registrosProvider),
      materiaId: revisao.materiaId,
      topicoId: revisao.topicoId,
    );
    final agendada = DateTime(
      revisao.dataAgendada.year,
      revisao.dataAgendada.month,
      revisao.dataAgendada.day,
    );
    final passo = RevisaoService.proximoPassoFsrs(
      estabilidade: revisao.estabilidade,
      dificuldade: revisao.dificuldade,
      intervaloAtual: revisao.intervaloDias,
      diasDeAtraso: agora.difference(agendada).inDays,
      taxaAcerto: taxa,
    );
    if (passo == null) {
      return (proxima: null, taxaAcerto: taxa, reforco: false);
    }

    final tituloBase = revisao.titulo.replaceFirst(
      RegExp(r' \((\d+d|reforço)\)$'),
      '',
    );
    final proxima = Revisao(
      id: const Uuid().v4(),
      materiaId: revisao.materiaId,
      topicoId: revisao.topicoId,
      // Linhagem da cadeia: sem o aulaId a invariante "uma cadeia por aula"
      // (dedupe em criarCadeiaParaAula) perderia as sucessoras de vista.
      aulaId: revisao.aulaId,
      titulo: passo.reforco
          ? '$tituloBase (reforço)'
          : '$tituloBase (${passo.dias}d)',
      dataAgendada: DateTime(agora.year, agora.month, agora.day + passo.dias),
      intervaloDias: passo.intervalo,
      estabilidade: passo.estabilidade,
      dificuldade: passo.dificuldade,
    );
    await _ref.read(revisoesProvider.notifier).salvar(proxima);
    await NotificacoesRevisao.sincronizar(proxima, config.horaNotificacao);
    return (proxima: proxima, taxaAcerto: taxa, reforco: passo.reforco);
  }

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
