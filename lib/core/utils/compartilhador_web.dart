import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

/// Web: sem sistema de arquivos — compartilha os bytes direto (share nativo
/// do navegador ou download).
Future<void> compartilharBytes(
    Uint8List bytes, String nomeArquivo, String mime) async {
  await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, name: nomeArquivo, mimeType: mime)]));
}
