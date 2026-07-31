import 'package:intl/intl.dart';

/// 135 -> "2h 15min"; 120 -> "2h"; 45 -> "45min".
String formatarMinutos(int minutos) {
  if (minutos < 60) return '${minutos}min';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  return m == 0 ? '${h}h' : '${h}h ${m.toString().padLeft(2, '0')}min';
}

/// Decimal em convenção pt-BR (vírgula) — U-17. Antes cada call site fazia
/// `toStringAsFixed`, que crava PONTO: "3.5 pág/h" no meio de um app que
/// escreve "30,5" em Configurações e exporta CSV com `;`.
String formatarDecimal(double v, {int casas = 1}) =>
    v.toStringAsFixed(casas).replaceAll('.', ',');

/// Inteiro com separador de milhar pt-BR: 48231 -> "48.231" (U-19).
String formatarInteiro(int v) => NumberFormat.decimalPattern('pt_BR').format(v);

/// Total grande (>=100h) em formato compacto: despreza os minutos e aplica
/// separador de milhar pt-BR — 119999 -> "1.999h" em vez de "1999h 59min"
/// (formatarMinutos estoura em espaços pequenos, ex. o miolo da rosca do
/// dashboard).
String formatarHorasCompacto(int minutos) =>
    '${formatarInteiro(minutos ~/ 60)}h';

String formatarData(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

String formatarDiaMes(DateTime d) => DateFormat('dd/MM').format(d);

/// Duração do cronômetro: "01:23:45".
String formatarCronometro(Duration d) {
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.inHours)}:${dois(d.inMinutes % 60)}:${dois(d.inSeconds % 60)}';
}

/// "1 erro" / "2 erros" — evita o "1 acertos" que aparecia em toda contagem
/// montada por interpolação direta. Português tem plural regular no que o app
/// conta (erro, acerto, questão, dia), então a forma do plural entra explícita
/// em vez de ser derivada por regra.
String plural(int n, String singular, String plural) =>
    '$n ${n == 1 ? singular : plural}';
