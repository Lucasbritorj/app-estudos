import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/prova_alvo.dart';
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
    final ajustada = dados.prontidaoAjustada;
    final cobertura = dados.coberturaConfiavel;
    final emRisco = dados.emRisco;
    final semMedicao = dados.semMedicao;

    final corProjecao = StatusColors.porTaxa(prontidaoProva);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Prontidão para a prova',
                    style: LuminaText.cardTitle,
                  ),
                ),
                Text(
                  rotuloRegressiva(diasAteProva, dataProva),
                  style: TextStyle(
                    color: diasAteProva <= 30
                        ? StatusColors.atencao
                        : VizColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Percentual(
                  rotulo: 'Hoje',
                  valor: prontidaoHoje,
                  cor: VizColors.inkSecondary,
                  tamanho: 20,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Spacing.md),
                  child: Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: VizColors.muted,
                  ),
                ),
                // Âncora: a projeção AJUSTADA ao risco é o número grande.
                _Percentual(
                  rotulo: 'Na prova (ajustada)',
                  valor: ajustada,
                  cor: corProjecao,
                  tamanho: 34,
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            // Faixa de confiança: quanto da projeção é evidência vs palpite,
            // e a diferença entre a média crua e a ajustada ao risco.
            _FaixaConfianca(
              projecaoCrua: prontidaoProva,
              ajustada: ajustada,
              cobertura: cobertura,
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
                      color: StatusColors.critico,
                      fontSize: 12,
                    ),
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
                style: const TextStyle(color: VizColors.muted, fontSize: 12),
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
  final double tamanho;

  const _Percentual({
    required this.rotulo,
    required this.valor,
    required this.cor,
    this.tamanho = 22,
  });

  @override
  Widget build(BuildContext context) {
    final percentualTexto = '${(valor * 100).toStringAsFixed(0)}%';
    // A cor (corProjecao = StatusColors.porTaxa) carrega o veredito, mas o
    // número grande e o rótulo abaixo dele são dois Text irmãos — o leitor
    // lia "72%" e só depois "Hoje", pares invertidos e soltos. Um nó só, na
    // ordem "rótulo: valor" ("Hoje: 72%").
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$rotulo: $percentualTexto',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            percentualTexto,
            style: LuminaText.numeroHero.copyWith(
              color: cor,
              fontSize: tamanho,
            ),
          ),
          Text(
            rotulo,
            style: const TextStyle(color: VizColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Faixa de confiança da prontidão: % do peso do edital com evidência (Elo
/// confiável) e o "desconto de risco" entre a projeção crua e a ajustada
/// por dispersão — o que o número único escondia.
class _FaixaConfianca extends StatelessWidget {
  final double projecaoCrua;
  final double ajustada;
  final double cobertura;

  const _FaixaConfianca({
    required this.projecaoCrua,
    required this.ajustada,
    required this.cobertura,
  });

  @override
  Widget build(BuildContext context) {
    final descontoPct = ((projecaoCrua - ajustada) * 100).round();
    final coberturaPct = (cobertura * 100).round();
    return Wrap(
      spacing: Spacing.md,
      runSpacing: Spacing.xs,
      children: [
        _Chip(
          icone: Icons.verified_outlined,
          texto: '$coberturaPct% do peso com evidência',
          cor: cobertura >= 0.5 ? StatusColors.bom : StatusColors.atencao,
        ),
        if (descontoPct > 0)
          _Chip(
            icone: Icons.balance,
            texto: 'crua ${(projecaoCrua * 100).toStringAsFixed(0)}% · '
                '−$descontoPct% de risco (dispersão)',
            cor: VizColors.muted,
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icone;
  final String texto;
  final Color cor;

  const _Chip({required this.icone, required this.texto, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 13, color: cor),
        const SizedBox(width: 4),
        Text(texto, style: TextStyle(color: cor, fontSize: 11)),
      ],
    );
  }
}
