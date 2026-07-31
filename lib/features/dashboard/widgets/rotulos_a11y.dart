import '../../../core/utils/formatters.dart';

/// Texto por extenso para rótulos de acessibilidade (WCAG 2.2 — leitor de
/// tela). As abreviações visuais de [formatarMinutos] ("1h 35min") existem
/// para densidade de tela, mas um leitor de tela lê "1h" como "um h" (não
/// reconhece a abreviação como unidade de tempo) — o nó semântico precisa da
/// forma falada, nunca do texto abreviado renderizado.
String minutosPorExtenso(int minutos) {
  if (minutos <= 0) return '0 minutos';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  final partes = <String>[
    if (h > 0) (h == 1 ? '1 hora' : '$h horas'),
    if (m > 0 || h == 0) (m == 1 ? '1 minuto' : '$m minutos'),
  ];
  return partes.join(' e ');
}

/// Idem para o tile "Ritmo" (pág/h): "3,5 pág/h" falado por extenso — "pág/h"
/// também não é uma abreviação que um leitor de tela reconhece.
String ritmoPorExtenso(double paginasPorHora) =>
    '${formatarDecimal(paginasPorHora)} páginas por hora';

/// Frase da variação MoM/YoY dos tiles Mês/Ano, por extenso — mesma
/// informação hoje só disponível no Tooltip da seta (que um leitor de tela
/// não alcança sem gesto extra de exploração).
String variacaoPorExtenso(double variacao, String periodo) {
  if (variacao == 0) {
    return ', estável em relação ao mesmo ponto do $periodo passado';
  }
  final subiu = variacao > 0;
  final pct = (variacao.abs() * 100).toStringAsFixed(0);
  return ', ${subiu ? 'subiu' : 'caiu'} $pct% em relação ao mesmo ponto '
      'do $periodo passado';
}
