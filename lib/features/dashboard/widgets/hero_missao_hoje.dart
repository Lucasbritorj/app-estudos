import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/avatar_cor.dart';
import '../../../core/utils/formatters.dart';
import '../../cronometro/cronometro_controller.dart';
import '../../registro/registro_form.dart';
import '../dashboard_providers.dart';

/// Missão de hoje: o próximo passo de estudo como elemento primário do
/// dashboard — 1 tap leva ao cronômetro já configurado e rodando (regra dos
/// 3 segundos: abrir, saber o que fazer, começar). Substitui o antigo
/// CardSugestaoHoje, que era um ListTile discreto no meio da coluna.
class HeroMissaoHoje extends ConsumerWidget {
  const HeroMissaoHoje({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sugestao = ref.watch(sugestaoHojeProvider);
    if (sugestao == null) return const SizedBox.shrink();
    final materia = sugestao.materia;
    final proximoTopico = sugestao.proximoTopico;

    void estudarAgora() {
      ref
          .read(preSelecaoCronometroProvider.notifier)
          .definir(materiaId: materia.id, topicoId: proximoTopico?.id);
      // Só inicia se parado: nunca atropela uma sessão pausada existente.
      if (ref.read(cronometroProvider).status == CronometroStatus.parado) {
        ref.read(cronometroProvider.notifier).iniciar();
      }
      ref.read(abaProvider.notifier).ir(Abas.cronometro);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          boxShadow: LuminaElevation.glow(
            LuminaColors.safiraClara,
            alpha: 0.22,
          ),
        ),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(Radius.circular(14)),
            side: BorderSide(
              color: LuminaColors.safiraClara.withValues(alpha: 0.45),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MISSÃO DE HOJE', style: LuminaText.rotuloUppercase),
                const SizedBox(height: 8),
                Row(
                  children: [
                    AvatarCor(slot: materia.corSlot, raio: 7),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        materia.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(color: VizColors.inkPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Faltam ${formatarMinutos(sugestao.deficitMinutos)} no '
                  'ciclo desta semana'
                  '${proximoTopico == null ? '' : ' · próximo tópico: '
                            '"${proximoTopico.nome}"'}',
                  style: const TextStyle(
                    color: VizColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: estudarAgora,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Estudar agora'),
                    ),
                    TextButton(
                      onPressed: () => mostrarFormularioRegistro(
                        context,
                        materiaInicial: materia.id,
                        topicoInicial: proximoTopico?.id,
                      ),
                      child: const Text('Registrar manualmente'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
