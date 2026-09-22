import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

bool _adquirida = false;
Future<bool>? _pendente;
Future<bool> adquirirInstancia() async {
  if (_adquirida) return true;
  return _pendente ??= _adquirir().whenComplete(() => _pendente = null);
}

Future<bool> _adquirir() async {
  final resultado = Completer<bool>();
  try {
    final requisicao = web.window.navigator.locks.request(
      'app-estudos-hive-escrita',
      web.LockOptions(ifAvailable: true),
      ((web.Lock? lock) {
        _adquirida = _adquirida || lock != null;
        resultado.complete(_adquirida);
        // Mantém o lock até fechar/recarregar esta aba, antes de abrir o Hive.
        return lock == null
            ? Future<JSAny?>.value(null).toJS
            : Completer<JSAny?>().future.toJS;
      }).toJS,
    );
    unawaited(
      requisicao.toDart.catchError((Object erro) {
        if (!resultado.isCompleted) resultado.completeError(erro);
        return null;
      }),
    );
  } catch (erro, pilha) {
    resultado.completeError(erro, pilha);
  }
  return resultado.future;
}
