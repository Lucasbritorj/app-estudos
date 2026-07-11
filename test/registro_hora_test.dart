import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final data = DateTime(2026, 7, 9, 14, 30);

  group('paginasLidas', () {
    test('intervalo é inclusivo: pág. 10 à 20 = 11 páginas', () {
      final registro = RegistroHora(
        id: 'a',
        data: data,
        materiaId: 'm1',
        minutos: 60,
        paginaInicial: 10,
        paginaFinal: 20,
      );
      expect(registro.paginasLidas, 11);
    });

    test('valor manual sobrescreve o intervalo', () {
      final registro = RegistroHora(
        id: 'a',
        data: data,
        materiaId: 'm1',
        minutos: 60,
        paginaInicial: 10,
        paginaFinal: 20,
        paginasLidasManual: 8,
      );
      expect(registro.paginasLidas, 8);
    });

    test('sem páginas retorna null', () {
      final registro = RegistroHora(
        id: 'a',
        data: data,
        materiaId: 'm1',
        minutos: 60,
      );
      expect(registro.paginasLidas, isNull);
      expect(registro.paginasPorHora, isNull);
    });
  });

  group('paginasPorHora', () {
    test('22 páginas em 120min = 11 pág/h', () {
      final registro = RegistroHora(
        id: 'a',
        data: data,
        materiaId: 'm1',
        minutos: 120,
        paginaInicial: 1,
        paginaFinal: 22,
      );
      expect(registro.paginasPorHora, 11.0);
    });

    test('minutos = 0 retorna null, sem divisão por zero', () {
      final registro = RegistroHora(
        id: 'a',
        data: data,
        materiaId: 'm1',
        minutos: 0,
        paginaInicial: 1,
        paginaFinal: 10,
      );
      expect(registro.paginasPorHora, isNull);
    });
  });

  test('json roundtrip preserva todos os campos', () {
    final original = RegistroHora(
      id: 'abc',
      data: data,
      materiaId: 'm1',
      topicoId: 't1',
      tarefa: 'Aula 12',
      minutos: 90,
      paginaInicial: 5,
      paginaFinal: 15,
      comentario: 'difícil',
    );
    final copia = RegistroHora.fromJson(original.toJson());
    expect(copia.id, original.id);
    expect(copia.data, original.data);
    expect(copia.materiaId, original.materiaId);
    expect(copia.topicoId, original.topicoId);
    expect(copia.tarefa, original.tarefa);
    expect(copia.minutos, original.minutos);
    expect(copia.paginasLidas, 11);
    expect(copia.comentario, original.comentario);
  });
}
