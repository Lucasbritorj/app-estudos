import 'dart:math';
import '../data/models/ambiente.dart';
import '../data/models/materia.dart';
import '../data/models/revisao.dart';
import 'planejamento_service.dart';

String diaPlano(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class BlocoDiario {
  final String id, materiaId, motivo;
  final DateTime dia;
  final String? revisaoId;
  final int minutos;
  const BlocoDiario({
    required this.id,
    required this.materiaId,
    required this.dia,
    required this.motivo,
    this.minutos = 15,
    this.revisaoId,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'materiaId': materiaId,
    'dia': dia.toIso8601String(),
    'motivo': motivo,
    'minutos': minutos,
    'revisaoId': revisaoId,
  };
  factory BlocoDiario.fromJson(Map j) => BlocoDiario(
    id: j['id'],
    materiaId: j['materiaId'],
    dia: DateTime.parse(j['dia']),
    motivo: j['motivo'],
    minutos: j['minutos'],
    revisaoId: j['revisaoId'],
  );
}

class PropostaDiaria {
  final List<BlocoDiario> blocos;
  final List<String> avisos;
  const PropostaDiaria(this.blocos, this.avisos);
}

/// Capacidade única pessoal. Revisões são reservas de tempo, nunca conclusões.
class PlanoDiarioService {
  static PropostaDiaria gerar({
    required DateTime hoje,
    required Map<int, int> dias,
    Map<String, int> excecoes = const {},
    required String principal,
    List<String> secundarios = const [],
    int percentualPrincipal = 80,
    required List<Ambiente> ambientes,
    required List<Materia> materias,
    required List<Revisao> revisoes,
    Map<String, double> dominio = const {},
    Map<String, int> feito = const {},
    Map<String, String> comuns = const {},
  }) {
    final inicio = DateTime(hoje.year, hoje.month, hoje.day);
    final alvos = {principal, ...secundarios.where((s) => s != principal)};
    final validos = ambientes
        .where((a) => alvos.contains(a.id) && !a.arquivado)
        .toList();
    final avisos = <String>[];
    for (final a in validos) {
      if (a.dataProva == null) {
        avisos.add('${a.nome}: sem data; planejamento semanal.');
      }
      if (a.dataProva != null && a.dataProva!.isBefore(inicio)) {
        avisos.add('${a.nome}: prova passada; sem novos blocos.');
      }
    }
    bool elegivel(Materia m, DateTime dia) =>
        !m.arquivada &&
        m.excluidaEm == null &&
        validos.any(
          (a) =>
              a.id == m.ambienteId &&
              ((a.dataProva == null && dia.difference(inicio).inDays < 7) ||
                  a.dataProva != null &&
                      !DateTime(
                        a.dataProva!.year,
                        a.dataProva!.month,
                        a.dataProva!.day,
                      ).isBefore(dia)),
        );
    final blocos = <BlocoDiario>[];
    final revisoesReservadas = <String>{};
    final alocado = <String, int>{};
    final quotas = <String, int>{};
    final datas = validos
        .map((a) => a.dataProva)
        .whereType<DateTime>()
        .where((d) => !d.isBefore(inicio))
        .toList();
    final fim = datas.isEmpty
        ? inicio.add(const Duration(days: 6))
        : datas.reduce((a, b) => a.isAfter(b) ? a : b);
    final horizonte = min(366, fim.difference(inicio).inDays + 1);
    if (fim.difference(inicio).inDays >= 366) {
      avisos.add(
        'Prévia limitada a 366 dias; gere novamente durante o acompanhamento.',
      );
    }
    for (var i = 0; i < horizonte; i++) {
      final dia = DateTime(inicio.year, inicio.month, inicio.day + i);
      var restante = (excecoes[diaPlano(dia)] ?? dias[dia.weekday] ?? 0).clamp(
        0,
        960,
      );
      final ms = materias.where((m) => elegivel(m, dia)).toList();
      final ids = ms.map((m) => m.id).toSet();
      final pendentes =
          revisoes
              .where(
                (r) =>
                    !r.feita &&
                    ids.contains(r.materiaId) &&
                    !r.dataAgendada.isAfter(
                      dia
                          .add(const Duration(days: 1))
                          .subtract(const Duration(microseconds: 1)),
                    ) &&
                    !revisoesReservadas.contains(r.id),
              )
              .toList()
            ..sort((a, b) => a.dataAgendada.compareTo(b.dataAgendada));
      for (final r in pendentes) {
        if (restante < 15) break;
        blocos.add(
          BlocoDiario(
            id: '${diaPlano(dia)}:r:${r.id}',
            materiaId: r.materiaId,
            dia: dia,
            motivo: 'Revisão: ${r.titulo}',
            revisaoId: r.id,
          ),
        );
        revisoesReservadas.add(r.id);
        restante -= 15;
      }
      final grupos = ms.map((m) => m.ambienteId).toSet().toList()..sort();
      final pesos = {
        for (final g in grupos)
          g: g == principal
              ? (grupos.length == 1
                    ? 100.0
                    : percentualPrincipal.clamp(1, 99).toDouble())
              : (grupos.contains(principal)
                    ? (100 - percentualPrincipal.clamp(1, 99)) /
                          max(1, grupos.length - 1)
                    : 100.0 / grupos.length),
      };
      for (final g in grupos) {
        quotas.putIfAbsent(g, () => 0);
      }
      while (restante >= 15 && grupos.isNotEmpty) {
        final disponiveis = ms
            .where(
              (m) =>
                  m.minutosAlvo == null ||
                  (feito[m.id] ?? 0) + (alocado[m.id] ?? 0) < m.minutosAlvo!,
            )
            .toList();
        final gs = grupos
            .where((g) => disponiveis.any((m) => m.ambienteId == g))
            .toList();
        if (gs.isEmpty) break;
        gs.sort(
          (a, b) => ((quotas[a]! + 15) / pesos[a]!).compareTo(
            (quotas[b]! + 15) / pesos[b]!,
          ),
        );
        final grupo = gs.first;
        final candidatos = disponiveis
            .where((m) => m.ambienteId == grupo)
            .toList();
        final distribuicao = PlanejamentoService.distribuirPorUtilidade(
          15,
          candidatos,
          {
            for (final m in candidatos)
              m.id:
                  ((dominio[m.id] ?? (m.intimidade - 1) / 4) +
                          (alocado[m.id] ?? 0) / 3000)
                      .clamp(0, 1)
                      .toDouble(),
          },
          blocoMinutos: 15,
          pisoManutencao: 0.05,
        );
        final id = distribuicao.entries.firstWhere((e) => e.value > 0).key;
        blocos.add(
          BlocoDiario(
            id: '${diaPlano(dia)}:e:${blocos.length}',
            materiaId: id,
            dia: dia,
            motivo:
                'Peso, domínio e capacidade do alvo${comuns.containsKey(id) ? ' · conteúdo comum associado' : ''}',
          ),
        );
        alocado[id] = (alocado[id] ?? 0) + 15;
        final associados = {
          if (comuns[id] != null) comuns[id]!,
          ...comuns.entries.where((e) => e.value == id).map((e) => e.key),
        };
        for (final outro in associados.where(
          (s) => s != id && ms.any((m) => m.id == s),
        )) {
          alocado[outro] = (alocado[outro] ?? 0) + 15;
        }
        quotas[grupo] = quotas[grupo]! + 15;
        restante -= 15;
      }
    }
    final pendencia = revisoes
        .where(
          (r) =>
              !r.feita &&
              materias.any((m) => m.id == r.materiaId && elegivel(m, inicio)) &&
              !r.dataAgendada.isAfter(fim) &&
              !revisoesReservadas.contains(r.id),
        )
        .length;
    if (pendencia > 0) {
      avisos.add('$pendencia revisões sem capacidade (${pendencia * 15} min).');
    }
    for (final m in materias.where(
      (m) => elegivel(m, inicio) && m.minutosAlvo != null,
    )) {
      final falta = m.minutosAlvo! - (feito[m.id] ?? 0) - (alocado[m.id] ?? 0);
      if (falta > 0) {
        avisos.add('${m.nome}: faltam $falta min de capacidade para o alvo.');
      }
    }
    return PropostaDiaria(blocos, avisos);
  }
}

/// Validação de fronteira para backup/importação, antes de qualquer escrita.
/// Referências a entidades são verificadas pelo preflight da restauração.
void validarPlanoDiario(Map dados) {
  Never falha(String campo) =>
      throw FormatException('Plano pessoal inválido: $campo.');
  bool inteiro(Object? valor, int min, int max) =>
      valor is int && valor >= min && valor <= max;
  DateTime data(Object? valor, String campo) {
    if (valor is! String) falha(campo);
    final parsed = DateTime.tryParse(valor);
    if (parsed == null) falha(campo);
    return parsed;
  }

  Map mapa(String campo) {
    final valor = dados[campo];
    if (valor == null) return {};
    if (valor is! Map) falha(campo);
    return valor;
  }

  List lista(String campo) {
    final valor = dados[campo];
    if (valor == null) return [];
    if (valor is! List) falha(campo);
    return valor;
  }

  for (final e in mapa('dias').entries) {
    if (e.key is! String ||
        !inteiro(int.tryParse(e.key), 1, 7) ||
        !inteiro(e.value, 0, 960)) {
      falha('dias');
    }
  }
  for (final e in mapa('excecoes').entries) {
    if (e.key is! String ||
        diaPlano(data(e.key, 'excecoes')) != e.key ||
        !inteiro(e.value, 0, 960)) {
      falha('excecoes');
    }
  }
  final principal = dados['principal'];
  if (principal != null && (principal is! String || principal.isEmpty)) {
    falha('principal');
  }
  final secundarios = lista('secundarios');
  if (secundarios.any((s) => s is! String || s.isEmpty || s == principal) ||
      secundarios.toSet().length != secundarios.length) {
    falha('secundarios');
  }
  if (dados['percentual'] != null && !inteiro(dados['percentual'], 10, 90)) {
    falha('percentual');
  }
  for (final e in mapa('comuns').entries) {
    if (e.key is! String ||
        (e.key as String).isEmpty ||
        e.value is! String ||
        (e.value as String).isEmpty ||
        e.key == e.value) {
      falha('comuns');
    }
  }
  final ids = <String>{};
  for (final raw in lista('blocos')) {
    if (raw is! Map) falha('blocos');
    for (final campo in ['id', 'materiaId', 'motivo']) {
      if (raw[campo] is! String || (raw[campo] as String).isEmpty) {
        falha('blocos.$campo');
      }
    }
    if (!ids.add(raw['id'] as String)) falha('blocos duplicados');
    data(raw['dia'], 'blocos.dia');
    if (!inteiro(raw['minutos'], 1, 960)) falha('blocos.minutos');
    if (raw['revisaoId'] != null &&
        (raw['revisaoId'] is! String || (raw['revisaoId'] as String).isEmpty)) {
      falha('blocos.revisaoId');
    }
  }
  final registros = <String>{};
  for (final e in mapa('vinculos').entries) {
    if (e.key is! String ||
        !ids.contains(e.key) ||
        e.value is! String ||
        (e.value as String).isEmpty ||
        !registros.add(e.value as String)) {
      falha('vinculos');
    }
  }
  if (lista('avisos').any((v) => v is! String)) falha('avisos');
}
