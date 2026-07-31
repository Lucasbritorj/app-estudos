import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/simulado.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/banca_service.dart';

/// Providers de desempenho por banca organizadora — mesmo padrão de
/// dashboard_providers.dart: agregação pura sobre listas escopadas por
/// ambiente, memoizada pelo Riverpod (Provider cacheia por `==` das
/// dependências; troca de aba/rebuild com o mesmo dado não recalcula).
///
/// Nenhum destes providers precisa de data (BancaService não olha `DateTime`
/// em nenhum método), então nenhum usa `hojeProvider` — não há o que
/// invalidar à meia-noite aqui.

/// Simulados do ambiente ativo — ambiente_filtros.dart tem o equivalente
/// para registros/revisões ([registrosDoAmbienteProvider],
/// [revisoesDoAmbienteProvider]) mas não para simulados; replica aqui o
/// MESMO filtro já usado inline em SimuladosScreen e CardSimulados
/// (`lib/features/simulados/simulados_screen.dart`,
/// `lib/features/dashboard/widgets/card_simulados.dart`) em vez de
/// introduzir uma terceira cópia divergente.
final _simuladosDoAmbienteProvider = Provider<List<Simulado>>((ref) {
  final simulados = ref.watch(simuladosProvider);
  final ativo = ref.watch(ambienteAtivoProvider);
  if (ativo == null) return simulados;
  return simulados.where((s) => s.ambienteId == ativo.id).toList();
});

/// Bancas já usadas pelo usuário no ambiente ativo, mais usada primeiro.
/// Além de alimentar o Autocomplete dos formulários, uma lista vazia aqui é
/// o sinal de "usuário nunca informou banca nenhuma" — usado pelo
/// CardBancas para se esconder (SizedBox.shrink) sem célula fantasma na
/// masonry do dashboard.
final bancasUsadasProvider = Provider<List<String>>((ref) {
  return BancaService.bancasUsadas(
    ref.watch(registrosDoAmbienteProvider),
    ref.watch(_simuladosDoAmbienteProvider),
  );
});

/// Ranking por taxa de acerto (melhor → pior), já excluindo bancas abaixo
/// de [BancaService.amostraMinima] questões — ver [BancaService.ranking].
final rankingBancasProvider = Provider<List<DesempenhoBanca>>((ref) {
  return BancaService.ranking(
    ref.watch(registrosDoAmbienteProvider),
    ref.watch(_simuladosDoAmbienteProvider),
  );
});

/// Pior par banca×matéria com amostra suficiente — a recomendação mais
/// acionável do módulo ("você acerta X% em Y na banca Z"). Null quando
/// nenhum par atinge a amostra mínima.
final pontoFracoBancaProvider =
    Provider<({String banca, String materiaId, double taxa, int questoes})?>((
      ref,
    ) {
      return BancaService.pontoFraco(
        ref.watch(registrosDoAmbienteProvider),
        ref.watch(_simuladosDoAmbienteProvider),
      );
    });
