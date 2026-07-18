import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Android/desktop: grava em arquivo temporário e compartilha o caminho.
Future<void> compartilharBytes(
  Uint8List bytes,
  String nomeArquivo,
  String mime,
) async {
  final dir = await getTemporaryDirectory();
  final arquivo = File('${dir.path}${Platform.pathSeparator}$nomeArquivo');
  await arquivo.writeAsBytes(bytes);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(arquivo.path, mimeType: mime)]),
  );
}
