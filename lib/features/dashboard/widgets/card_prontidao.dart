import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/prontidao_service.dart';
import '../dashboard_providers.dart';

/// Prontidão para a prova: % hoje vs % projetado na data da prova pelo
/// ritmo do cronograma, matérias em risco e chamada de calibração para
/// matéria sem medição (cold start honesto — palpite vira evidência com
/// 10+ questões registradas). Só aparece com ambiente ativo com data de
/// prova marcada.
class CardProntidao extends ConsumerWidget {
  const CardProntidao({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dados = ref.watch(prontidaoProvider);
    if (dados == null) return const SizedBox.shrink();
    final dataProva = dados.dataProva;
    final diasAteProva = dados.diasAteProva;
    final minutosSemanais = dados.minutosSemanais;
    final prontidaoHoje = dados.prontidaoHoje;
    final prontidaoProva = dados.prontidaoProva;
    final emRisco = dados.emRisco;
    final semMedicao = dados.semMedicao;

    final corProjecao = prontidaoProva >= 0.85
        ? StatusColors.bom
        : prontidaoProva >= ProntidaoService.limiarRisco
            ? StatusColors.atencao
            : StatusColors.critico;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Prontidão para a prova',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: VizColors.inkSecondary)),
                ),
                Text(
                  diasAteProva < 0
                      ? 'prova em ${formatarData(dataProva)}'
                      : diasAteProva == 0
                          ? 'É HOJE'
                          : diasAteProva == 1
                              ? 'falta 1 dia'
                              : 'faltam $diasAteProva dias',
                  style: TextStyle(
                      color: diasAteProva <= 30
                          ? StatusColors.atencao
                          : VizColors.muted,
                      fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _Percentual(
                    rotulo: 'Hoje',
                    valor: prontidaoHoje,
                    cor: VizColors.inkPrimary),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.arrow_forward,
                      size: 16, color: VizColors.muted),
                ),
                _Percentual(
                    rotulo: 'Na prova (ritmo atual)',
                    valor: prontidaoProva,
                    cor: corProjecao),
              ],
            ),
            if (minutosSemanais <= 0) ...[
              const SizedBox(height: 8),
              const Text(
                'Sem cronograma semanal — a projeção assume ritmo zero. '
                'Defina horas por dia em Planejamento.',
                style: TextStyle(color: StatusColors.atencao, fontSize: 12),
              ),
            ],
            if (emRisco.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final r in emRisco.take(3))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'No ritmo atual, ${r.materia.nome} chega a '
                    '${(r.projetado * 100).toStringAsFixed(0)}%.',
                    style: const TextStyle(
                        color: StatusColors.critico, fontSize: 12),
                  ),
                ),
            ],
            if (semMedicao.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Estimado pela intimidade (sem evidência): '
                '${semMedicao.take(4).map((m) => m.nome).join(', ')}'
                '${semMedicao.length > 4 ? '…' : ''} — registre 10+ '
                'questões de cada para calibrar.',
                style:
                    const TextStyle(color: VizColors.muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Percentual extends StatelessWidget {
  final String rotulo;
  final double valor;
  final Color cor;

  const _Percentual(
      {required this.rotulo, required this.valor, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${(valor * 100).toStringAsFixed(0)}%',
            style: TextStyle(
                color: cor, fontSize: 22, fontWeight: FontWeight.w600)),
        Text(rotulo,
            style: const TextStyle(color: VizColors.muted, fontSize: 11)),
      ],
    );
  }
}
