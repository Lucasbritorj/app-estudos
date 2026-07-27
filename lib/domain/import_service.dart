import 'dart:convert';

import '../data/models/ambiente.dart';
import '../data/models/aula.dart';
import '../data/models/leitura.dart';
import '../data/models/materia.dart';
import '../data/models/registro_hora.dart';
import '../data/models/resumo.dart';
import '../data/models/revisao.dart';
import '../data/models/simulado.dart';
import '../data/models/topico.dart';

class BackupImportado {
  final List<Ambiente> ambientes;
  final List<Materia> materias;
  final List<Topico> topicos;
  final List<Aula> aulas;
  final List<RegistroHora> registros;
  final List<Revisao> revisoes;
  final List<Leitura> leituras;
  final Map<int, int> planejamento;
  final List<Simulado> simulados;
  final List<Resumo> resumos;

  const BackupImportado({
    this.ambientes = const [],
    required this.materias,
    required this.topicos,
    required this.aulas,
    required this.registros,
    required this.revisoes,
    required this.leituras,
    required this.planejamento,
    this.simulados = const [],
    this.resumos = const [],
  });

  /// Ambientes prontos para gravação: backup pré-Ambientes (lista vazia)
  /// ganha o "Geral", que é onde as matérias dele caem via fromJson.
  List<Ambiente> ambientesOuGeral(DateTime agora) => ambientes.isNotEmpty
      ? ambientes
      : [Ambiente(id: Ambiente.geralId, nome: 'Geral', criadoEm: agora)];

  String get resumo =>
      '${ambientes.length} ambientes, '
      '${materias.length} matérias, ${topicos.length} tópicos, '
      '${aulas.length} aulas, ${registros.length} registros, '
      '${revisoes.length} revisões, ${leituras.length} leituras, '
      '${resumos.length} resumos';
}

/// Parser do backup JSON gerado pelo próprio app (ExportService.jsonCompleto).
/// Falha com FormatException explícita — nunca importa parcial em silêncio.
class ImportService {
  static BackupImportado parseBackup(String jsonTexto) {
    final Object? raw;
    try {
      raw = jsonDecode(jsonTexto);
    } on FormatException {
      throw const FormatException('Texto colado não é JSON válido.');
    }
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('JSON não é um objeto de backup.');
    }
    // Cópia tipada: promoção de tipo não atravessa closures.
    final Map<String, dynamic> mapa = raw;
    final versao = mapa['versao'];
    if (versao != 1) {
      throw FormatException('Versão de backup não suportada: $versao');
    }

    List<T> lista<T>(String chave, T Function(Map<String, dynamic>) fromJson) {
      final bruta = mapa[chave];
      if (bruta == null) return [];
      if (bruta is! List) {
        throw FormatException('Campo "$chave" não é uma lista.');
      }
      try {
        return bruta
            .map((e) => fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (erro) {
        throw FormatException('Item inválido em "$chave": $erro');
      }
    }

    final planoBruto = mapa['planejamento'];
    final planejamento = <int, int>{};
    if (planoBruto is Map) {
      planoBruto.forEach((k, v) {
        final dia = int.tryParse(k.toString());
        if (dia == null || dia < 1 || dia > 7) return;
        // Contrato do parser: entrada inválida vira FormatException — um
        // `as num` aqui lançaria TypeError e furaria o catch da UI.
        if (v is! num) {
          throw FormatException(
            'Valor de planejamento inválido para o dia $dia: "$v"',
          );
        }
        final minutos = v.toInt();
        planejamento[dia] = minutos < 0 ? 0 : minutos;
      });
    }

    return BackupImportado(
      // Backups antigos não têm 'ambientes' — lista() devolve vazio.
      ambientes: lista('ambientes', Ambiente.fromJson),
      materias: lista('materias', Materia.fromJson),
      topicos: lista('topicos', Topico.fromJson),
      // Backups antigos não têm 'aulas' — lista() devolve vazio.
      aulas: lista('aulas', Aula.fromJson),
      registros: lista('registros', RegistroHora.fromJson),
      revisoes: lista('revisoes', Revisao.fromJson),
      leituras: lista('leituras', Leitura.fromJson),
      planejamento: planejamento,
      simulados: lista('simulados', Simulado.fromJson),
      // Backups antigos não têm 'resumos' — lista() devolve vazio.
      resumos: lista('resumos', Resumo.fromJson),
    );
  }
}
