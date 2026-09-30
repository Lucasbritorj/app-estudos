import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/plano_diario_service.dart';
import 'plano_diario_repositorio.dart';
import 'plano_diario_screen.dart';

class CardPlanoPessoal extends ConsumerWidget {
  const CardPlanoPessoal({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salvo = ref.watch(planoDiarioProvider);
    final hoje = diaPlano(DateTime.now());
    final blocos = (salvo['blocos'] as List? ?? [])
        .map((j) => BlocoDiario.fromJson(j as Map))
        .where((b) => diaPlano(b.dia) == hoje)
        .toList();
    final registros = ref.watch(registrosProvider);
    final vinculos = salvo['vinculos'] as Map? ?? {};
    final pendentes = blocos
        .where((b) => !registros.any((r) => r.id == vinculos[b.id]))
        .toList();
    final materias = ref.watch(materiasProvider);
    final proximo = pendentes.isEmpty ? null : pendentes.first;
    final nomes = materias.where((m) => m.id == proximo?.materiaId);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.calendar_month),
        title: Text(
          blocos.isEmpty
              ? 'Planejar até a prova'
              : 'Hoje · ${blocos.length - pendentes.length}/${blocos.length} sessões associadas',
        ),
        subtitle: Text(
          proximo == null
              ? 'Capacidade pessoal, revisões e concursos'
              : '${nomes.isEmpty ? 'Matéria indisponível' : nomes.first.nome} · ${proximo.minutos} min\n${proximo.motivo}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const PlanoDiarioScreen()),
        ),
      ),
    );
  }
}
