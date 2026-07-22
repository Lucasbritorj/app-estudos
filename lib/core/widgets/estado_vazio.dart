import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Estado vazio padrão do app — ícone + título + descrição + CTA opcional.
/// Fecha o achado P1 do redesign v4 (estados vazios inconsistentes: dashboard
/// rico vs strings peladas nas telas secundárias). Mesma anatomia do estado
/// vazio original do dashboard, generalizada.
class EstadoVazio extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String descricao;
  final Widget? cta;

  const EstadoVazio({
    super.key,
    required this.icone,
    required this.titulo,
    required this.descricao,
    this.cta,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 44, color: LuminaColors.safiraClara),
              const SizedBox(height: 14),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: VizColors.inkPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                descricao,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VizColors.inkSecondary,
                  fontSize: 13,
                ),
              ),
              if (cta != null) ...[const SizedBox(height: 18), cta!],
            ],
          ),
        ),
      ),
    );
  }
}
