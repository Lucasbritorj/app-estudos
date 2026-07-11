import 'package:intl/intl.dart';

/// 135 -> "2h 15min"; 120 -> "2h"; 45 -> "45min".
String formatarMinutos(int minutos) {
  if (minutos < 60) return '${minutos}min';
  final h = minutos ~/ 60;
  final m = minutos % 60;
  return m == 0 ? '${h}h' : '${h}h ${m.toString().padLeft(2, '0')}min';
}

String formatarData(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

String formatarDiaMes(DateTime d) => DateFormat('dd/MM').format(d);

/// Duração do cronômetro: "01:23:45".
String formatarCronometro(Duration d) {
  String dois(int n) => n.toString().padLeft(2, '0');
  return '${dois(d.inHours)}:${dois(d.inMinutes % 60)}:${dois(d.inSeconds % 60)}';
}
