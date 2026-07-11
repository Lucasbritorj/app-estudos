import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/notificacoes/notificacoes_service.dart';
import '../../data/models/aula.dart';
import '../../data/models/revisao.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/revisao_service.dart';

/// Gatilho da cadeia de revisões: dispara quando uma Aula é CONCLUÍDA
/// (paginasLidas >= paginasTotais), nunca por sessão avulsa. Agenda só a
/// Revisão 1 (menor intervalo configurado, ex.: 7d) a partir da data de
/// conclusão do PDF — as seguintes nascem ao concluir cada revisão.
Future<Revisao?> criarCadeiaParaAula(
    WidgetRef ref, Aula aula, String materiaNome) async {
  final config = ref.read(configuracoesProvider);
  final primeiro =
      RevisaoService.proximoIntervalo(config.intervalosRevisao, 0);
  if (primeiro == null) return null;

  // Uma cadeia por aula: se já existe revisão pendente da aula, não duplica.
  final jaExiste = ref
      .read(revisoesProvider)
      .any((r) => r.aulaId == aula.id && !r.feita);
  if (jaExiste) return null;

  final base = aula.dataConclusao ?? DateTime.now();
  final revisao = Revisao(
    id: const Uuid().v4(),
    materiaId: aula.materiaId,
    aulaId: aula.id,
    titulo: '$materiaNome — ${aula.nome} (${primeiro}d)',
    dataAgendada: DateTime(base.year, base.month, base.day + primeiro),
    intervaloDias: primeiro,
  );
  await ref.read(revisoesProvider.notifier).salvar(revisao);
  await NotificacoesService.agendarRevisao(
    id: revisao.id,
    titulo: revisao.titulo,
    dia: revisao.dataAgendada,
    hora: config.horaNotificacao,
  );
  return revisao;
}
