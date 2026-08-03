import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/avatar_cor.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/materia.dart';
import '../../data/models/registro_hora.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/planejamento_repositorio.dart';
import '../../domain/planejamento_service.dart';
import '../dashboard/dashboard_providers.dart';
import '../../domain/stats_service.dart';

const _diasDaSemana = [
  'Segunda',
  'Terça',
  'Quarta',
  'Quinta',
  'Sexta',
  'Sábado',
  'Domingo',
];

class PlanejamentoScreen extends ConsumerWidget {
  const PlanejamentoScreen({super.key});

  Future<void> _editarDia(
    BuildContext context,
    WidgetRef ref,
    int diaDaSemana,
    int atual,
  ) async {
    final minutos = TextEditingController(text: atual == 0 ? '' : '$atual');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_diasDaSemana[diaDaSemana - 1]),
        content: TextField(
          controller: minutos,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutos planejados',
            hintText: 'Ex.: 120',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(planejamentoProvider.notifier)
                  .definirDia(diaDaSemana, int.tryParse(minutos.text) ?? 0);
              Navigator.pop(dialogContext);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plano = ref.watch(planejamentoProvider);
    // Ciclo sugerido respeita o escopo: pesos e horas do ambiente ativo.
    final materias = ref.watch(materiasDoAmbienteProvider);
    final registros = ref.watch(registrosDoAmbienteProvider);
    // `hojeProvider`, não `DateTime.now()`: "feito na semana" precisa da mesma
    // data que o resto do app usa. Com o relógio cru, o golden desta tela só
    // era estável por acidente — a semana real nunca mais cruza com os
    // registros semeados, então "feito" ficava preso em 0 e o teste não
    // exercitava o caminho de verdade.
    final hoje = ref.watch(hojeProvider);

    final planejado = PlanejamentoService.totalPlanejado(plano);
    final feito = StatsService.minutosNaSemana(registros, hoje);
    final restante = (planejado - feito).clamp(0, planejado);
    // Ciclo por utilidade: peso × déficit de domínio (Elo medido ou prior
    // de intimidade), com retorno decrescente por bloco alocado.
    final alvoPorMateria = PlanejamentoService.cicloPorUtilidade(
      planejado,
      materias,
      registros,
    );
    final feitoPorMateria = StatsService.minutosPorMateria(
      registros,
      de: StatsService.inicioDaSemana(hoje),
      ate: hoje,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Planejamento')),
      body: ConteudoCentral(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (planejado > 0)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Semana',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: VizColors.inkSecondary),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Planejado ${formatarMinutos(planejado)} · feito ${formatarMinutos(feito)} · restante ${formatarMinutos(restante)}',
                        style: const TextStyle(color: VizColors.inkPrimary),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: planejado == 0
                              ? 0
                              : (feito / planejado).clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: VizColors.gridline,
                          color: seriesColors[0],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _CardFilaDeEstudo(
              materias: materias,
              registros: registros,
              hoje: hoje,
            ),
            Card(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Horas por dia (toque para editar)',
                        style: TextStyle(color: VizColors.inkSecondary),
                      ),
                    ),
                  ),
                  for (var dia = 1; dia <= 7; dia++)
                    ListTile(
                      dense: true,
                      title: Text(_diasDaSemana[dia - 1]),
                      trailing: Text(
                        plano[dia] == null || plano[dia] == 0
                            ? '—'
                            : formatarMinutos(plano[dia]!),
                        style: const TextStyle(
                          color: VizColors.inkPrimary,
                          fontSize: 14,
                        ),
                      ),
                      onTap: () =>
                          _editarDia(context, ref, dia, plano[dia] ?? 0),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (alvoPorMateria.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ciclo sugerido — proporcional ao peso',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: VizColors.inkSecondary),
                      ),
                      const SizedBox(height: 12),
                      for (final materia in materias.where(
                        (m) => alvoPorMateria.containsKey(m.id),
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: corDaSerie(materia.corSlot),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(materia.nome)),
                                  Text(
                                    '${formatarMinutos(feitoPorMateria[materia.id] ?? 0)} / ${formatarMinutos(alvoPorMateria[materia.id]!)}',
                                    style: const TextStyle(
                                      color: VizColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: alvoPorMateria[materia.id]! == 0
                                      ? 0
                                      : ((feitoPorMateria[materia.id] ?? 0) /
                                                alvoPorMateria[materia.id]!)
                                            .clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: VizColors.gridline,
                                  color: corDaSerie(materia.corSlot),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              )
            else
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Defina horas por dia e cadastre matérias com peso para gerar o ciclo sugerido.',
                    style: TextStyle(color: VizColors.muted),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fila de estudo: matérias com horas-alvo, na ordem de ataque. A semana
/// inteira vai para a matéria da vez; ao fechar, a próxima entra — a ETA
/// mostra em quantas semanas cada uma conclui no ritmo da meta.
class _CardFilaDeEstudo extends ConsumerWidget {
  final List<Materia> materias;
  final List<RegistroHora> registros;
  final DateTime hoje;

  const _CardFilaDeEstudo({
    required this.materias,
    required this.registros,
    required this.hoje,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plano = ref.watch(planejamentoProvider);
    final config = ref.watch(configuracoesProvider);
    final minutosSemanais = PlanejamentoService.totalPlanejado(plano) > 0
        ? PlanejamentoService.totalPlanejado(plano)
        : config.metaSemanalMinutos;
    // Alvo é da matéria inteira: feito conta TODO o histórico, não a semana.
    final feitoPorMateria = StatsService.minutosPorMateria(registros);
    final fila = PlanejamentoService.filaDeEstudo(
      materias: materias,
      feitoPorMateria: feitoPorMateria,
      minutosSemanais: minutosSemanais,
    );
    if (fila.isEmpty) return const SizedBox.shrink();

    // Matéria "da vez" = primeira não concluída (-1 se tudo fechado).
    final emAndamento = fila.indexWhere((f) => !f.concluida);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fila de estudo',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: VizColors.inkSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Ordem por peso e intimidade · meta '
                '${formatarMinutos(minutosSemanais)}/semana',
                style: const TextStyle(color: VizColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              for (var i = 0; i < fila.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        fila[i].concluida
                            ? Icons.check_circle
                            : (i == emAndamento && !fila[i].concluida
                                  ? Icons.play_circle_outline
                                  : Icons.schedule),
                        size: 16,
                        color: fila[i].concluida
                            ? StatusColors.bom
                            : (i == emAndamento
                                  ? LuminaColors.safiraClara
                                  : VizColors.muted),
                      ),
                      const SizedBox(width: 8),
                      AvatarCor(slot: fila[i].materia.corSlot, raio: 5),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          fila[i].materia.nome,
                          style: const TextStyle(color: VizColors.inkSecondary),
                        ),
                      ),
                      Text(
                        fila[i].concluida
                            ? 'concluída'
                            : 'faltam ${formatarMinutos(fila[i].restanteMinutos)}'
                                  '${fila[i].semanasAteConcluir.isFinite ? ' · ~${fila[i].semanasAteConcluir.ceil()} sem' : ''}',
                        style: const TextStyle(
                          color: VizColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
