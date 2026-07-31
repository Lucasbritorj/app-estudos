import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/haptica.dart';
import '../../core/widgets/estado_vazio.dart';
import '../../data/models/questao_errada.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/repositorios.dart';
import 'caderno_providers.dart';

/// Tela de resolução de questões órfãs (B5).
///
/// `MateriaUseCase`/`TopicoUseCase` preservam a `QuestaoErrada` de propósito
/// ao excluir matéria/tópico — o enunciado é conteúdo caro escrito à mão, e
/// apagar a questão junto jogaria isso fora. O vínculo (`materiaId`/
/// `topicoId`) fica pendurado em vez disso. Esta tela é o único lugar do
/// app que resolve essa pendência: reatribui para matéria/tópico existente.
/// Nunca exclui nada automaticamente.
class QuestoesOrfasScreen extends ConsumerWidget {
  const QuestoesOrfasScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orfas = ref.watch(questoesOrfasProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Questões órfãs')),
      body: orfas.isEmpty
          ? const EstadoVazio(
              icone: Icons.link_off,
              titulo: 'Nenhuma questão órfã',
              descricao:
                  'Toda questão do caderno está com matéria e tópico '
                  'válidos.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                Spacing.lg,
                Spacing.md,
                Spacing.lg,
                Spacing.lg,
              ),
              itemCount: orfas.length,
              itemBuilder: (context, i) {
                final orfa = orfas[i];
                return _CartaoOrfa(key: ValueKey(orfa.questao.id), orfa: orfa);
              },
            ),
    );
  }
}

class _CartaoOrfa extends StatelessWidget {
  final QuestaoOrfa orfa;

  const _CartaoOrfa({super.key, required this.orfa});

  @override
  Widget build(BuildContext context) {
    final motivo = orfa.motivo == MotivoOrfandade.materiaInexistente
        ? 'Matéria excluída'
        : 'Tópico excluído';
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Cor de status só no ícone (grafismo pequeno tolera 3:1) —
                // mesma receita de `_LinhaResposta` em caderno_screen.dart.
                const Icon(Icons.link_off, size: 15, color: StatusColors.atencao),
                const SizedBox(width: 6),
                Text(
                  motivo,
                  style: const TextStyle(
                    color: VizColors.inkSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              orfa.questao.enunciado,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: VizColors.inkPrimary, fontSize: 14),
            ),
            const SizedBox(height: Spacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _DialogoReatribuir(questao: orfa.questao),
                ),
                child: const Text('Reatribuir'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo focado só em matéria/tópico. Reatribuir não mexe em enunciado,
/// resposta ou comentário — isso é o `_DialogoQuestao` de caderno_screen.dart;
/// duplicar aqui só a parte que resolve a orfandade evita reabrir o
/// formulário inteiro (com campos irrelevantes pro que o usuário veio fazer)
/// para um simples ajuste de vínculo.
class _DialogoReatribuir extends ConsumerStatefulWidget {
  final QuestaoErrada questao;

  const _DialogoReatribuir({required this.questao});

  @override
  ConsumerState<_DialogoReatribuir> createState() => _DialogoReatribuirState();
}

class _DialogoReatribuirState extends ConsumerState<_DialogoReatribuir> {
  final _formKey = GlobalKey<FormState>();
  late String? _materiaId;
  late String? _topicoId;

  @override
  void initState() {
    super.initState();
    // Pré-preenche com o vínculo atual — se a matéria ainda existir (motivo
    // foi só o tópico), o usuário não precisa escolhê-la de novo. Se não
    // existir mais, o guard de `materiaSumiuDaLista` no build() força
    // `initialValue: null` e a escolha vira obrigatória via validator.
    _materiaId = widget.questao.materiaId;
    _topicoId = widget.questao.topicoId;
  }

  void _salvar() {
    if (!_formKey.currentState!.validate()) return;
    final atualizada = widget.questao.copyWith(
      materiaId: _materiaId!,
      topicoId: _topicoId,
      limparTopico: _topicoId == null,
    );
    final messenger = ScaffoldMessenger.of(context);
    // Fire-and-forget, mesmo padrão de `_DialogoQuestaoState._salvar()`: o
    // rebuild reativo de `questoesOrfasProvider` tira o item da lista assim
    // que a escrita completa, sem precisar aguardar aqui.
    ref.read(questoesErradasProvider.notifier).salvar(atualizada);
    Haptica.leve();
    Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(content: Text('Questão reatribuída.')));
  }

  @override
  Widget build(BuildContext context) {
    // Lista GLOBAL (não `materiasDoAmbienteProvider`): a questão órfã não
    // pertence a ambiente nenhum — a matéria que a colocaria lá já era —,
    // então restringir ao ambiente ativo esconderia destinos válidos em
    // outro ambiente. Mesmo raciocínio de `questoesOrfasProvider`.
    final materias = ref.watch(materiasProvider).where((m) => !m.arquivada).toList();
    final materiaSumiuDaLista =
        _materiaId != null && !materias.any((m) => m.id == _materiaId);
    final topicos = (_materiaId == null || materiaSumiuDaLista)
        ? const <Topico>[]
        : ref.watch(topicosProvider.notifier).daMateria(_materiaId!);
    final topicoSumiuDaLista =
        _topicoId != null && !topicos.any((t) => t.id == _topicoId);

    return AlertDialog(
      title: const Text('Reatribuir questão'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.questao.enunciado,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: VizColors.inkSecondary, fontSize: 12),
              ),
              const SizedBox(height: Spacing.md),
              if (materias.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: Spacing.sm),
                  child: Text(
                    'Nenhuma matéria disponível. Cadastre uma matéria antes '
                    'de reatribuir.',
                    style: TextStyle(color: VizColors.muted, fontSize: 12),
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
                  decoration: const InputDecoration(labelText: 'Tópico (opcional)'),
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
            ],
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
