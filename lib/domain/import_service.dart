import 'dart:convert';
import 'dart:typed_data';

import '../data/models/ambiente.dart';
import '../data/models/configuracoes.dart';
import '../data/models/aula.dart';
import '../data/models/leitura.dart';
import '../data/models/materia.dart';
import '../data/models/questao_errada.dart';
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
  final List<QuestaoErrada> questoesErradas;

  /// Fotos do caderno de erros (F1): id da questão -> bytes JÁ decodificados
  /// (o base64 é só o formato de transporte dentro do JSON — ver
  /// `ExportService.jsonCompleto`). Tolerante: backup anterior ao F1 não tem
  /// a chave e cai no mapa vazio, nunca falha o import.
  final Map<String, Uint8List> anexos;

  /// Preferências do backup; null em backup antigo (ou de ambiente), e aí a
  /// configuração local NÃO é tocada.
  final Configuracoes? configuracoes;

  /// Marca de escopo gravada pelo gerador (`ExportService.escopoAmbiente`
  /// no backup de um ambiente). Null = backup completo.
  final String? escopo;

  /// Chaves que o ARQUIVO trouxe, com valor não-nulo.
  ///
  /// D-01: `lista()` devolve `[]` tanto para "chave ausente" quanto para
  /// "lista vazia", e a restauração destrutiva tratava os dois igual —
  /// restaurar um backup antigo (sem `resumos`) apagava os resumos de quem
  /// restaurava. É o mesmo cuidado que [configuracoes] já tinha por ser
  /// nulável; as listas não tinham como expressar a diferença.
  ///
  /// Regra: arquivo que FALA vazio zera; arquivo que não fala não decide.
  final Set<String> chavesPresentes;

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
    this.questoesErradas = const [],
    this.anexos = const {},
    this.configuracoes,
    this.escopo,
    this.chavesPresentes = const {},
  });

  /// Se o arquivo mencionou [chave] — base da regra de restauração destrutiva.
  bool mencionou(String chave) => chavesPresentes.contains(chave);

  /// Backup de escopo reduzido: leituras, resumos e planejamento estão vazios
  /// porque ficaram FORA do arquivo, não porque o usuário não os tem. Usar um
  /// desses para "substituir tudo" apagaria essas coleções sem volta — a UI
  /// só pode mesclar.
  bool get parcial => escopo != null;

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
      '${resumos.length} resumos, ${questoesErradas.length} questões erradas'
      '${anexos.isEmpty ? '' : ', ${anexos.length} fotos'}';
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

    final anexosBrutos = mapa['anexos'];
    final anexos = <String, Uint8List>{};
    if (anexosBrutos is Map) {
      anexosBrutos.forEach((chave, valor) {
        // Mesmo contrato do `planejamento` acima: entrada inválida vira
        // FormatException explícita — um `as String` direto lançaria
        // TypeError e furaria o catch da UI.
        if (valor is! String) {
          throw FormatException(
            'Anexo inválido para a questão "$chave": não é uma string base64.',
          );
        }
        // base64Decode já lança FormatException nativamente para texto
        // corrompido (caractere/comprimento/padding inválidos) — não precisa
        // de try/catch próprio aqui, o erro sobe com a mensagem original.
        anexos[chave.toString()] = base64Decode(valor);
      });
    } else if (anexosBrutos != null) {
      throw const FormatException('Campo "anexos" não é um objeto.');
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
      // Backups anteriores ao caderno de erros não têm a chave.
      questoesErradas: lista('questoesErradas', QuestaoErrada.fromJson),
      // Backups anteriores ao F1 não têm a chave — mapa vazio acima.
      anexos: anexos,
      configuracoes: () {
        final bruta = mapa['configuracoes'];
        if (bruta is! Map) return null;
        try {
          return Configuracoes.fromJson(Map<String, dynamic>.from(bruta));
        } catch (erro) {
          throw FormatException('Configurações inválidas no backup: $erro');
        }
      }(),
      escopo: mapa['escopo'] is String ? mapa['escopo'] as String : null,
      // Valor nulo conta como AUSENTE: `jsonCompleto` grava
      // `'configuracoes': null` quando não recebe preferências, e um campo
      // escrito como null não é o arquivo dizendo "apague".
      chavesPresentes: {
        for (final e in mapa.entries)
          if (e.value != null) e.key,
      },
    );
  }
}
