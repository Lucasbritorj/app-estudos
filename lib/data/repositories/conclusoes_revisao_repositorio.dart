import 'package:hive_ce/hive.dart';
import '../local/hive_boxes.dart';

/// Write-ahead journal: intenção completa antes dos efeitos multi-box.
/// Aplicadas são recibos permanentes, não reaplicados após exclusão pelo usuário.
class ConclusoesRevisaoRepositorio {
  static Future<void> _fila = Future.value();

  /// Serializa IDs diferentes também: compartilham o teto diário.
  static Future<T> exclusivo<T>(Future<T> Function() executar) {
    final resultado = _fila.then((_) => executar());
    _fila = resultado.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return resultado;
  }

  static Box<Map> get box => Hive.box<Map>(HiveBoxes.conclusoesRevisao);

  static Future<void> guardar(Map<String, dynamic> operacao) async {
    await box.put(operacao['id'], operacao);
    await box.flush();
  }

  /// Cada efeito usa o ID reservado na intenção; replay nunca cria IDs.
  /// Callback permite interromper a escrita em testes de recuperação reais.
  static Future<void> aplicar(
    Map<String, dynamic> operacao, {
    Future<void> Function(String etapa)? aposEtapa,
  }) async {
    if (operacao['aplicada'] == true) return;
    for (final efeito in [
      ('sessao', HiveBoxes.registros),
      ('feita', HiveBoxes.revisoes),
      ('proxima', HiveBoxes.revisoes),
    ]) {
      final raw = operacao[efeito.$1] as Map?;
      if (raw != null) {
        final destino = Hive.box<Map>(efeito.$2);
        await destino.put(raw['id'], raw);
        await destino.flush();
      }
      await aposEtapa?.call(efeito.$1);
    }
    await guardar({...operacao, 'aplicada': true});
  }

  /// Também executado no boot e antes de iniciar outra conclusão.
  static Future<void> recuperar() async {
    for (final raw in box.values.toList()) {
      if (raw['aplicada'] != true) {
        await aplicar(Map<String, dynamic>.from(raw));
      }
    }
    await preservarLegadas();
  }

  static Future<void> preservarLegadas() async {
    for (final raw in Hive.box<Map>(HiveBoxes.revisoes).values.toList()) {
      if (raw['feita'] != true || box.containsKey(raw['id'])) continue;
      await guardar({
        'id': raw['id'],
        'feita': Map<String, dynamic>.from(raw),
        'sessao': null,
        'proxima': null,
        'taxaAcerto': null,
        'reforco': false,
        'aplicada': true,
      });
    }
  }

  static int concluidasNoDia(DateTime dia) => box.values.where((raw) {
    final feita = raw['feita'] as Map;
    final data = DateTime.tryParse(feita['dataConclusao'] as String? ?? '');
    return data != null &&
        data.year == dia.year &&
        data.month == dia.month &&
        data.day == dia.day;
  }).length;
}
