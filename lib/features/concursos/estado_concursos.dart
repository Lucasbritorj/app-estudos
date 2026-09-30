/// Validação pura antes de restaurar um backup. Campo ausente é legado válido.
/// Lança FormatException; nunca escreve no Hive nem corrige silenciosamente.
void validarEstadoConcursos(Object? value) {
  if (value == null) return;
  Never invalid() =>
      throw const FormatException('Estado de concursos inválido no backup.');
  if (value is! Map) invalid();
  final state = value;
  bool text(Object? v) => v == null || v is String;
  for (final key in ['perfil', 'consultas', 'publicacoes', 'aprovadas']) {
    if (state[key] != null && state[key] is! Map) invalid();
  }
  final profile = state['perfil'] as Map?;
  if (profile != null && profile.values.any((v) => !text(v))) invalid();
  final followed = state['acompanhados'];
  if (followed != null &&
      (followed is! List ||
          followed.any(
            (v) =>
                v is! String ||
                !RegExp(
                  r'^(fgv|cebraspe|cesgranrio):[A-Za-z0-9_-]{1,100}$',
                ).hasMatch(v),
          ))) {
    invalid();
  }
  final approved = state['aprovadas'] as Map?;
  if (approved != null &&
      approved.entries.any((e) => e.key is! String || e.value is! String)) {
    invalid();
  }
  final queries = state['consultas'] as Map?;
  for (final entry in queries?.entries ?? <MapEntry<dynamic, dynamic>>[]) {
    if (entry.key is! String || entry.value is! Map) invalid();
    final q = entry.value as Map;
    for (final k in ['tentativa', 'sucesso']) {
      if (q[k] != null &&
          (q[k] is! String || DateTime.tryParse(q[k]) == null)) {
        invalid();
      }
    }
    if (!text(q['erro'])) invalid();
  }
  void publication(Object? v, {bool previous = false}) {
    if (v is! Map) invalid();
    final p = v;
    for (final k in ['id', 'versao', 'titulo', 'url', 'fonte']) {
      if (p[k] is! String) invalid();
    }
    final uri = Uri.tryParse(p['url'] as String);
    if (uri?.scheme != 'https' ||
        !{
          'conhecimento.fgv.br',
          'www.cesgranrio.org.br',
          'concursos.cesgranrio.org.br',
          'www.cebraspe.org.br',
          'cdn.cebraspe.org.br',
        }.contains(uri?.host)) {
      invalid();
    }
    for (final k in [
      'data',
      'concurso',
      'escolaridade',
      'localizacao',
      'checksum',
      'verificacao',
      'detectadoEm',
    ]) {
      if (!text(p[k])) invalid();
    }
    if (p['salario'] != null &&
        (p['salario'] is! num || !(p['salario'] as num).isFinite)) {
      invalid();
    }
    if (p['anterior'] != null) {
      if (previous) invalid();
      publication(p['anterior'], previous: true);
    }
  }

  for (final p in (state['publicacoes'] as Map?)?.values ?? <dynamic>[]) {
    publication(p);
  }
}
