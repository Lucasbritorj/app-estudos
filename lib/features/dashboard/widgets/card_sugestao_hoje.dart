import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../registro/registro_form.dart';
import '../dashboard_providers.dart';

/// Sugestão do dia: a matéria com maior déficit no ciclo da semana
/// (alvo por peso − feito), apontando o próximo tópico da fronteira do
/// grafo (pré-requisitos satisfeitos). Some sem cronograma ou sem matérias.
class CardSugestaoHoje extends ConsumerWidget {
  const CardSugestaoHoje({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sugestao = ref.watch(sugestaoHojeProvider);
    if (sugestao == null) return const SizedBox.shrink();
    final materia = sugestao.materia;
    final proximoTopico = sugestao.proximoTopico;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
            radius: 10, backgroundColor: corDaSerie(materia.corSlot)),
        title: Text('Sugestão de hoje: ${materia.nome}'),
        subtitle: Text(
            'Faltam ${formatarMinutos(sugestao.deficitMinutos)} no ciclo desta '
            'semana'
            '${proximoTopico == null ? '' : ' · comece por '
                '"${proximoTopico.nome}"'}'),
        trailing: const Icon(Icons.arrow_forward, color: VizColors.muted),
        onTap: () => mostrarFormularioRegistro(context,
            materiaInicial: materia.id, topicoInicial: proximoTopico?.id),
      ),
    );
  }
}
