import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/haptica.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/configuracoes_repositorio.dart';
import '../../data/repositories/repositorios.dart';
import 'ambientes_screen.dart';

/// Chip-menu do ambiente ativo — vive na AppBar do Dashboard/Matérias.
/// Trocar de ambiente rescopa o app inteiro (providers derivados).
class AmbienteSelector extends ConsumerWidget {
  const AmbienteSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ambientes =
        ref.watch(ambientesProvider).where((a) => !a.arquivado).toList();
    final ativo = ref.watch(ambienteAtivoProvider);

    return PopupMenuButton<String>(
      tooltip: 'Trocar ambiente',
      onSelected: (id) async {
        Haptica.selecao();
        final notifier = ref.read(configuracoesProvider.notifier);
        final config = ref.read(configuracoesProvider);
        if (id == '__todos__') {
          await notifier.salvar(config.copyWith(limparAmbienteAtivo: true));
        } else if (id == '__gerenciar__') {
          if (context.mounted) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AmbientesScreen()),
            );
          }
        } else {
          await notifier.salvar(config.copyWith(ambienteAtivoId: id));
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
            value: '__todos__', child: Text('Todos os ambientes')),
        for (final a in ambientes)
          PopupMenuItem(
            value: a.id,
            child: Row(
              children: [
                CircleAvatar(
                    radius: 6, backgroundColor: corDaSerie(a.corSlot)),
                const SizedBox(width: 8),
                Text(a.nome),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: '__gerenciar__', child: Text('Gerenciar ambientes…')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (ativo != null) ...[
              CircleAvatar(
                  radius: 5, backgroundColor: corDaSerie(ativo.corSlot)),
              const SizedBox(width: 6),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                ativo?.nome ?? 'Todos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, color: VizColors.inkSecondary),
              ),
            ),
            const Icon(Icons.expand_more, size: 18, color: VizColors.muted),
          ],
        ),
      ),
    );
  }
}
