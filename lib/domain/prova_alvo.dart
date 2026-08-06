import '../core/utils/formatters.dart';

/// Calendário até a data da prova.
///
/// A data da prova mora em `Ambiente.dataProva` — não existe entidade
/// separada. Este arquivo é só a régua de CALENDÁRIO em cima dela, e é
/// deliberadamente independente do FSRS: revisão responde retenção da
/// memória, prova responde dias úteis restantes. Nada aqui lê ou escreve
/// estabilidade, dificuldade ou intervalo.
///
/// Extraído de `card_prontidao.dart` e `dashboard_providers.dart`, onde a
/// mesma conta vivia duplicada — uma dentro de um `?:` aninhado no `build`,
/// sem teste de borda nenhum.

/// Dias de calendário de [hoje] até [dataProva]. Negativo = prova passou,
/// 0 = é hoje.
///
/// Compara DIA, não instante: hora, minuto e segundo de ambos os lados são
/// descartados, então 23:59 de hoje e 00:00 de hoje dão o mesmo resultado.
int diasAteProva(DateTime hoje, DateTime dataProva) {
  final prova = DateTime(dataProva.year, dataProva.month, dataProva.day);
  final dia = DateTime(hoje.year, hoje.month, hoje.day);
  return prova.difference(dia).inDays;
}

/// Rótulo pt-BR da contagem regressiva. [dias] vem de [diasAteProva].
///
/// Prova passada não vira "faltam -3 dias": mostra a data, que é a
/// informação que ainda serve para alguma coisa.
String rotuloRegressiva(int dias, DateTime dataProva) {
  if (dias < 0) return 'prova em ${formatarData(dataProva)}';
  if (dias == 0) return 'É HOJE';
  if (dias == 1) return 'falta 1 dia';
  return 'faltam $dias dias';
}
