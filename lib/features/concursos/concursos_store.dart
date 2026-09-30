import 'package:hive_ce/hive.dart';
import '../../data/local/hive_boxes.dart';
import 'cliente.dart' as cliente;

typedef Consulta = Future<Map<String, dynamic>> Function(String, String);

/// Uma escrita atômica por atualização; sem alterar edital ou histórico de estudo.
class ConcursosStore {
  ConcursosStore({Box<Map>? box, Consulta? consulta})
    : box = box ?? Hive.box<Map>(HiveBoxes.config),
      consulta = consulta ?? cliente.consultar;
  final Box<Map> box;
  final Consulta consulta;
  static bool _ocupado = false;
  Map<String, dynamic> get state =>
      Map<String, dynamic>.from(box.get('concursos') ?? {});
  Future<void> save(Map<String, dynamic> value) => box.put('concursos', value);

  Future<void> atualizar({bool manual = false, DateTime? agora}) async {
    if (_ocupado) return;
    _ocupado = true;
    try {
      final now = agora ?? DateTime.now();
      final snapshot = state;
      final targets = <String>[
        'fgv:',
        'cebraspe:',
        'cesgranrio:',
        ...List<String>.from(snapshot['acompanhados'] ?? []),
      ];
      for (final target in targets.toSet()) {
        final current = state;
        final consultas = Map<String, dynamic>.from(current['consultas'] ?? {});
        final previous = Map<String, dynamic>.from(consultas[target] ?? {});
        final attempted = DateTime.tryParse(previous['tentativa'] ?? '');
        final success = DateTime.tryParse(previous['sucesso'] ?? '');
        if (attempted != null &&
            now.difference(attempted) < const Duration(minutes: 5)) {
          continue;
        }
        if (!manual &&
            success != null &&
            now.difference(success) < const Duration(hours: 6)) {
          continue;
        }
        previous['tentativa'] = now.toIso8601String();
        consultas[target] = previous;
        current['consultas'] = consultas;
        await save(current);
        var invalidated = false;
        final changes = box
            .watch(key: 'concursos')
            .listen((_) => invalidated = true);
        try {
          final parts = target.split(':');
          final response = await consulta(
            parts.first,
            parts.length > 1 ? parts[1] : '',
          );
          await changes.cancel();
          if (invalidated) return;
          final rows = List<Map<String, dynamic>>.from(
            (response['publicacoes'] as List).map(
              (v) => Map<String, dynamic>.from(v as Map),
            ),
          );
          if (rows.isEmpty) {
            throw StateError('Sem dados; resultados anteriores preservados.');
          }
          final latest = state;
          final publications = Map<String, dynamic>.from(
            latest['publicacoes'] ?? {},
          );
          for (final row in rows) {
            final id = row['id'] as String;
            final old = publications[id];
            // Uma falha de download não representa alteração do documento.
            if (old is Map &&
                old['checksum'] != null &&
                row['checksum'] == null &&
                row['titulo'] == old['titulo'] &&
                row['data'] == old['data']) {
              row['checksum'] = old['checksum'];
              row['versao'] = old['versao'];
            }
            publications[id] = {
              ...row,
              'anterior': old is Map && old['versao'] != row['versao']
                  ? (Map.from(old)..remove('anterior'))
                  : (old is Map ? old['anterior'] : null),
              'detectadoEm': old is Map && old['versao'] == row['versao']
                  ? old['detectadoEm']
                  : now.toIso8601String(),
            };
          }
          final statuses = Map<String, dynamic>.from(latest['consultas'] ?? {});
          statuses[target] = {
            ...previous,
            'sucesso': now.toIso8601String(),
            'erro': null,
          };
          await save({
            ...latest,
            'publicacoes': publications,
            'consultas': statuses,
          });
        } catch (e) {
          await changes.cancel();
          if (invalidated) return;
          final latest = state;
          final statuses = Map<String, dynamic>.from(latest['consultas'] ?? {});
          statuses[target] = {...previous, 'erro': e.toString()};
          await save({...latest, 'consultas': statuses});
        } finally {
          await changes.cancel();
        }
      }
    } finally {
      _ocupado = false;
    }
  }
}
