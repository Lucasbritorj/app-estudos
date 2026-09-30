import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<Map<String, dynamic>> consultar(String fonte, String concurso) async {
  final uri = Uri(
    path: '/api/concursos',
    queryParameters: {
      'fonte': fonte,
      if (concurso.isNotEmpty) 'concurso': concurso,
    },
  );
  final response = await web.window
      .fetch(uri.toString().toJS)
      .toDart
      .timeout(const Duration(seconds: 25));
  final body = await response.text().toDart;
  Map<String, dynamic> result;
  try {
    result = Map<String, dynamic>.from(jsonDecode(body.toDart) as Map);
  } catch (_) {
    throw StateError('Coletor indisponível nesta instalação.');
  }
  if (!response.ok) {
    throw StateError(result['erro']?.toString() ?? 'Falha na coleta');
  }
  return result;
}

void abrirFonte(String url) {
  final uri = Uri.tryParse(url);
  if (uri?.scheme != 'https' ||
      !{
        'conhecimento.fgv.br',
        'www.cesgranrio.org.br',
        'concursos.cesgranrio.org.br',
        'www.cebraspe.org.br',
        'cdn.cebraspe.org.br',
      }.contains(uri?.host)) {
    return;
  }
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
