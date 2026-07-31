import 'dart:typed_data';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptica.dart';
import '../../core/widgets/avatar_cor.dart';
import '../../core/widgets/estado_vazio.dart';
import '../../data/models/bancas.dart';
import '../../data/models/materia.dart';
import '../../data/models/questao_errada.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/caderno_erros_service.dart';
import '../dashboard/dashboard_providers.dart';
import '../materias/materia_dialog.dart';
import 'caderno_providers.dart';
import 'questoes_orfas_screen.dart';

/// Caderno de erros: fila de hoje (refazer), listagem completa com filtros e
/// estatísticas (ranking por matéria, taxa de recuperação, forecast).
///
/// Abas em vez de telas separadas: é a MESMA coleção vista de três ângulos
/// (o que fazer agora / tudo / como estou indo), então trocar de aba é mais
/// barato que navegar — igual à dualidade Pendentes/Feitas de RevisoesScreen,
/// só que com uma terceira lente analítica.
class CadernoScreen extends ConsumerStatefulWidget {
  const CadernoScreen({super.key});

  @override
  ConsumerState<CadernoScreen> createState() => _CadernoScreenState();
}

class _CadernoScreenState extends ConsumerState<CadernoScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _novaQuestao() {
    showDialog<void>(context: context, builder: (_) => const _DialogoQuestao());
  }

  @override
  Widget build(BuildContext context) {
    // Escopo por ambiente (igual ao resto do app): caderno vazio no
    // ambiente ativo não deve mostrar abas/estatísticas fantasma de OUTRO
    // ambiente que por acaso tenha questões.
    final vazio = ref.watch(questoesErradasDoAmbienteProvider).isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caderno de Erros'),
        bottom: vazio
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Fila de hoje'),
                  Tab(text: 'Todas'),
                  Tab(text: 'Estatísticas'),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nova questão errada',
        onPressed: _novaQuestao,
        child: const Icon(Icons.add),
      ),
      body: vazio
          ? EstadoVazio(
              icone: Icons.menu_book_outlined,
              titulo: 'Caderno de erros vazio',
              descricao:
                  'Toda questão que você errar vale registrar aqui: o app '
                  'traz ela de volta pra você refazer no ritmo certo, até '
                  'dominar de verdade.',
              cta: FilledButton.icon(
                onPressed: _novaQuestao,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar questão'),
              ),
            )
          : ConteudoCentral(
              child: TabBarView(
                controller: _tabController,
                children: const [_AbaFila(), _AbaTodas(), _AbaEstatisticas()],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aba 1 — Fila de hoje (modo refazer)
// ---------------------------------------------------------------------------

class _AbaFila extends ConsumerWidget {
  const _AbaFila();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fila = ref.watch(filaDoDiaProvider);
    if (fila.isEmpty) {
      return const EstadoVazio(
        icone: Icons.task_alt,
        titulo: 'Fila zerada por hoje',
        descricao:
            'Nenhuma questão vencida agora. Volte amanhã ou adicione uma '
            'nova questão errada ao caderno.',
      );
    }

    // Mapas resolvidos UMA vez aqui (não por card) — a fila pode ter dezenas
    // de itens e cada um repetir a busca em `materiasProvider`/`topicosProvider`
    // seria O(fila × matérias) à toa.
    final materiasPorId = {for (final m in ref.watch(materiasProvider)) m.id: m};
    final topicosPorId = {for (final t in ref.watch(topicosProvider)) t.id: t};

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 88),
      itemCount: fila.length,
      itemBuilder: (context, i) {
        final q = fila[i];
        return _CartaoFila(
          // Key por id: cada card tem estado local próprio ("ver resposta")
          // que não pode vazar pro card vizinho quando a lista reordena.
          key: ValueKey(q.id),
          questao: q,
          materia: materiasPorId[q.materiaId],
          topicoNome: q.topicoId == null ? null : topicosPorId[q.topicoId]?.nome,
        );
      },
    );
  }
}

/// Card de "refazer": enunciado visível, resposta escondida atrás de um
/// botão, dois botões grandes de resultado. Fica em StatefulWidget próprio
/// porque "ver resposta" é estado local por questão (não pertence à tela).
class _CartaoFila extends ConsumerStatefulWidget {
  final QuestaoErrada questao;
  final Materia? materia;
  final String? topicoNome;

  const _CartaoFila({
    super.key,
    required this.questao,
    required this.materia,
    required this.topicoNome,
  });

  @override
  ConsumerState<_CartaoFila> createState() => _CartaoFilaState();
}

class _CartaoFilaState extends ConsumerState<_CartaoFila> {
  var _verResposta = false;

  Future<void> _responder(bool acertou) async {
    final hoje = ref.read(hojeProvider);
    final atualizada = CadernoErrosService.registrarTentativa(
      widget.questao,
      acertou,
      hoje,
    );
    final messenger = ScaffoldMessenger.of(context);
    final mensagem = _mensagemTentativa(atualizada, hoje);
    // Toda resposta reagenda pra frente (no mínimo +1 dia): a questão sempre
    // sai da fila de HOJE depois de respondida, então não precisamos
    // manipular estado local aqui — o rebuild da lista cuida disso.
    await ref.read(questoesErradasProvider.notifier).salvar(atualizada);
    if (!mounted) return;
    if (atualizada.arquivada) {
      Haptica.celebrar();
    } else {
      Haptica.leve();
    }
    messenger.showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.questao;
    final legendas = <String>[
      if (q.banca != null) q.banca!,
      if (q.ano != null) '${q.ano}',
      if (q.orgao != null) q.orgao!,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.md),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AvatarCor(slot: widget.materia?.corSlot ?? 0, raio: 6),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    [
                      widget.materia?.nome ?? '—',
                      if (widget.topicoNome != null) widget.topicoNome!,
                    ].join(' · '),
                    style: LuminaText.rotuloUppercase,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (q.totalTentativas > 0)
                  Text(
                    '${q.totalTentativas}ª tentativa',
                    style: const TextStyle(color: VizColors.muted, fontSize: 11),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            if (q.temAnexo) ...[
              _FotoEnunciado(
                // .read, não .watch: os bytes só mudam quando a própria
                // questão é salva de novo (dialog de edição), o que já
                // reconstrói este card via `questoesErradasProvider` — não
                // há um stream próprio do box de anexos pra observar aqui.
                bytes: ref.read(anexosQuestaoRepositorioProvider).ler(q.id),
              ),
              const SizedBox(height: Spacing.sm),
            ],
            Text(
              q.enunciado,
              style: const TextStyle(
                color: VizColors.inkPrimary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (legendas.isNotEmpty) ...[
              const SizedBox(height: Spacing.xs),
              Text(
                legendas.join(' · '),
                style: const TextStyle(color: VizColors.muted, fontSize: 11),
              ),
            ],
            const SizedBox(height: Spacing.md),
            if (!_verResposta)
              OutlinedButton.icon(
                onPressed: () => setState(() => _verResposta = true),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Ver resposta'),
              )
            else ...[
              if (q.respostaMarcada != null)
                _LinhaResposta(
                  icone: Icons.close,
                  cor: StatusColors.critico,
                  rotulo: 'Você marcou',
                  valor: q.respostaMarcada!,
                ),
              if (q.respostaCorreta != null)
                _LinhaResposta(
                  icone: Icons.check,
                  cor: StatusColors.bom,
                  rotulo: 'Resposta correta',
                  valor: q.respostaCorreta!,
                ),
              if (q.comentario.isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  q.comentario,
                  style: const TextStyle(
                    color: VizColors.inkSecondary,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _responder(false),
                      // criticoSuperficie é o vermelho calibrado do tema pra
                      // FUNDO de botão (rótulo branco passa em 4,5:1) — nunca
                      // StatusColors.critico aqui, que é a tinta clara de
                      // TEXTO e não tem contraste como preenchimento.
                      style: FilledButton.styleFrom(
                        backgroundColor: StatusColors.criticoSuperficie,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.close),
                      label: const Text('Errei'),
                    ),
                  ),
                  const SizedBox(width: Spacing.md),
                  Expanded(
                    child: FilledButton.icon(
                      // Sem StatusColors.bom aqui: como fundo de botão o
                      // verde do tema não passa em 4,5:1 pro rótulo branco
                      // (só foi calibrado pra uso em ícone/texto pequeno).
                      // O estilo padrão do tema (safira) já é garantidamente
                      // acessível via ColorScheme.fromSeed.
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => _responder(true),
                      icon: const Icon(Icons.check),
                      label: const Text('Acertei'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mensagem de feedback pós-tentativa: quando a questão volta (data exata)
/// ou que foi dominada e saiu do caderno — sem abrir a questão de novo pra
/// descobrir.
String _mensagemTentativa(QuestaoErrada atualizada, DateTime hoje) {
  if (atualizada.arquivada) {
    return 'Dominada! Saiu da fila do caderno de erros.';
  }
  final dias = atualizada.proximaTentativa.difference(hoje).inDays;
  final quando = dias <= 1 ? 'amanhã' : 'em $dias dias';
  return 'Volta $quando · ${formatarData(atualizada.proximaTentativa)}.';
}

/// Linha "rótulo: valor" com ícone de status pequeno. A cor de status fica
/// SÓ no ícone (grafismo pequeno tolera 3:1); o texto segue em tons neutros
/// já calibrados — mesma solução que RevisoesScreen usa pro status de prazo.
class _LinhaResposta extends StatelessWidget {
  final IconData icone;
  final Color cor;
  final String rotulo;
  final String valor;

  const _LinhaResposta({
    required this.icone,
    required this.cor,
    required this.rotulo,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 15, color: cor),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$rotulo: ',
                    style: const TextStyle(color: VizColors.muted, fontSize: 12),
                  ),
                  TextSpan(
                    text: valor,
                    style: const TextStyle(
                      color: VizColors.inkSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto do enunciado (F1), miniatura de topo do card de refazer.
///
/// `bytes` pode vir null mesmo com `temAnexo == true` se o box de anexos e a
/// flag da questão desincronizarem por algum motivo externo (ex.: box
/// limpo à mão fora do app) — mostra um placeholder em vez de espaço em
/// branco silencioso ou de derrubar o card inteiro.
class _FotoEnunciado extends StatelessWidget {
  final Uint8List? bytes;

  const _FotoEnunciado({required this.bytes});

  @override
  Widget build(BuildContext context) {
    final dados = bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: dados == null
          ? Container(
              height: 96,
              alignment: Alignment.center,
              color: VizColors.gridline,
              child: const Icon(
                Icons.broken_image_outlined,
                color: VizColors.muted,
              ),
            )
          : Image.memory(
              dados,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aba 2 — Todas (filtro por matéria e situação)
// ---------------------------------------------------------------------------

enum _FiltroSituacao { ativas, dominadas, todas }

class _AbaTodas extends ConsumerStatefulWidget {
  const _AbaTodas();

  @override
  ConsumerState<_AbaTodas> createState() => _AbaTodasState();
}

class _AbaTodasState extends ConsumerState<_AbaTodas> {
  String? _materiaFiltro;
  var _situacao = _FiltroSituacao.ativas;

  @override
  Widget build(BuildContext context) {
    final todas = ref.watch(questoesErradasDoAmbienteProvider);
    final materias = ref.watch(materiasDoAmbienteProvider);
    final materiasPorId = {for (final m in materias) m.id: m};
    final orfas = ref.watch(questoesOrfasProvider);

    final filtradas = [
      for (final q in todas)
        if ((_materiaFiltro == null || q.materiaId == _materiaFiltro) &&
            (_situacao == _FiltroSituacao.todas ||
                (_situacao == _FiltroSituacao.ativas) == !q.arquivada))
          q,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_FiltroSituacao>(
                segments: const [
                  ButtonSegment(
                    value: _FiltroSituacao.ativas,
                    label: Text('Ativas'),
                  ),
                  ButtonSegment(
                    value: _FiltroSituacao.dominadas,
                    label: Text('Dominadas'),
                  ),
                  ButtonSegment(value: _FiltroSituacao.todas, label: Text('Todas')),
                ],
                selected: {_situacao},
                onSelectionChanged: (s) => setState(() => _situacao = s.first),
              ),
              if (materias.isNotEmpty) ...[
                const SizedBox(height: Spacing.sm),
                DropdownButtonFormField<String?>(
                  initialValue: _materiaFiltro,
                  decoration: const InputDecoration(labelText: 'Matéria'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todas as matérias'),
                    ),
                    for (final m in materias)
                      DropdownMenuItem<String?>(value: m.id, child: Text(m.nome)),
                  ],
                  onChanged: (v) => setState(() => _materiaFiltro = v),
                ),
              ],
            ],
          ),
        ),
        if (orfas.isNotEmpty) _AvisoOrfas(quantidade: orfas.length),
        Expanded(
          child: filtradas.isEmpty
              ? const EstadoVazio(
                  icone: Icons.filter_alt_off_outlined,
                  titulo: 'Nada por aqui',
                  descricao: 'Nenhuma questão bate com o filtro atual.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    Spacing.lg,
                    Spacing.md,
                    Spacing.lg,
                    88,
                  ),
                  itemCount: filtradas.length,
                  itemBuilder: (context, i) {
                    final q = filtradas[i];
                    return _LinhaQuestao(
                      questao: q,
                      materia: materiasPorId[q.materiaId],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Aviso discreto (não modal, não bloqueia a aba) de que existem questões
/// com matéria/tópico excluído — excluir matéria/tópico preserva a
/// QuestaoErrada de propósito (ver `questoesOrfasProvider`), então elas
/// ficam invisíveis nos filtros por matéria até alguém reatribuir. Único
/// ponto de entrada da tela de resolução: só aparece quando há órfã, então
/// não vira ruído permanente na aba.
class _AvisoOrfas extends StatelessWidget {
  final int quantidade;

  const _AvisoOrfas({required this.quantidade});

  @override
  Widget build(BuildContext context) {
    final texto = quantidade == 1
        ? '1 questão órfã (matéria ou tópico excluído) — reatribuir'
        : '$quantidade questões órfãs (matéria ou tópico excluído) — reatribuir';
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.sm, Spacing.lg, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QuestoesOrfasScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.sm,
            ),
            decoration: BoxDecoration(
              color: StatusColors.atencao.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: StatusColors.atencao.withValues(alpha: 0.28)),
            ),
            child: Row(
              children: [
                // Cor de status só no ícone (grafismo pequeno tolera 3:1); o
                // texto segue em tom neutro já calibrado — mesma receita de
                // `_LinhaResposta` acima.
                const Icon(Icons.link_off, size: 16, color: StatusColors.atencao),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    texto,
                    style: const TextStyle(color: VizColors.inkSecondary, fontSize: 12),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: VizColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinhaQuestao extends ConsumerWidget {
  final QuestaoErrada questao;
  final Materia? materia;

  const _LinhaQuestao({required this.questao, required this.materia});

  Future<void> _editar(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => _DialogoQuestao(existente: questao),
  );

  Future<void> _alternarArquivada(WidgetRef ref) async {
    final hoje = ref.read(hojeProvider);
    final atualizada = questao.arquivada
        ? CadernoErrosService.reabrir(questao, hoje)
        : questao.copyWith(arquivada: true);
    await ref.read(questoesErradasProvider.notifier).salvar(atualizada);
  }

  Future<void> _excluir(BuildContext context, WidgetRef ref) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir questão?'),
        content: const Text(
          'O histórico de tentativas desta questão se perde. Esta ação não '
          'pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StatusColors.criticoSuperficie,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmado == true) {
      await ref.read(questoesErradasProvider.notifier).remover(questao.id);
      // Cascata: sem isto a foto ficava órfã no box de anexos (remover() é
      // idempotente, então chamar mesmo sem `temAnexo` é seguro e mais
      // simples que checar antes).
      await ref.read(anexosQuestaoRepositorioProvider).remover(questao.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = questao;
    final situacao = q.arquivada
        ? 'Dominada'
        : 'Ativa · vence ${formatarData(q.proximaTentativa)}';

    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: ListTile(
        onTap: () => _editar(context),
        leading: AvatarCor(slot: materia?.corSlot ?? 0),
        title: Text(q.enunciado, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Expanded(
              child: Text(
                [
                  materia?.nome ?? '—',
                  if (q.banca != null) q.banca!,
                  if (q.ano != null) '${q.ano}',
                  situacao,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VizColors.muted, fontSize: 12),
              ),
            ),
            // Só a FLAG decide o ícone — nunca ler o box de anexos aqui: a
            // aba "Todas" pode listar dezenas de questões, e abrir o box por
            // linha pra checar bytes derrubaria a rolagem.
            if (q.temAnexo) ...[
              const SizedBox(width: Spacing.xs),
              // `Icon.semanticLabel` sozinho não basta: o Semantics interno
              // do Icon não marca `container`, então o rótulo pode se
              // fundir num nó ancestral em vez de virar um nó próprio —
              // `container: true` aqui garante um nó "Foto anexada" que o
              // leitor de tela encontra e anuncia (Icon puro é mudo).
              Semantics(
                container: true,
                label: 'Foto anexada',
                child: const Icon(
                  Icons.image_outlined,
                  size: 14,
                  color: VizColors.muted,
                ),
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Mais opções',
          onSelected: (acao) {
            if (acao == 'editar') {
              _editar(context);
            } else if (acao == 'arquivar') {
              _alternarArquivada(ref);
            } else if (acao == 'excluir') {
              _excluir(context, ref);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'editar', child: Text('Editar')),
            PopupMenuItem(
              value: 'arquivar',
              child: Text(q.arquivada ? 'Reabrir' : 'Marcar como dominada'),
            ),
            const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aba 3 — Estatísticas
// ---------------------------------------------------------------------------

class _AbaEstatisticas extends ConsumerWidget {
  const _AbaEstatisticas();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumo = ref.watch(resumoCadernoProvider);
    final ranking = ref.watch(rankingCadernoProvider);
    final porBanca = ref.watch(rankingPorBancaCadernoProvider);
    final porTopico = ref.watch(rankingPorTopicoCadernoProvider);
    final forecast = ref.watch(forecastCadernoProvider);
    final taxa = resumo.taxaRecuperacao;
    final maxForecast = forecast.fold(0, (m, d) => d.quantidade > m ? d.quantidade : m);

    return ListView(
      padding: const EdgeInsets.fromLTRB(Spacing.lg, Spacing.md, Spacing.lg, 88),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Row(
              children: [
                _NumeroResumo(rotulo: 'Ativas', valor: '${resumo.totalAtivas}'),
                _NumeroResumo(
                  rotulo: 'Dominadas',
                  valor: '${resumo.totalDominadas}',
                ),
                _NumeroResumo(rotulo: 'Vencem hoje', valor: '${resumo.venceHoje}'),
                _NumeroResumo(
                  rotulo: 'Recuperação',
                  valor: taxa == null ? '—' : '${(taxa * 100).toStringAsFixed(0)}%',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Onde você mais erra', style: LuminaText.cardTitle),
                const SizedBox(height: Spacing.xs),
                const Text(
                  'Matérias com mais questões ativas no caderno, piores primeiro.',
                  style: TextStyle(color: VizColors.muted, fontSize: 11),
                ),
                const SizedBox(height: Spacing.md),
                if (ranking.isEmpty)
                  const Text(
                    'Nenhuma matéria com erro ativo agora — parabéns!',
                    style: TextStyle(color: VizColors.inkSecondary, fontSize: 13),
                  )
                else
                  for (final linha in ranking)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.sm),
                      child: Row(
                        children: [
                          AvatarCor(slot: linha.materia.corSlot, raio: 5),
                          const SizedBox(width: 6),
                          Expanded(child: Text(linha.materia.nome)),
                          Text(
                            '${linha.resumo.ativas} ativas'
                            '${linha.resumo.taxa == null ? '' : ' · ${(linha.resumo.taxa! * 100).toStringAsFixed(0)}% ao refazer'}',
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
        const SizedBox(height: Spacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Por banca', style: LuminaText.cardTitle),
                const SizedBox(height: Spacing.xs),
                const Text(
                  'Desempenho ao refazer questões de cada banca organizadora.',
                  style: TextStyle(color: VizColors.muted, fontSize: 11),
                ),
                const SizedBox(height: Spacing.md),
                if (porBanca.isEmpty)
                  const Text(
                    'Nenhuma questão do caderno tem banca informada ainda.',
                    style: TextStyle(color: VizColors.inkSecondary, fontSize: 13),
                  )
                else
                  for (final linha in porBanca)
                    _LinhaEstatistica(titulo: linha.banca, resumo: linha.resumo),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Por tópico', style: LuminaText.cardTitle),
                const SizedBox(height: Spacing.xs),
                const Text(
                  'Mesmo raciocínio do ranking por matéria, um nível mais fundo.',
                  style: TextStyle(color: VizColors.muted, fontSize: 11),
                ),
                const SizedBox(height: Spacing.md),
                if (porTopico.isEmpty)
                  const Text(
                    'Nenhuma questão do caderno tem tópico associado ainda.',
                    style: TextStyle(color: VizColors.inkSecondary, fontSize: 13),
                  )
                else
                  for (final linha in porTopico)
                    _LinhaEstatistica(titulo: linha.topico.nome, resumo: linha.resumo),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Carga dos próximos 14 dias', style: LuminaText.cardTitle),
                const SizedBox(height: Spacing.md),
                SizedBox(
                  height: 64,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < forecast.length; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0.8),
                            child: _BarraForecast(
                              fracao: maxForecast == 0
                                  ? 0
                                  : forecast[i].quantidade / maxForecast,
                              // "Hoje" (a fila já vencida) em atenção — chama
                              // é canal exclusivo do streak, não reaproveitar.
                              cor: i == 0
                                  ? StatusColors.atencao
                                  : LuminaColors.safiraClara,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('hoje', style: TextStyle(color: VizColors.muted, fontSize: 10)),
                    Text('+14d', style: TextStyle(color: VizColors.muted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NumeroResumo extends StatelessWidget {
  final String rotulo;
  final String valor;

  const _NumeroResumo({required this.rotulo, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            valor,
            style: LuminaText.numeroHero.copyWith(
              fontSize: 20,
              color: VizColors.inkPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rotulo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VizColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Linha "rótulo — total/ativas/dominadas/taxa" das seções Por banca/Por
/// tópico. Mostra os quatro números (não só ativas+taxa do ranking por
/// matéria): aqui o objetivo é o extrato completo, então um grupo já
/// totalmente dominado (0 ativas) continua aparecendo em vez de sumir.
class _LinhaEstatistica extends StatelessWidget {
  final String titulo;
  final ResumoErros resumo;

  const _LinhaEstatistica({required this.titulo, required this.resumo});

  @override
  Widget build(BuildContext context) {
    final taxa = resumo.taxa;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: Spacing.sm),
          Text(
            '${resumo.total} total · ${resumo.ativas} ativas · '
            '${resumo.dominadas} dominadas'
            '${taxa == null ? '' : ' · ${(taxa * 100).toStringAsFixed(0)}% ao refazer'}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: VizColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Barra vertical do forecast — mesma receita de card_forecast_revisao.dart
/// (`widthFactor: 1.0` é obrigatório: sem ele o DecoratedBox recebe largura
/// solta e colapsa a 0px, barra invisível mesmo com a altura certa).
class _BarraForecast extends StatelessWidget {
  final double fracao;
  final Color cor;

  const _BarraForecast({required this.fracao, required this.cor});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: FractionallySizedBox(
            alignment: Alignment.bottomCenter,
            heightFactor: fracao == 0 ? 0.02 : (0.1 + 0.9 * fracao),
            widthFactor: 1.0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fracao == 0 ? VizColors.gridline : cor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// CRUD — diálogo de criar/editar questão
// ---------------------------------------------------------------------------

class _DialogoQuestao extends ConsumerStatefulWidget {
  final QuestaoErrada? existente;

  const _DialogoQuestao({this.existente});

  @override
  ConsumerState<_DialogoQuestao> createState() => _DialogoQuestaoState();
}

class _DialogoQuestaoState extends ConsumerState<_DialogoQuestao> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _enunciado;
  late final TextEditingController _respostaMarcada;
  late final TextEditingController _respostaCorreta;
  late final TextEditingController _comentario;
  late final TextEditingController _banca;
  late final TextEditingController _ano;
  late final TextEditingController _orgao;
  String? _materiaId;
  String? _topicoId;

  /// Bytes da foto do enunciado — representa o estado DESEJADO ao salvar
  /// (null = "sem foto", seja porque nunca teve ou porque o usuário removeu
  /// nesta edição). `_salvar()` reconcilia isso com o box de anexos de uma
  /// vez só, sem precisar rastrear "mudou ou não" à parte.
  Uint8List? _foto;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _enunciado = TextEditingController(text: e?.enunciado ?? '');
    _respostaMarcada = TextEditingController(text: e?.respostaMarcada ?? '');
    _respostaCorreta = TextEditingController(text: e?.respostaCorreta ?? '');
    _comentario = TextEditingController(text: e?.comentario ?? '');
    _banca = TextEditingController(text: e?.banca ?? '');
    _ano = TextEditingController(text: e?.ano?.toString() ?? '');
    _orgao = TextEditingController(text: e?.orgao ?? '');
    _materiaId = e?.materiaId;
    _topicoId = e?.topicoId;
    // Lido direto do box, sem FutureBuilder: Hive.get() é síncrono depois
    // que o box já está aberto (o app abre todos os boxes no boot, antes de
    // qualquer tela existir).
    _foto = (e != null && e.temAnexo)
        ? ref.read(anexosQuestaoRepositorioProvider).ler(e.id)
        : null;
  }

  @override
  void dispose() {
    _enunciado.dispose();
    _respostaMarcada.dispose();
    _respostaCorreta.dispose();
    _comentario.dispose();
    _banca.dispose();
    _ano.dispose();
    _orgao.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_formKey.currentState!.validate()) return;
    final existente = widget.existente;
    final ano = int.tryParse(_ano.text.trim());
    // Gerado ANTES do objeto pra poder gravar o anexo sob a MESMA chave: o
    // box de anexos usa o id da questão, tanto em criação quanto em edição.
    final id = existente?.id ?? const Uuid().v4();

    final questao = existente == null
        ? QuestaoErrada(
            id: id,
            materiaId: _materiaId!,
            topicoId: _topicoId,
            enunciado: _enunciado.text,
            respostaMarcada: _respostaMarcada.text,
            respostaCorreta: _respostaCorreta.text,
            comentario: _comentario.text,
            banca: _banca.text,
            ano: ano,
            orgao: _orgao.text,
            // hojeProvider (não DateTime.now()): a questão nasce na fila de
            // hoje segundo o calendário do APP, o mesmo que decide o resto
            // do agendamento — e mantém a criação determinística em teste.
            criadaEm: ref.read(hojeProvider),
            temAnexo: _foto != null,
          )
        : existente.copyWith(
            materiaId: _materiaId!,
            topicoId: _topicoId,
            limparTopico: _topicoId == null,
            enunciado: _enunciado.text,
            respostaMarcada: _respostaMarcada.text,
            respostaCorreta: _respostaCorreta.text,
            comentario: _comentario.text,
            banca: _banca.text,
            ano: ano,
            // Campo "Ano" vazio precisa APAGAR o ano gravado, não preservar
            // o antigo — mesma ambiguidade de `limparTopico` acima (`ano`
            // vira null tanto ao limpar quanto ao "não mexer").
            limparAno: ano == null,
            orgao: _orgao.text,
            temAnexo: _foto != null,
          );

    final messenger = ScaffoldMessenger.of(context);
    ref.read(questoesErradasProvider.notifier).salvar(questao);
    // Mesmo fire-and-forget da linha acima: o box de anexos não tem `state`
    // reativo pra aguardar, e a tela não precisa travar por causa do I/O da
    // foto — pior caso (kill do app no meio) é a mesma janela de risco que
    // qualquer outra escrita multi-box deste app já tem (Hive não tem
    // transação entre boxes).
    final anexos = ref.read(anexosQuestaoRepositorioProvider);
    final foto = _foto;
    if (foto != null) {
      anexos.salvar(id, foto);
    } else if (existente?.temAnexo ?? false) {
      anexos.remover(id);
    }
    Haptica.leve();
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          existente == null ? 'Questão adicionada ao caderno.' : 'Questão atualizada.',
        ),
      ),
    );
  }

  /// Câmera OU galeria já escolhidas (bytes prontos) vs. os dois botões de
  /// escolha. Não usa FutureBuilder: `_foto` é estado local simples, trocado
  /// de forma síncrona por `setState` assim que o picker devolve.
  Widget _construirSeletorFoto() {
    final foto = _foto;
    if (foto != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: Image.memory(
              foto,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Remover foto',
                icon: const Icon(Icons.close, color: Colors.white, size: 18),
                onPressed: () => setState(() => _foto = null),
              ),
            ),
          ),
        ],
      );
    }

    // Câmera só aparece onde de fato existe uma câmera de verdade pra abrir:
    // nativo Android/iOS, ou navegador rodando num celular (no Flutter Web,
    // `defaultTargetPlatform` reflete o SO por trás do navegador, não
    // "web" genérico). Em desktop nativo (Linux/Windows/macOS) o próprio
    // `image_picker` lança `StateError` pra `ImageSource.camera` sem
    // `cameraDelegate` configurado; em desktop NO NAVEGADOR o atributo HTML
    // que pediria a câmera é ignorado e cai de volta num seletor de arquivo
    // igual ao da galeria — ou seja, mostrar o botão ali só confundiria sem
    // nunca abrir câmera nenhuma. O try/catch de `_selecionarFoto` é a
    // segunda rede, pra qualquer caso que esta checagem não previu (ex.:
    // permissão de câmera negada em Android/iOS).
    final mostraCamera =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;

    return Row(
      children: [
        if (mostraCamera) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _selecionarFoto(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Câmera'),
            ),
          ),
          const SizedBox(width: Spacing.sm),
        ],
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _selecionarFoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('Foto do enunciado'),
          ),
        ),
      ],
    );
  }

  Future<void> _selecionarFoto(ImageSource source) async {
    try {
      final arquivo = await ImagePicker().pickImage(
        source: source,
        // Compressão OBRIGATÓRIA: uma foto de câmera atual passa fácil de
        // 4 MB. Sem limite, isso vai inteiro pro box do Hive (fica em disco
        // local pra sempre) e pro backup JSON em base64 (mais 33% de novo
        // em cima disso). 1600px de lado maior a 70% de qualidade ainda é
        // sobra legível pra reler o enunciado depois, e cai pra dezenas ou
        // poucas centenas de KB por foto — é a diferença entre um backup de
        // 200 questões pesar alguns MB ou mais de 1 GB.
        maxWidth: 1600,
        imageQuality: 70,
      );
      if (arquivo == null) return; // usuário cancelou o picker.
      final bytes = await arquivo.readAsBytes();
      if (!mounted) return;
      setState(() => _foto = bytes);
    } catch (_) {
      // Câmera/galeria podem falhar por motivo de plataforma (permissão
      // negada, hardware ausente, fonte não implementada no desktop nativo)
      // — nunca pode derrubar o diálogo. Pior caso: o usuário continua sem
      // foto, exatamente como antes desta funcionalidade existir.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir a câmera/galeria agora.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final materias = ref
        .watch(materiasDoAmbienteProvider)
        .where((m) => !m.arquivada)
        .toList();
    // Matéria da questão pode ter sido arquivada depois de criada — sem essa
    // checagem o Dropdown quebra (valor selecionado fora da lista de itens).
    final materiaSumiuDaLista =
        _materiaId != null && !materias.any((m) => m.id == _materiaId);
    final topicos = (_materiaId == null || materiaSumiuDaLista)
        ? const <Topico>[]
        : ref.watch(topicosProvider.notifier).daMateria(_materiaId!);
    // Mesma proteção acima, para o tópico: ele pode ter sido excluído (fica
    // órfão — ver questoesOrfasProvider) ou a matéria pode ter mudado para
    // uma que não tem esse tópico. Sem isso o Dropdown quebra com um
    // `initialValue` fora dos `items`.
    final topicoSumiuDaLista =
        _topicoId != null && !topicos.any((t) => t.id == _topicoId);
    final sugestoesBanca =
        {...Bancas.sugestoes, ...ref.watch(bancasDoCadernoProvider)}.toList()..sort();

    return AlertDialog(
      title: Text(widget.existente == null ? 'Nova questão errada' : 'Editar questão'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (materias.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Spacing.sm),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cadastre uma matéria antes de registrar questões.',
                            style: TextStyle(color: VizColors.muted, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () => mostrarDialogoMateria(context, ref),
                          child: const Text('Criar matéria'),
                        ),
                      ],
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: materiaSumiuDaLista ? null : _materiaId,
                  decoration: const InputDecoration(labelText: 'Matéria *'),
                  items: [
                    for (final m in materias)
                      DropdownMenuItem(value: m.id, child: Text(m.nome)),
                  ],
                  validator: (v) => v == null ? 'Escolha a matéria' : null,
                  onChanged: (v) => setState(() {
                    _materiaId = v;
                    _topicoId = null;
                  }),
                ),
                if (topicos.isNotEmpty) ...[
                  const SizedBox(height: Spacing.sm),
                  DropdownButtonFormField<String?>(
                    initialValue: topicoSumiuDaLista ? null : _topicoId,
                    decoration: const InputDecoration(
                      labelText: 'Tópico (opcional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— sem tópico —'),
                      ),
                      for (final t in topicos)
                        DropdownMenuItem<String?>(value: t.id, child: Text(t.nome)),
                    ],
                    onChanged: (v) => setState(() => _topicoId = v),
                  ),
                ],
                const SizedBox(height: Spacing.sm),
                _construirSeletorFoto(),
                const SizedBox(height: Spacing.sm),
                TextFormField(
                  controller: _enunciado,
                  decoration: const InputDecoration(labelText: 'Enunciado *'),
                  maxLines: 4,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Obrigatório' : null,
                ),
                const SizedBox(height: Spacing.sm),
                TextFormField(
                  controller: _respostaMarcada,
                  decoration: const InputDecoration(labelText: 'Resposta marcada'),
                ),
                const SizedBox(height: Spacing.sm),
                TextFormField(
                  controller: _respostaCorreta,
                  decoration: const InputDecoration(labelText: 'Resposta correta'),
                ),
                const SizedBox(height: Spacing.sm),
                TextFormField(
                  controller: _comentario,
                  decoration: const InputDecoration(
                    labelText: 'Por que errei',
                    hintText:
                        'Não sabia / interpretei mal / troquei conceito / chutei',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: Spacing.sm),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _banca.text),
                  optionsBuilder: (value) {
                    final q = value.text.trim().toUpperCase();
                    if (q.isEmpty) return sugestoesBanca;
                    return sugestoesBanca.where((b) => b.contains(q));
                  },
                  onSelected: (v) => _banca.text = v,
                  fieldViewBuilder: (context, fieldController, focusNode, _) {
                    return TextFormField(
                      controller: fieldController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(labelText: 'Banca'),
                      onChanged: (v) => _banca.text = v,
                    );
                  },
                ),
                const SizedBox(height: Spacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ano,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Ano'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = int.tryParse(v.trim());
                          if (n == null || n < 1990 || n > 2100) return '1990-2100';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _orgao,
                        decoration: const InputDecoration(labelText: 'Órgão'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: materias.isEmpty ? null : _salvar,
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}
