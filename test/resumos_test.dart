import 'dart:io';

import 'package:app_estudos/data/catalogo/catalogo_materias.dart';
import 'package:app_estudos/data/local/hive_boxes.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/resumo.dart';
import 'package:app_estudos/features/resumos/resumos_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  group('catálogo', () {
    test('siglas únicas e não vazias', () {
      final siglas = catalogoMaterias.map((m) => m.sigla).toList();
      expect(siglas.toSet().length, siglas.length);
      expect(siglas.every((s) => s.isNotEmpty), isTrue);
      expect(catalogoMaterias.every((m) => m.nome.isNotEmpty), isTrue);
    });

    test('siglaPara deriva por iniciais ignorando conectivos', () {
      expect(siglaPara('Direito Constitucional'), 'DC');
      expect(siglaPara('Direito do Trabalho'), 'DT');
      expect(siglaPara('Administração Financeira e Orçamentária'), 'AFO');
      expect(siglaPara('Matemática'), 'MAT');
    });
  });

  group('resumo model', () {
    test('roundtrip toJson/fromJson preserva tudo', () {
      final r = Resumo(
        sigla: 'DC',
        nome: 'Direito Constitucional',
        texto: '**CF/88** ==art. 5º==',
        atualizadoEm: DateTime(2026, 7, 13, 10, 30),
        doCatalogo: true,
      );
      final volta = Resumo.fromJson(r.toJson());
      expect(volta.sigla, r.sigla);
      expect(volta.nome, r.nome);
      expect(volta.texto, r.texto);
      expect(volta.atualizadoEm, r.atualizadoEm);
      expect(volta.doCatalogo, isTrue);
    });
  });

  group('seed', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('hive_resumos_');
      Hive.init(dir.path);
      await Hive.openBox<Map>(HiveBoxes.resumos);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test('cria todas as páginas do catálogo e é idempotente', () async {
      await HiveBoxes.seedResumos();
      final box = Hive.box<Map>(HiveBoxes.resumos);
      expect(box.length, catalogoMaterias.length);

      await HiveBoxes.seedResumos();
      expect(box.length, catalogoMaterias.length);
    });

    test('re-seed NUNCA sobrescreve texto editado', () async {
      await HiveBoxes.seedResumos();
      final box = Hive.box<Map>(HiveBoxes.resumos);
      final editado = Resumo.fromJson(Map<String, dynamic>.from(box.get('DC')!))
          .copyWith(texto: 'meu resumo', atualizadoEm: DateTime(2026, 7, 13));
      await box.put('DC', editado.toJson());

      await HiveBoxes.seedResumos();
      final depois =
          Resumo.fromJson(Map<String, dynamic>.from(box.get('DC')!));
      expect(depois.texto, 'meu resumo');
    });
  });

  group('páginas e ligações', () {
    test('matéria do usuário fora do catálogo ganha página com sigla derivada',
        () {
      final resumos = [
        for (final m in catalogoMaterias.take(3))
          Resumo(sigla: m.sigla, nome: m.nome, doCatalogo: true),
      ];
      final materias = [
        Materia(
            id: 'm1',
            nome: 'Legislação do SUS',
            corSlot: 0,
            criadaEm: DateTime(2026, 1, 1)),
      ];
      final paginas = paginasResumo(resumos, materias);
      expect(paginas.length, 4);
      expect(paginas.any((p) => p.nome == 'Legislação do SUS' && p.sigla == 'LS'),
          isTrue);
    });

    test('matéria com nome do catálogo não duplica página', () {
      final resumos = [
        const Resumo(
            sigla: 'DC', nome: 'Direito Constitucional', doCatalogo: true),
      ];
      final materias = [
        Materia(
            id: 'm1',
            nome: 'direito constitucional',
            corSlot: 0,
            criadaEm: DateTime(2026, 1, 1)),
      ];
      expect(paginasResumo(resumos, materias).length, 1);
    });

    test('ligacoesNoTexto só devolve siglas conhecidas, sem repetir', () {
      final ligacoes = ligacoesNoTexto(
        'Ver #DC e #dc de novo, #AFO e #XYZ inexistente',
        {'DC', 'AFO', 'DA'},
      );
      expect(ligacoes, ['AFO', 'DC']);
    });
  });
}
