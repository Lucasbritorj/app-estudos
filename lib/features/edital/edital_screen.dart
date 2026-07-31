import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/avatar_cor.dart';
import '../../core/widgets/estado_vazio.dart';
import '../../domain/edital_service.dart';
import '../ambientes/ambiente_selector.dart';
import '../materias/importar_edital.dart';
import 'edital_providers.dart';

/// Cor semântica de cada situação do tópico no edital verticalizado.
///
/// Intocado/estudado ficam em tons de cinza — não usam a paleta categórica
/// de matéria (`seriesColors`), que é reservada para IDENTIDADE, não
/// status: medido que `seriesColors[0]` (o azul usado como "em estudo" no
/// Mapa de Estudos) rende só 4,42:1 sobre `VizColors.surface`, abaixo do
/// mínimo AA de 4,5:1 para texto pequeno. Frágil/dominado reaproveitam o
/// par âmbar/verde de `StatusColors`, a régua que Desempenho, Prontidão e
/// o Mapa já usam para "sabe/não sabe" — ambos medem acima de 4,5:1.
Color _corDaSituacao(SituacaoTopico situacao) => switch (situacao) {
  SituacaoTopico.intocado => VizColors.muted,
  SituacaoTopico.estudado => VizColors.inkSecondary,
  SituacaoTopico.fragil => StatusColors.atencao,
  SituacaoTopico.dominado => StatusColors.bom,
};

IconData _iconeDaSituacao(SituacaoTopico situacao) => switch (situacao) {
  SituacaoTopico.intocado => Icons.radio_button_unchecked,
  SituacaoTopico.estudado => Icons.play_circle_outline,
  SituacaoTopico.fragil => Icons.error_outline,
  SituacaoTopico.dominado => Icons.check_circle,
};

String _rotuloDaSituacao(SituacaoTopico situacao) => switch (situacao) {
  SituacaoTopico.intocado => 'Intocado',
  SituacaoTopico.estudado => 'Estudado',
  SituacaoTopico.fragil => 'Frágil',
  SituacaoTopico.dominado => 'Dominado',
};

/// Edital verticalizado: cobertura do que foi importado cruzada com o que
/// foi de fato estudado e medido (Elo), matéria por matéria — mais a fila
/// de "próximos buracos" ordenada por prioridade (peso matéria × peso
/// tópico). Escopo do ambiente ativo, igual ao resto do app.
class EditalScreen extends ConsumerWidget {
  const EditalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coberturaGeral = ref.watch(coberturaGeralEditalProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edital verticalizado'),
        actions: const [AmbienteSelector(), SizedBox(width: 8)],
      ),
      // Sem tópico cadastrado no ambiente ativo, nada abaixo tem o que
      // mostrar (toda matéria cairia com totalTopicos:0, buracos vazio) —
      // uma tela cheia de seções zeradas seria pior que um convite único e
      // claro pra importar. `coberturaGeral == null` é o sinal (nunca
      // "0%": zero por FALTA DE DADO é diferente de zero por desempenho).
      body: coberturaGeral == null
          ? _EstadoVazioEdital(
              onImportar: () => mostrarImportarEdital(context, ref),
            )
          : ConteudoCentral(
              maxWidth: 900,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.md,
                  Spacing.lg,
                  Spacing.xxl,
                ),
                children: [
                  _CardCoberturaGeral(cobertura: coberturaGeral),
                  const SizedBox(height: Spacing.lg),
                  Padding(
                    padding: const EdgeInsets.only(
                      left: Spacing.xs,
                      bottom: Spacing.sm,
                    ),
                    child: Text(
                      'POR MATÉRIA',
                      style: LuminaText.rotuloUppercase,
                    ),
                  ),
                  const _ListaPorMateria(),
                  const SizedBox(height: Spacing.lg),
                  const _SecaoBuracos(),
                ],
              ),
            ),
    );
  }
}

class _EstadoVazioEdital extends StatelessWidget {
  final VoidCallback onImportar;

  const _EstadoVazioEdital({required this.onImportar});

  @override
  Widget build(BuildContext context) {
    return EstadoVazio(
      icone: Icons.checklist_rtl,
      titulo: 'Importe o edital para ver a cobertura',
      descricao:
          'Cole o conteúdo programático do PDF e o app cruza cada tópico '
          'com o que você já estudou e com o domínio medido (Elo) — '
          'cobertura de verdade, não só horas registradas.',
      cta: FilledButton.icon(
        onPressed: onImportar,
        icon: const Icon(Icons.content_paste_go),
        label: const Text('Importar edital'),
      ),
    );
  }
}

/// Cobertura geral em destaque + donut da distribuição por situação. O
/// número no furo é a MESMA cobertura geral (peso dominado / peso total,
/// matéria × tópico) — não a contagem simples de tópicos dominados, que
/// sub ou superestimaria matérias com tópicos de peso desigual.
class _CardCoberturaGeral extends ConsumerWidget {
  final double cobertura;

  const _CardCoberturaGeral({required this.cobertura});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distribuicao = ref.watch(distribuicaoEditalProvider);
    final total = distribuicao.values.fold(0, (a, b) => a + b);
    final resumoA11y = [
      for (final s in SituacaoTopico.values)
        '${_rotuloDaSituacao(s)} ${distribuicao[s] ?? 0}',
    ].join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cobertura do edital', style: LuminaText.cardTitle),
            const SizedBox(height: Spacing.sm),
            Semantics(
              container: true,
              label:
                  'Cobertura geral ${(cobertura * 100).toStringAsFixed(0)} '
                  'por cento. Distribuição de $total tópicos: $resumoA11y',
              child: total == 0
                  ? const SizedBox(height: 40)
                  : _DonutSituacoes(
                      distribuicao: distribuicao,
                      total: total,
                      cobertura: cobertura,
                    ),
            ),
            const SizedBox(height: Spacing.sm),
            const Text(
              'Peso dominado sobre o peso total do edital (peso da matéria '
              '× peso do tópico) — não é a média simples de tópicos.',
              style: TextStyle(color: VizColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonutSituacoes extends StatelessWidget {
  final Map<SituacaoTopico, int> distribuicao;
  final int total;
  final double cobertura;

  const _DonutSituacoes({
    required this.distribuicao,
    required this.total,
    required this.cobertura,
  });

  @override
  Widget build(BuildContext context) {
    final corCentro = StatusColors.porTaxa(cobertura);
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  centerSpaceRadius: 50,
                  sectionsSpace: 2,
                  sections: [
                    for (final s in SituacaoTopico.values)
                      if ((distribuicao[s] ?? 0) > 0)
                        PieChartSectionData(
                          value: (distribuicao[s] ?? 0).toDouble(),
                          color: _corDaSituacao(s),
                          radius: 20,
                          showTitle: false,
                        ),
                  ],
                ),
              ),
              // Furo do donut carrega o número-âncora da tela — o mesmo
              // percentual do topo, só reforçado aqui dentro do gráfico.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(cobertura * 100).toStringAsFixed(0)}%',
                      style: LuminaText.numeroHero.copyWith(
                        color: corCentro,
                        fontSize: 28,
                      ),
                    ),
                    const Text(
                      'cobertura',
                      style: TextStyle(color: VizColors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.md),
        Wrap(
          spacing: Spacing.lg,
          runSpacing: Spacing.sm,
          alignment: WrapAlignment.center,
          children: [
            for (final s in SituacaoTopico.values)
              _LegendaSituacao(
                situacao: s,
                quantidade: distribuicao[s] ?? 0,
                total: total,
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendaSituacao extends StatelessWidget {
  final SituacaoTopico situacao;
  final int quantidade;
  final int total;

  const _LegendaSituacao({
    required this.situacao,
    required this.quantidade,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (quantidade * 100 / total).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _corDaSituacao(situacao),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${_rotuloDaSituacao(situacao)} · $quantidade ($pct%)',
          style: const TextStyle(color: VizColors.inkSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

/// Lista de matérias com cobertura — só as que TÊM tópico cadastrado
/// (`totalTopicos > 0`). Matéria sem edital importado ainda ficaria com
/// uma barra "0%" ao lado de outras cheias, o que pareceria um alerta em
/// vez de "ainda não importei o edital desta matéria" (mesmo raciocínio do
/// `coberturaGeral` nulo no topo da tela). Pior cobertura primeiro — é a
/// ordem de quem precisa de mais atenção.
class _ListaPorMateria extends ConsumerWidget {
  const _ListaPorMateria();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linhas = [
      for (final c in ref.watch(coberturaPorMateriaEditalProvider))
        if (c.totalTopicos > 0) c,
    ]..sort((a, b) => a.cobertura.compareTo(b.cobertura));

    if (linhas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Text(
          'Nenhuma matéria com edital importado ainda.',
          style: TextStyle(color: VizColors.muted, fontSize: 12),
        ),
      );
    }

    return Column(
      children: [for (final c in linhas) _MateriaEditalTile(cobertura: c)],
    );
  }
}

class _MateriaEditalTile extends ConsumerWidget {
  final CoberturaMateria cobertura;

  const _MateriaEditalTile({required this.cobertura});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materia = cobertura.materia;
    final linhas =
        ref.watch(linhasPorMateriaEditalProvider)[materia.id] ?? const [];
    final cor = StatusColors.porTaxa(cobertura.cobertura);

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: ExpansionTile(
        leading: AvatarCor(slot: materia.corSlot),
        title: Row(
          children: [
            Expanded(
              child: Text(
                materia.nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'peso ${materia.peso}',
              style: const TextStyle(color: VizColors.muted, fontSize: 12),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6, right: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: cobertura.cobertura,
                  minHeight: 7,
                  backgroundColor: VizColors.gridline,
                  color: cor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${cobertura.dominados} de ${cobertura.totalTopicos} '
                'tópicos dominados · ${cobertura.intocados} intocados',
                style: const TextStyle(
                  color: VizColors.inkSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        children: [for (final l in linhas) _TopicoEditalLinha(linha: l)],
      ),
    );
  }
}

class _TopicoEditalLinha extends StatelessWidget {
  final LinhaEdital linha;

  const _TopicoEditalLinha({required this.linha});

  @override
  Widget build(BuildContext context) {
    final cor = _corDaSituacao(linha.situacao);
    final dominioTxt = linha.dominio == null
        ? ''
        : ' · domínio ${(linha.dominio! * 100).toStringAsFixed(0)}%';
    final detalhe =
        '${_rotuloDaSituacao(linha.situacao)} · '
        '${formatarMinutos(linha.minutos)}'
        '${linha.questoes > 0 ? ' · ${linha.questoes} questões' : ''}'
        '$dominioTxt';

    return Semantics(
      label: '${linha.topico.nome}. $detalhe',
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 24, right: 16),
        leading: Icon(_iconeDaSituacao(linha.situacao), size: 20, color: cor),
        title: Text(
          linha.topico.nome,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(detalhe, style: TextStyle(color: cor, fontSize: 12)),
      ),
    );
  }
}

/// Fila de "o que estudar em seguida" derivada do edital: intocados e
/// frágeis ordenados por prioridade (peso matéria × peso tópico), maior
/// primeiro — mesma ordenação de `EditalService.buracos`.
class _SecaoBuracos extends ConsumerWidget {
  const _SecaoBuracos();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final buracos = ref.watch(buracosEditalProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Próximos buracos', style: LuminaText.cardTitle),
            const SizedBox(height: 4),
            const Text(
              'Prioridade = peso da matéria × peso do tópico. No mesmo '
              'peso, zero contato custa mais que contato insuficiente.',
              style: TextStyle(color: VizColors.muted, fontSize: 11),
            ),
            const SizedBox(height: Spacing.md),
            if (buracos.isEmpty)
              const Row(
                children: [
                  Icon(Icons.verified, size: 16, color: StatusColors.bom),
                  SizedBox(width: 6),
                  Text(
                    'Nenhum buraco — edital em dia.',
                    style: TextStyle(color: StatusColors.bom, fontSize: 13),
                  ),
                ],
              )
            else
              for (final b in buracos) _BuracoLinha(buraco: b),
          ],
        ),
      ),
    );
  }
}

class _BuracoLinha extends StatelessWidget {
  final BuracoEdital buraco;

  const _BuracoLinha({required this.buraco});

  @override
  Widget build(BuildContext context) {
    final situacao = buraco.linha.situacao;
    final cor = _corDaSituacao(situacao);
    final topico = buraco.linha.topico;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(_iconeDaSituacao(situacao), size: 18, color: cor),
          ),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${buraco.materia.nome} — ${topico.nome}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_rotuloDaSituacao(situacao)} · peso '
                  '${buraco.materia.peso} × tópico ${topico.peso} = '
                  '${buraco.prioridade}',
                  style: TextStyle(color: cor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
