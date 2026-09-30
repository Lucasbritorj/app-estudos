import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:app_estudos/features/concursos/concursos_store.dart';

void main() {
  late Directory dir;
  late Box<Map> box;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('concursos_test');
    Hive.init(dir.path);
    box = await Hive.openBox<Map>('config');
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  Map<String, dynamic> response(String version) => {
    'publicacoes': [
      {
        'id': 'a',
        'versao': version,
        'titulo': 'Edital',
        'url': 'https://conhecimento.fgv.br/x',
      },
    ],
  };
  test('TTL 6h e manual 5min persistem após instanciar novamente', () async {
    var calls = 0;
    Future<Map<String, dynamic>> query(String s, String id) async {
      calls++;
      return response('1');
    }

    final store = ConcursosStore(box: box, consulta: query);
    final now = DateTime(2026, 9, 7);
    await store.atualizar(agora: now);
    expect(calls, 2);
    await ConcursosStore(
      box: box,
      consulta: query,
    ).atualizar(agora: now.add(const Duration(hours: 1)));
    expect(calls, 2);
    await store.atualizar(
      manual: true,
      agora: now.add(const Duration(minutes: 4)),
    );
    expect(calls, 2);
    await store.atualizar(
      manual: true,
      agora: now.add(const Duration(minutes: 5)),
    );
    expect(calls, 4);
    await store.atualizar(agora: now.add(const Duration(hours: 7)));
    expect(calls, 6);
  });
  test(
    'falha mantém cache e histórico; mudança guarda versão anterior',
    () async {
      var version = '1';
      var fail = false;
      final store = ConcursosStore(
        box: box,
        consulta: (s, id) async {
          if (fail) throw StateError('HTTP503');
          return response(version);
        },
      );
      final now = DateTime(2026, 9, 7);
      await store.atualizar(agora: now);
      fail = true;
      await store.atualizar(agora: now.add(const Duration(hours: 7)));
      expect(store.state['publicacoes']['a']['versao'], '1');
      expect(store.state['consultas']['fgv:']['erro'], contains('HTTP503'));
      fail = false;
      version = '2';
      await store.atualizar(agora: now.add(const Duration(hours: 8)));
      expect(store.state['publicacoes']['a']['anterior']['versao'], '1');
    },
  );
  test(
    'acompanhamento antigo da Cesgranrio fica no estado e não é consultado',
    () async {
      await box.put('concursos', {
        'acompanhados': ['cesgranrio:sema-mt-2026', 'fgv:seplagrj'],
      });
      final fontes = <String>[];
      final store = ConcursosStore(
        box: box,
        consulta: (s, id) async {
          fontes.add('$s:$id');
          return response('1');
        },
      );
      await store.atualizar(agora: DateTime(2026, 9, 30));
      expect(fontes, unorderedEquals(['fgv:', 'cebraspe:', 'fgv:seplagrj']));
      expect(store.state['acompanhados'], contains('cesgranrio:sema-mt-2026'));
    },
  );
  test('concorrência não duplica consultas', () async {
    var calls = 0;
    final store = ConcursosStore(
      box: box,
      consulta: (s, id) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        return response('1');
      },
    );
    await Future.wait([store.atualizar(), store.atualizar()]);
    expect(calls, 2);
  });
  for (final restore in [false, true]) {
    test(
      'resposta em voo não repovoa ${restore ? 'restauração' : 'apagamento'}',
      () async {
        final started = Completer<void>();
        final pending = Completer<Map<String, dynamic>>();
        final store = ConcursosStore(
          box: box,
          consulta: (s, id) {
            started.complete();
            return pending.future;
          },
        );
        final run = store.atualizar();
        await started.future;
        if (restore) {
          await box.put('concursos', {
            'perfil': {'termos': 'restaurado'},
          });
        } else {
          await box.delete('concursos');
        }
        pending.complete(response('velho'));
        await run;
        if (restore) {
          expect(box.get('concursos'), {
            'perfil': {'termos': 'restaurado'},
          });
        } else {
          expect(box.containsKey('concursos'), false);
        }
      },
    );
  }
}
