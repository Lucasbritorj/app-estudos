// Compartilhamento de arquivos exportados, por plataforma: em io grava
// temp + compartilha caminho; no web compartilha os bytes direto.
export 'compartilhador_io.dart'
    if (dart.library.js_interop) 'compartilhador_web.dart';
