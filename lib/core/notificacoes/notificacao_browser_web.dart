import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<bool> pedirPermissao() async {
  try {
    return (await web.Notification.requestPermission().toDart).toDart ==
        'granted';
  } catch (_) {
    return false;
  }
}

bool mostrar(String titulo, String corpo) {
  try {
    if (web.Notification.permission != 'granted') return false;
    web.Notification(
      titulo,
      web.NotificationOptions(body: corpo, tag: 'revisoes-pendentes'),
    );
    return true;
  } catch (_) {
    return false;
  }
}
