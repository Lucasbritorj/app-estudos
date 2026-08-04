import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/revisao_use_case.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/revisao.dart';

/// Conclusão de revisão como fluxo compartilhado — extraído de
/// `RevisoesScreen` para o dashboard poder concluir sem sair da tela.
///
/// Por que extrair em vez de reimplementar no card: concluir dispara FSRS,
/// grava sessão prática, cancela lembrete no SO e agenda a próxima. Um
/// segundo caminho de dado divergiria no primeiro ajuste do algoritmo, e o
/// bug apareceria só para quem concluísse pelo dashboard. Uma função, dois
/// call sites, paridade por construção.

/// Pergunta o desempenho da revisão. Retornos: null = cancelou (não
/// conclui); (questoes: null, ...) = concluir sem registrar; valores =
/// concluir e registrar prática.
///
/// Não recebe a [Revisao]: o diálogo nunca usou o parâmetro que tinha antes.
///
/// Débito conhecido que veio junto na extração: os dois
/// `TextEditingController` não são liberados. É o padrão que a onda de
/// dispose/Semantics vai varrer nas 10 telas — mover o defeito junto com o
/// código é honesto; consertar aqui de forma avulsa criaria meia-migração.
Future<({int? questoes, int? acertos})?> perguntarDesempenhoRevisao(
  BuildContext context,
) {
  final questoesCtrl = TextEditingController();
  final acertosCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<({int? questoes, int? acertos})?>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Como foi a revisão?'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Se fez questões, informe o resultado — o próximo intervalo '
              'se ajusta à taxa de acerto e o registro entra como prática.',
              style: TextStyle(color: VizColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: questoesCtrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Questões'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final n = int.tryParse(v.trim());
                      if (n == null || n <= 0) return 'Inteiro > 0';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: acertosCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Acertos'),
                    validator: (v) {
                      final questoes = int.tryParse(questoesCtrl.text.trim());
                      if (questoes == null) return null;
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 0) return 'Obrigatório';
                      if (n > questoes) return '≤ questões';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(dialogContext, (questoes: null, acertos: null)),
          child: const Text('Só concluir'),
        ),
        FilledButton(
          onPressed: () {
            final questoes = int.tryParse(questoesCtrl.text.trim());
            if (questoes == null) {
              // Sem questões preenchidas, o botão equivale a só concluir.
              Navigator.pop(dialogContext, (questoes: null, acertos: null));
              return;
            }
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(dialogContext, (
              questoes: questoes,
              acertos: int.tryParse(acertosCtrl.text.trim()),
            ));
          },
          child: const Text('Concluir'),
        ),
      ],
    ),
  );
}

/// Pergunta o desempenho, conclui via caso de uso (FSRS-lite) e mostra o
/// feedback. Cancelar no diálogo não conclui nada.
///
/// Usado pela tela de Revisões e pelo card do dashboard — os dois passam
/// exatamente por aqui.
Future<void> concluirRevisaoComFeedback(
  BuildContext context,
  WidgetRef ref,
  Revisao revisao,
) async {
  final desempenho = await perguntarDesempenhoRevisao(context);
  if (desempenho == null || !context.mounted) return;

  final resultado = await ref
      .read(revisaoUseCaseProvider)
      .concluir(
        revisao,
        questoes: desempenho.questoes,
        acertos: desempenho.acertos,
      );

  final proxima = resultado.proxima;
  // `proxima == null` = cadeia encerrada (intervalo passou do teto): não há
  // data seguinte a anunciar, e a conclusão já aconteceu.
  if (proxima == null || !context.mounted) return;

  final motivo = resultado.reforco
      ? 'Acerto ${(resultado.taxaAcerto! * 100).toStringAsFixed(0)}% '
            'abaixo de 75% — reforço em ${proxima.intervaloDias}d'
      : 'Próxima em ${proxima.intervaloDias}d';
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Feita. $motivo (${formatarData(proxima.dataAgendada)}).'),
    ),
  );
}
