import 'dart:math';

import '../data/models/materia.dart';
import '../data/models/registro_hora.dart';
import 'dominio_service.dart';
import 'planejamento_service.dart';

/// Projeção de prontidão para a data da prova — funções puras.
///
/// Usa o MESMO modelo do ciclo por utilidade: minutos semanais do cronograma
/// são alocados semana a semana via mochila gulosa e cada bloco de 15min
/// rende +0.02 de domínio efetivo (saturando em 1.0). A projeção é coerente
/// com o plano por construção: se o usuário seguir o ciclo sugerido, chega
/// no número projetado.
class ProntidaoService {
  /// Mesmos parâmetros de PlanejamentoService.distribuirPorUtilidade.
  static const _blocoMinutos = 15;
  static const _passoPorBloco = 0.02;

  /// Abaixo disso na projeção, a matéria entra na lista de risco.
  static const limiarRisco = 0.75;

  /// Prontidão = média de domínio ponderada pelo peso do edital.
  /// Null sem matérias ativas (sem dados, sem número inventado).
  static double? prontidao(
      List<Materia> materias, Map<String, double> dominios) {
    final ativas = materias.where((m) => !m.arquivada).toList();
    if (ativas.isEmpty) return null;
    var somaPesos = 0.0;
    var soma = 0.0;
    for (final m in ativas) {
      soma += m.peso * (dominios[m.id] ?? 0.5);
      somaPesos += m.peso;
    }
    if (somaPesos <= 0) return null;
    return soma / somaPesos;
  }

  /// Domínio atual por matéria: Elo confiável ou prior de intimidade —
  /// mesma regra do ciclo (PlanejamentoService.dominioInicial).
  static Map<String, double> dominiosAtuais(
          List<Materia> materias, List<RegistroHora> registros) =>
      {
        for (final m in materias)
          m.id: PlanejamentoService.dominioInicial(m.intimidade,
              DominioService.dominioDaMateria(registros, m.id)),
      };

  /// Projeta os domínios na data da prova simulando o ciclo semana a
  /// semana: [minutosSemanais] do cronograma, alocados por utilidade sobre
  /// os domínios correntes da simulação. Semana fracionária no fim recebe
  /// minutos proporcionais.
  static Map<String, double> projetarDominios({
    required List<Materia> materias,
    required Map<String, double> dominiosHoje,
    required int minutosSemanais,
    required int diasAteProva,
  }) {
    final dominios = {
      for (final e in dominiosHoje.entries)
        e.key: e.value.clamp(0.0, 1.0).toDouble(),
    };
    if (minutosSemanais <= 0 || diasAteProva <= 0) return dominios;

    var diasRestantes = diasAteProva;
    while (diasRestantes > 0) {
      final fracao = min(7, diasRestantes) / 7.0;
      final minutosDaSemana = (minutosSemanais * fracao).round();
      if (minutosDaSemana <= 0) break;
      final alocacao = PlanejamentoService.distribuirPorUtilidade(
          minutosDaSemana, materias, dominios);
      for (final e in alocacao.entries) {
        final ganho = _passoPorBloco * e.value / _blocoMinutos;
        dominios[e.key] = min(1.0, (dominios[e.key] ?? 0.5) + ganho);
      }
      diasRestantes -= 7;
    }
    return dominios;
  }

  /// Matérias ativas cuja projeção fica abaixo de [limiarRisco], piores
  /// primeiro.
  static List<({Materia materia, double projetado})> materiasEmRisco(
      List<Materia> materias, Map<String, double> projetados) {
    return [
      for (final m in materias.where((m) => !m.arquivada))
        if ((projetados[m.id] ?? 0.5) < limiarRisco)
          (materia: m, projetado: projetados[m.id] ?? 0.5),
    ]..sort((a, b) => a.projetado.compareTo(b.projetado));
  }

  /// Matérias ativas sem medição Elo confiável — domínio vem do prior de
  /// intimidade. Chamada de calibração (cold start): registrar 10+ questões
  /// troca o palpite por evidência.
  static List<Materia> semMedicao(
          List<Materia> materias, List<RegistroHora> registros) =>
      [
        for (final m in materias.where((m) => !m.arquivada))
          if (!(DominioService.dominioDaMateria(registros, m.id)?.confiavel ??
              false))
            m,
      ];
}
