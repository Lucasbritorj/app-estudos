import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/materia.dart';
import '../../data/models/topico.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/edital_service.dart';
import '../dashboard/dashboard_providers.dart' show hojeProvider;

/// Buraco do edital pronto para exibição: mesmo shape que
/// `EditalService.buracos` devolve, só nomeado para não repetir o record
/// type inteiro em cada assinatura de provider/widget.
typedef BuracoEdital = ({LinhaEdital linha, Materia materia, int prioridade});

/// Teto de buracos carregado tanto na seção "Próximos buracos" da tela
/// quanto no card do dashboard (que lê só o primeiro) — um único número
/// para os dois, senão a lista da tela e o "buraco mais caro" do card
/// poderiam discordar sobre o que é prioridade.
const limiteBuracosEdital = 10;

/// Tópicos do ambiente ativo (todos quando consolidado). Não mora em
/// `ambiente_filtros.dart` (arquivo travado, fora do escopo desta tarefa)
/// porque só o edital verticalizado precisa da lista de tópicos JÁ
/// filtrada por ambiente — os outros consumidores de `topicosProvider`
/// (Mapa de Estudos, sugestão do dia) filtram por matéria individualmente,
/// já escopada pelo ambiente.
final _topicosDoAmbienteProvider = Provider<List<Topico>>((ref) {
  final ids = {for (final m in ref.watch(materiasDoAmbienteProvider)) m.id};
  return ref
      .watch(topicosProvider)
      .where((t) => ids.contains(t.materiaId))
      .toList();
});

/// Situação de cada tópico do ambiente ativo (intocado/estudado/frágil/
/// dominado) cruzada com minutos, questões e domínio Elo. Base memoizada de
/// todas as agregações abaixo — sem isto, cobertura + distribuição +
/// buracos recalculariam o mesmo cruzamento tópicos×registros três vezes
/// a cada rebuild da tela.
final linhasEditalProvider = Provider<List<LinhaEdital>>((ref) {
  return EditalService.linhas(
    ref.watch(_topicosDoAmbienteProvider),
    ref.watch(registrosDoAmbienteProvider),
    // hojeProvider, nunca DateTime.now(): mesma data estável do resto do
    // dashboard — inclusive a que decide o esquecimento (staleness) do Elo.
    referencia: ref.watch(hojeProvider),
  );
});

/// Linhas agrupadas por matéria — evita reagrupar a cada ExpansionTile
/// aberta/fechada na tela do edital.
final linhasPorMateriaEditalProvider = Provider<Map<String, List<LinhaEdital>>>(
  (ref) {
    final porMateria = <String, List<LinhaEdital>>{};
    for (final l in ref.watch(linhasEditalProvider)) {
      (porMateria[l.topico.materiaId] ??= []).add(l);
    }
    return porMateria;
  },
);

/// Cobertura por matéria do ambiente ativo (arquivadas já saem filtradas
/// por `EditalService.coberturaPorMateria`).
final coberturaPorMateriaEditalProvider = Provider<List<CoberturaMateria>>((
  ref,
) {
  return EditalService.coberturaPorMateria(
    ref.watch(materiasDoAmbienteProvider),
    ref.watch(_topicosDoAmbienteProvider),
    ref.watch(registrosDoAmbienteProvider),
    referencia: ref.watch(hojeProvider),
  );
});

/// Cobertura do edital inteiro do ambiente ativo, ponderada por peso da
/// matéria × peso do tópico. Null sem tópico cadastrado — o sinal que a
/// tela e o card usam para NUNCA mostrar "0%" quando não há edital
/// importado (edital vazio não é edital zerado).
final coberturaGeralEditalProvider = Provider<double?>((ref) {
  return EditalService.coberturaGeral(
    ref.watch(materiasDoAmbienteProvider),
    ref.watch(_topicosDoAmbienteProvider),
    ref.watch(registrosDoAmbienteProvider),
    referencia: ref.watch(hojeProvider),
  );
});

/// Contagem de tópicos por situação no ambiente ativo — base do
/// donut/legenda do topo da tela e do "N intocados" do card.
final distribuicaoEditalProvider = Provider<Map<SituacaoTopico, int>>((ref) {
  return EditalService.distribuicao(
    ref.watch(materiasDoAmbienteProvider),
    ref.watch(_topicosDoAmbienteProvider),
    ref.watch(registrosDoAmbienteProvider),
    referencia: ref.watch(hojeProvider),
  );
});

/// Próximos buracos do edital ativo — intocados/frágeis ordenados por
/// prioridade (peso matéria × peso tópico), já cortados em
/// [limiteBuracosEdital]. A seção "Próximos buracos" da tela lê a lista
/// inteira; o card do dashboard lê só `.firstOrNull`.
final buracosEditalProvider = Provider<List<BuracoEdital>>((ref) {
  return EditalService.buracos(
    ref.watch(materiasDoAmbienteProvider),
    ref.watch(_topicosDoAmbienteProvider),
    ref.watch(registrosDoAmbienteProvider),
    referencia: ref.watch(hojeProvider),
    limite: limiteBuracosEdital,
  );
});
