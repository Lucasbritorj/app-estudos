// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import '_massa_fake.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/domain/export_service.dart';
import 'package:app_estudos/domain/import_service.dart';
import 'package:app_estudos/domain/revisao_service.dart';

String backupDaMassa(Massa m, {bool completo = true}) => completo
    ? ExportService.jsonCompleto(
        ambientes: [m.ambiente], materias: m.materias, topicos: m.topicos,
        aulas: m.aulas, registros: m.registros, revisoes: m.revisoes,
        leituras: const [], planejamento: m.planejamento,
        simulados: const [], resumos: const [])
    : ExportService.jsonAmbiente(
        ambiente: m.ambiente, materias: m.materias, topicos: m.topicos,
        aulas: m.aulas, registros: m.registros, revisoes: m.revisoes);

void main() {
  final massa = construirMassa();

  test('UAT-G1 round-trip export -> import sem perda', () {
    final json = backupDaMassa(massa);
    final b = ImportService.parseBackup(json);
    print('[G1] bytes=${json.length} resumo="${b.resumo}"');
    expect(b.materias.length, massa.materias.length);
    expect(b.topicos.length, massa.topicos.length);
    expect(b.aulas.length, massa.aulas.length);
    expect(b.registros.length, massa.registros.length);
    expect(b.revisoes.length, massa.revisoes.length);
    expect(b.planejamento, massa.planejamento);

    final orig = massa.registros.first;
    final volta = b.registros.firstWhere((r) => r.id == orig.id);
    print('[G1] registro: data=${volta.data} min=${volta.minutos} q=${volta.questoes} '
        'a=${volta.acertos} tipo=${volta.tipo.name} pIni=${volta.paginaInicial}');
    expect(volta.data, orig.data);
    expect(volta.minutos, orig.minutos);
    expect(volta.questoes, orig.questoes);
    expect(volta.acertos, orig.acertos);
    expect(volta.tipo, orig.tipo);
    expect(volta.paginasLidas, orig.paginasLidas);

    final rev = massa.revisoes.firstWhere((r) => r.id == 'rev-fut-3');
    final revVolta = b.revisoes.firstWhere((r) => r.id == 'rev-fut-3');
    print('[G1] revisao FSRS: S=${revVolta.estabilidade} D=${revVolta.dificuldade} '
        'intervalo=${revVolta.intervaloDias} agendada=${revVolta.dataAgendada}');
    expect(revVolta.estabilidade, rev.estabilidade);
    expect(revVolta.dificuldade, rev.dificuldade);
    expect(revVolta.dataAgendada, rev.dataAgendada);

    final top = b.topicos.firstWhere((t) => t.id == 'top-remedios');
    expect(top.parentId, 'top-df');
    expect(top.prerequisitos, ['top-art5']);
    print('[G1] hierarquia e DAG preservados: parent=${top.parentId} pre=${top.prerequisitos}');
  });

  test('UAT-G2 rejeicoes explicitas (nunca importa parcial em silencio)', () {
    final casos = <String, String>{
      'texto solto': 'nao sou json',
      'array no topo': '[]',
      'versao 2': '{"versao":2}',
      'versao ausente': '{"materias":[]}',
      'campo nao-lista': '{"versao":1,"materias":{"a":1}}',
      'item invalido': '{"versao":1,"materias":[{"nome":"sem id"}]}',
      'planejamento texto': '{"versao":1,"planejamento":{"1":"muito"}}',
      'registro sem minutos': '{"versao":1,"registros":[{"id":"r","data":"2026-01-01","materiaId":"m"}]}',
    };
    casos.forEach((nome, texto) {
      Object? erro;
      try {
        ImportService.parseBackup(texto);
      } catch (e) {
        erro = e;
      }
      print('[G2] $nome -> ${erro == null ? "ACEITOU (!!)" : "${erro.runtimeType}"}');
      expect(erro, isA<FormatException>(), reason: nome);
    });
  });

  test('UAT-G3 tolerancia a backup antigo (sem ambientes/aulas/resumos)', () {
    final antigo = jsonEncode({
      'versao': 1,
      'materias': [
        {'id': 'm1', 'nome': 'Velha', 'corSlot': 0, 'criadaEm': '2025-01-01T00:00:00.000'}
      ],
      'topicos': [], 'registros': [], 'revisoes': [], 'leituras': [],
      'planejamento': {'1': 60, '9': 999, '0': 10},
    });
    final b = ImportService.parseBackup(antigo);
    final amb = b.ambientesOuGeral(hoje);
    print('[G3] ambientes=${amb.map((a) => a.id).join(",")} aulas=${b.aulas.length} '
        'resumos=${b.resumos.length} planejamento=${b.planejamento}');
    print('[G3] materia caiu no ambiente=${b.materias.first.ambienteId}');
    expect(amb.single.id, 'geral');
    expect(b.planejamento, {1: 60}, reason: 'dias 0 e 9 descartados');
    expect(b.materias.first.ambienteId, 'geral');
  });

  test('UAT-G4 planejamento negativo vira zero; minutos absurdos clampam', () {
    final j = jsonEncode({
      'versao': 1, 'materias': [], 'topicos': [], 'revisoes': [], 'leituras': [],
      'planejamento': {'3': -500},
      'registros': [
        {'id': 'r1', 'data': '2026-07-29T20:00:00.000', 'materiaId': 'm', 'minutos': 100000,
         'questoes': 5, 'acertos': 50, 'paginaInicial': -3, 'paginaFinal': 10}
      ],
    });
    final b = ImportService.parseBackup(j);
    final r = b.registros.single;
    print('[G4] plano=${b.planejamento} minutos=${r.minutos} acertos=${r.acertos} '
        'pIni=${r.paginaInicial} paginasLidas=${r.paginasLidas}');
    expect(b.planejamento, {3: 0});
    expect(r.minutos, RegistroHora.maxMinutosPorSessao);
    expect(r.acertos, 5);
    expect(r.paginaInicial, isNull);
  });

  test('UAT-G5 BUG-CANDIDATO: backup com estabilidade 0 quebra a conclusao', () {
    final j = jsonEncode({
      'versao': 1, 'materias': [], 'topicos': [], 'registros': [], 'leituras': [],
      'revisoes': [
        {'id': 'rv', 'materiaId': 'm', 'titulo': 'x', 'dataAgendada': '2026-07-29T00:00:00.000',
         'intervaloDias': 7, 'feita': false, 'estabilidade': 0, 'dificuldade': 5}
      ],
    });
    final b = ImportService.parseBackup(j);
    final rev = b.revisoes.single;
    print('[G5] import ACEITOU estabilidade=${rev.estabilidade}');
    expect(rev.estabilidade, 0.0, reason: 'Revisao.fromJson nao valida S');
    Object? erro;
    try {
      RevisaoService.proximoPassoFsrs(
        estabilidade: rev.estabilidade, dificuldade: rev.dificuldade,
        intervaloAtual: rev.intervaloDias, taxaAcerto: null);
    } catch (e) {
      erro = e;
    }
    print('[G5] concluir essa revisao: ${erro == null ? "OK (estado invalido cai na semente)" : "LANCOU ${erro.runtimeType}: $erro"}');
    final passo = RevisaoService.proximoPassoFsrs(
        estabilidade: rev.estabilidade, dificuldade: rev.dificuldade,
        intervaloAtual: rev.intervaloDias, taxaAcerto: null);
    print('[G5] passo recuperado: ${passo?.dias}d S=${passo?.estabilidade.toStringAsFixed(4)}');
    expect(erro, isNull, reason: 'REGRESSAO: S=0 vindo de backup nao pode derrubar a cadeia');
    expect(passo, isNotNull);
    expect(passo!.dias, inInclusiveRange(1, RevisaoService.tetoDiasFsrs));
  });

  test('UAT-G6 REGRESSAO: backup de UM ambiente e marcado como parcial', () {
    final parcial = ImportService.parseBackup(backupDaMassa(massa, completo: false));
    final completo = ImportService.parseBackup(backupDaMassa(massa));
    print('[G6] ambiente: escopo=${parcial.escopo} parcial=${parcial.parcial} '
        'leituras=${parcial.leituras.length} plano=${parcial.planejamento}');
    print('[G6] completo: escopo=${completo.escopo} parcial=${completo.parcial}');
    print('[G6] >>> exportar_screen bloqueia "substituir tudo" quando parcial=true '
        '(antes zerava leituras, resumos e plano)');
    expect(parcial.parcial, isTrue);
    expect(parcial.escopo, 'ambiente');
    expect(completo.parcial, isFalse, reason: 'backup completo continua substituivel');
    expect(parcial.materias.length, massa.materias.length);
    // Backup antigo (sem o campo) segue tratado como completo.
    final antigo = ImportService.parseBackup('{"versao":1,"materias":[]}');
    print('[G6] backup legado sem escopo: parcial=${antigo.parcial}');
    expect(antigo.parcial, isFalse);
    // Campo corrompido (numero em vez de string) nao pode lancar.
    final ruim = ImportService.parseBackup('{"versao":1,"escopo":42,"materias":[]}');
    print('[G6] escopo=42 -> escopo=${ruim.escopo} parcial=${ruim.parcial}');
    expect(ruim.parcial, isFalse);
  });

  test('UAT-G7 CSV injection neutralizada em todos os exports', () {
    final maliciosa = Materia(
        id: 'mx', nome: '=HYPERLINK("http://x","clique")', corSlot: 0, criadaEm: hoje);
    final reg = RegistroHora(
        id: 'r1', data: hoje, materiaId: 'mx', minutos: 60,
        comentario: '@SUM(A1:A9);drop', tarefa: '-2+3');
    final csv = ExportService.csvRegistros([reg], {'mx': maliciosa}, const {});
    final bi = ExportService.csvBi([reg], {'mx': maliciosa}, const {}, metaSemanalMinutos: 600);
    final estrela = ExportService.modeloEstrela(
        registros: [reg], materias: [maliciosa], topicos: const [], ambientes: const []);
    print('[G7] csv linha=${csv.split("\r\n")[1]}');
    print('[G7] bi  linha=${bi.split("\r\n")[1]}');
    print('[G7] dim_materia=${estrela["dim_materia.csv"]!.split("\r\n")[1]}');
    expect(csv.contains("'=HYPERLINK"), isTrue);
    expect(csv.contains("'@SUM"), isTrue);
    expect(csv.contains("'-2+3"), isTrue);
    expect(estrela['dim_materia.csv']!.contains("'=HYPERLINK"), isTrue);
  });

  test('UAT-G8 ZIP do modelo estrela abre e traz as 5 tabelas', () {
    final tabelas = ExportService.modeloEstrela(
        registros: massa.registros, materias: massa.materias,
        topicos: massa.topicos, ambientes: [massa.ambiente]);
    final zip = ExportService.zipModeloEstrela(tabelas);
    final lido = ZipDecoder().decodeBytes(zip);
    print('[G8] zip bytes=${zip.length} arquivos=${lido.files.map((f) => f.name).join(",")}');
    expect(lido.files.length, 5);
    final fato = utf8.decode(lido.findFile('fato_registros.csv')!.content as List<int>);
    final linhas = fato.trim().split('\r\n');
    print('[G8] fato: ${linhas.length - 1} linhas | header=${linhas.first}');
    expect(linhas.length - 1, massa.registros.length);
    final dimData = utf8.decode(lido.findFile('dim_data.csv')!.content as List<int>);
    print('[G8] dim_data: ${dimData.trim().split("\r\n").length - 1} dias (cobertura continua)');
    expect(dimData.trim().split('\r\n').length - 1, 59,
        reason: 'do 1o ao ultimo registro, sem buraco');
  });

  test('UAT-G8b REGRESSAO: sem chave orfa, as dimensoes nao ganham linha extra', () {
    final tabelas = ExportService.modeloEstrela(
        registros: massa.registros, materias: massa.materias,
        topicos: massa.topicos, ambientes: [massa.ambiente]);
    final dimMateria = tabelas['dim_materia.csv']!.trim().split('\r\n').length - 1;
    final dimTopico = tabelas['dim_topico.csv']!.trim().split('\r\n').length - 1;
    print('[G8b] dim_materia=$dimMateria (materias=${massa.materias.length}) '
        'dim_topico=$dimTopico (topicos=${massa.topicos.length})');
    expect(dimMateria, massa.materias.length);
    expect(dimTopico, massa.topicos.length);
    expect(tabelas['dim_materia.csv'], isNot(contains(ExportService.nomeMateriaExcluida)));
  });

  test('UAT-G9 CSV BI: decimal com ponto, data ISO, sem separador ambiguo', () {
    final bi = ExportService.csvBi(
        massa.registros.take(3).toList(),
        {for (final m in massa.materias) m.id: m},
        {for (final t in massa.topicos) t.id: t},
        metaSemanalMinutos: 540);
    final linha = bi.split('\r\n')[1].split(',');
    print('[G9] data=${linha[0]} semana=${linha[1]} horas=${linha[7]} taxa=${linha[14]}');
    expect(linha[0], matches(r'^\d{4}-\d{2}-\d{2}$'));
    expect(linha[7], matches(r'^\d+\.\d{4}$'));
  });

  test('UAT-G10 export de ambiente filtra por escopo (nao vaza outro ambiente)', () {
    final outra = Materia(id: 'mat-outro', nome: 'Fora', ambienteId: 'amb-x', corSlot: 7, criadaEm: hoje);
    final json = ExportService.jsonAmbiente(
      ambiente: massa.ambiente,
      materias: [...massa.materias, outra],
      topicos: massa.topicos,
      aulas: massa.aulas,
      registros: [
        ...massa.registros,
        RegistroHora(id: 'fora', data: hoje, materiaId: 'mat-outro', minutos: 99),
      ],
      revisoes: massa.revisoes,
    );
    final b = ImportService.parseBackup(json);
    print('[G10] materias=${b.materias.length} (esperado ${massa.materias.length}) '
        'registros=${b.registros.length} (esperado ${massa.registros.length})');
    expect(b.materias.any((m) => m.id == 'mat-outro'), isFalse);
    expect(b.registros.any((r) => r.id == 'fora'), isFalse);
  });

  test('UAT-G11 revisao feita mantem carimbo de conclusao no round-trip (XP)', () {
    final json = backupDaMassa(massa);
    final b = ImportService.parseBackup(json);
    final feitas = b.revisoes.where((r) => r.feita).toList();
    print('[G11] feitas=${feitas.length} comDataConclusao='
        '${feitas.where((r) => r.dataConclusao != null).length}');
    expect(feitas.every((r) => r.dataConclusao != null), isTrue,
        reason: 'sem carimbo o teto diario de bonus muda o XP');
    final revSemCarimbo = Revisao.fromJson({
      'id': 'x', 'materiaId': 'm', 'titulo': 't',
      'dataAgendada': '2026-01-01T00:00:00.000', 'intervaloDias': 7, 'feita': true,
    });
    print('[G11] backup pre-carimbo: dataConclusao=${revSemCarimbo.dataConclusao} (balde legado)');
    expect(revSemCarimbo.dataConclusao, isNull);
  });
}
