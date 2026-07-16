import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/repositories/ambiente_filtros.dart';
import '../../../data/repositories/planejamento_repositorio.dart';
import '../../../data/repositories/repositorios.dart';
import '../../../domain/mapa_estudos_service.dart';
import '../../../domain/planejamento_service.dart';
import '../../../domain/stats_service.dart';
import '../../registro/registro_form.dart';

/// Sugestão do dia: a matéria com maior déficit no ciclo da semana
/// (alvo por peso − feito), apontando o próximo tópico da fronteira do
/// grafo (pré-requisitos satisfeitos). Some sem cronograma ou sem matérias.
class CardSugestaoHoje extends ConsumerWidget {
  final DateTime hoje;

  const CardSugestaoHoje({super.key, required this.hoje});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plano = ref.watch(planejamentoProvider);
    final materias = ref.watch(materiasDoAmbienteProvider);
    final registros = ref.watch(registrosDoAmbienteProvider);
    final planejado = PlanejamentoService.totalPlanejado(plano);
    if (planejado == 0 || materias.isEmpty) return const SizedBox.shrink();

    final alvo =
        PlanejamentoService.cicloPorUtilidade(planejado, materias, registros);
    final feito = StatsService.minutosPorMateria(registros,
        de: StatsService.inicioDaSemana(hoje), ate: hoje);

    String? sugestaoId;
    var maiorDeficit = 0;
    for (final e in alvo.entries) {
      final deficit = e.value - (feito[e.key] ?? 0);
      if (deficit > maiorDeficit) {
        maiorDeficit = deficit;
        sugestaoId = e.key;
      }
    }
    if (sugestaoId == null) return const SizedBox.shrink();
    final materia =
        materias.where((m) => m.id == sugestaoId).firstOrNull;
    if (materia == null) return const SizedBox.shrink();

    final topicosDaMateria = ref
        .watch(topicosProvider)
        .where((t) => t.materiaId == materia.id)
        .toList();
    final proximoTopico = MapaEstudosService.fronteira(
            topicosDaMateria, registros)
        .firstOrNull;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
            radius: 10, backgroundColor: corDaSerie(materia.corSlot)),
        title: Text('Sugestão de hoje: ${materia.nome}'),
        subtitle: Text(
            'Faltam ${formatarMinutos(maiorDeficit)} no ciclo desta semana'
            '${proximoTopico == null ? '' : ' · comece por '
                '"${proximoTopico.nome}"'}'),
        trailing: const Icon(Icons.arrow_forward, color: VizColors.muted),
        onTap: () => mostrarFormularioRegistro(context,
            materiaInicial: materia.id, topicoInicial: proximoTopico?.id),
      ),
    );
  }
}
