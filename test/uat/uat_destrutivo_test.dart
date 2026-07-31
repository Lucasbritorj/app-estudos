// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import '_massa_fake.dart';
import 'package:app_estudos/data/models/aula.dart';
import 'package:app_estudos/data/models/materia.dart';
import 'package:app_estudos/data/models/registro_hora.dart';
import 'package:app_estudos/data/models/revisao.dart';
import 'package:app_estudos/data/models/topico.dart';
import 'package:app_estudos/domain/stats_service.dart';
import 'package:app_estudos/domain/gamificacao_service.dart';
import 'package:app_estudos/domain/dominio_service.dart';
import 'package:app_estudos/domain/prontidao_service.dart';
import 'package:app_estudos/domain/mapa_estudos_service.dart';
import 'package:app_estudos/domain/export_service.dart';

/// Replica EXATAMENTE os predicados de MateriaUseCase.excluirEmCascata
/// (lib/application/materia_use_case.dart) sobre listas em memoria.
class Estado {
  List<Materia> materias;
  List<Topico> topicos;
  List<Aula> aulas;
  List<RegistroHora> registros;
  List<Revisao> revisoes;
  Estado(this.materias, this.topicos, this.aulas, this.registros, this.revisoes);

  void excluirMateriaEmCascata(String materiaId) {
    revisoes = revisoes.where((r) => !(r.materiaId == materiaId && !r.feita)).toList();
    topicos = topicos.where((t) => t.materiaId != materiaId).toList();
    aulas = aulas.where((a) => a.materiaId != materiaId).toList();
    materias = materias.where((m) => m.id != materiaId).toList();
  }

  /// Comportamento ANTIGO: topicos_screen chamava repositorio.remover(id) cru.
  void excluirTopicoCru(String topicoId) {
    topicos = topicos.where((t) => t.id != topicoId).toList();
  }

  /// Transcricao FIEL de TopicoUseCase.excluirEmCascata
  /// (lib/application/topico_use_case.dart).
  void excluirTopicoEmCascata(String topicoId) {
    final alvo = topicos.where((t) => t.id == topicoId).firstOrNull;
    if (alvo == null) return;
    revisoes = revisoes.where((r) => !(r.topicoId == topicoId && !r.feita)).toList();
    topicos = [
      for (final t in topicos)
        if (t.id != topicoId)
          (t.parentId == topicoId || t.prerequisitos.contains(topicoId))
              ? t.copyWith(
                  limparParent: t.parentId == topicoId && alvo.parentId == null,
                  parentId: t.parentId == topicoId ? alvo.parentId : t.parentId,
                  prerequisitos: [
                    for (final id in t.prerequisitos)
                      if (id != topicoId) id,
                  ],
                )
              : t,
    ];
  }

  /// AulaUseCase.excluirEmCascata
  void excluirAulaEmCascata(String aulaId, DateTime agora) {
    revisoes = revisoes.where((r) => !(r.aulaId == aulaId && !r.feita)).toList();
    registros = [
      for (final r in registros) r.aulaId == aulaId ? r.semAula(agora) : r,
    ];
    aulas = aulas.where((a) => a.id != aulaId).toList();
  }
}

Estado estadoDaMassa(Massa m) => Estado(
      [...m.materias], [...m.topicos], [...m.aulas], [...m.registros], [...m.revisoes]);

int xpDe(Estado e) => GamificacaoService.xpDetalhado(
      e.registros, e.revisoes, hoje,
      pesoPorMateria: {for (final m in e.materias) m.id: m.peso},
    ).total;

void main() {
  test('UAT-E1 cascata de materia: o que morre e o que sobrevive', () {
    final e = estadoDaMassa(construirMassa());
    final antes = (
      mat: e.materias.length, top: e.topicos.length, aul: e.aulas.length,
      reg: e.registros.length, rev: e.revisoes.length,
    );
    e.excluirMateriaEmCascata('mat-const');
    print('[E1] antes=$antes');
    print('[E1] depois=(mat:${e.materias.length} top:${e.topicos.length} '
        'aul:${e.aulas.length} reg:${e.registros.length} rev:${e.revisoes.length})');
    expect(e.materias.any((m) => m.id == 'mat-const'), isFalse);
    expect(e.topicos.any((t) => t.materiaId == 'mat-const'), isFalse);
    expect(e.aulas.any((a) => a.materiaId == 'mat-const'), isFalse);
    expect(e.revisoes.any((r) => r.materiaId == 'mat-const' && !r.feita), isFalse);

    final regOrfaos = e.registros.where((r) => r.materiaId == 'mat-const').length;
    final revFeitasOrfas = e.revisoes.where((r) => r.materiaId == 'mat-const').length;
    print('[E1] ORFAOS: registros apontando p/ materia inexistente=$regOrfaos '
        '| revisoes feitas orfas=$revFeitasOrfas');
    expect(regOrfaos, greaterThan(0), reason: 'historico preservado por design');
    expect(revFeitasOrfas, 4, reason: 'revisoes feitas ficam (XP)');
    final topOrfaos = e.registros.where((r) => r.topicoId != null &&
        !e.topicos.any((t) => t.id == r.topicoId)).length;
    print('[E1] registros com topicoId pendurado=$topOrfaos');
  });

  test('UAT-E2 REGRESSAO: XP nao cai ao excluir materia (pesos historicos)', () {
    final massa = construirMassa();
    final e = estadoDaMassa(massa);
    // Pesos de TODAS as materias ja gravadas, inclusive as com tombstone:
    // e o que MateriasRepositorio.pesosHistoricos() devolve (le o box, nao o
    // state) e o que gamificacaoProvider passa depois da correcao.
    final pesosHistoricos = {for (final m in massa.materias) m.id: m.peso};
    final xpAntes = GamificacaoService.xpDetalhado(e.registros, e.revisoes, hoje,
        pesoPorMateria: pesosHistoricos);

    e.excluirMateriaEmCascata('mat-const'); // peso 5 -> multiplicador x1.4

    final soVivas = GamificacaoService.xpDetalhado(e.registros, e.revisoes, hoje,
        pesoPorMateria: {for (final m in e.materias) m.id: m.peso});
    final comHistorico = GamificacaoService.xpDetalhado(e.registros, e.revisoes, hoje,
        pesoPorMateria: pesosHistoricos);
    print('[E2] XP antes=${xpAntes.total} (base=${xpAntes.base})');
    print('[E2] so materias vivas (ANTES da correcao)=${soVivas.total} '
        'delta=${soVivas.total - xpAntes.total} nivel=${GamificacaoService.nivelPara(soVivas.total)}');
    print('[E2] pesos historicos (DEPOIS)=${comHistorico.total} '
        'delta=${comHistorico.total - xpAntes.total} nivel=${GamificacaoService.nivelPara(comHistorico.total)}');
    expect(soVivas.total, lessThan(xpAntes.total),
        reason: 'documenta o defeito: peso perdido derruba o XP');
    expect(comHistorico.total, xpAntes.total,
        reason: 'REGRESSAO: com o peso do tombstone o XP fica intacto');
    expect(GamificacaoService.nivelPara(comHistorico.total),
        GamificacaoService.nivelPara(xpAntes.total));
  });

  test('UAT-E3 fantasmas nos agregados do dashboard depois da cascata', () {
    final e = estadoDaMassa(construirMassa());
    e.excluirMateriaEmCascata('mat-const');
    final minutos = StatsService.minutosPorMateria(e.registros);
    final desemp = StatsService.desempenhoPorMateria(e.registros);
    final vivas = {for (final m in e.materias) m.id};
    final fantasmasMin = minutos.keys.where((k) => !vivas.contains(k)).toList();
    final fantasmasDes = desemp.keys.where((k) => !vivas.contains(k)).toList();
    print('[E3] chaves fantasma em minutosPorMateria=$fantasmasMin');
    print('[E3] chaves fantasma em desempenhoPorMateria=$fantasmasDes');
    print('[E3] card_desempenho renderiza linha com materia=null p/ cada fantasma');
    expect(fantasmasMin, contains('mat-const'));
    expect(fantasmasDes, contains('mat-const'));

    // Prontidao/Elo iteram sobre materias VIVAS -> nao veem fantasma.
    final medidos = DominioService.dominioPorMateria(
        e.registros, e.materias.map((m) => m.id), referencia: hoje);
    final dom = ProntidaoService.dominiosAtuais(e.materias, medidos);
    print('[E3] prontidao pos-exclusao=${ProntidaoService.prontidao(e.materias, dom)}');
    expect(medidos.containsKey('mat-const'), isFalse);
  });

  test('UAT-E4 export sobrevive a fantasmas (nome vazio, sem crash)', () {
    final e = estadoDaMassa(construirMassa());
    e.excluirMateriaEmCascata('mat-const');
    final csv = ExportService.csvRegistros(
      e.registros,
      {for (final m in e.materias) m.id: m},
      {for (final t in e.topicos) t.id: t},
    );
    final linhasSemMateria = csv.split('\r\n').where((l) => l.startsWith(RegExp(r'\d\d/\d\d/\d{4};;'))).length;
    print('[E4] linhas de CSV com materia vazia=$linhasSemMateria');
    expect(linhasSemMateria, greaterThan(0), reason: 'sessao historica sem nome de materia');
    final estrela = ExportService.modeloEstrela(
      registros: e.registros, materias: e.materias, topicos: e.topicos, ambientes: [construirMassa().ambiente]);
    Set<String> chaves(String arquivo, int coluna) => {
          for (final l in estrela[arquivo]!.trim().split('\r\n').skip(1))
            l.split(',')[coluna],
        };
    final fatoLinhas = estrela['fato_registros.csv']!.trim().split('\r\n').length - 1;
    final chavesFatoMateria = chaves('fato_registros.csv', 2);
    final chavesFatoTopico = chaves('fato_registros.csv', 3)..remove('');
    final dimMateria = chaves('dim_materia.csv', 0);
    final dimTopico = chaves('dim_topico.csv', 0);
    print('[E4] modelo estrela: fato=$fatoLinhas linhas | '
        'materia_id no fato=${chavesFatoMateria.length} dim_materia=${dimMateria.length} | '
        'topico_id no fato=${chavesFatoTopico.length} dim_topico=${dimTopico.length}');
    print('[E4] linha sintetica presente=${estrela["dim_materia.csv"]!.contains(ExportService.nomeMateriaExcluida)}');
    expect(chavesFatoMateria.difference(dimMateria), isEmpty,
        reason: 'REGRESSAO: todo materia_id do fato tem linha na dimensao');
    expect(chavesFatoTopico.difference(dimTopico), isEmpty,
        reason: 'REGRESSAO: todo topico_id do fato tem linha na dimensao');
    expect(estrela['dim_materia.csv'], contains(ExportService.nomeMateriaExcluida));
    expect(estrela['dim_topico.csv'], contains(ExportService.nomeTopicoExcluido));
  });

  test('UAT-E5 REGRESSAO: excluir topico cascateia revisao pendente e reparenta filhos', () {
    // Comportamento antigo, para contraste.
    final antigo = estadoDaMassa(construirMassa());
    antigo.excluirTopicoCru('top-art5');
    final sobrouCru = antigo.revisoes.where((r) => r.topicoId == 'top-art5' && !r.feita).length;

    final e = estadoDaMassa(construirMassa());
    final pendentesAntes = e.revisoes.where((r) => r.topicoId == 'top-art5' && !r.feita).length;
    final feitasAntes = e.revisoes.where((r) => r.topicoId == 'top-art5' && r.feita).length;
    final registrosAntes = e.registros.length;
    e.excluirTopicoEmCascata('top-art5'); // filho de top-df, pre-req de top-remedios

    final pendentesDepois = e.revisoes.where((r) => r.topicoId == 'top-art5' && !r.feita).length;
    final remedios = e.topicos.firstWhere((t) => t.id == 'top-remedios');
    print('[E5] pendentes de top-art5: antes=$pendentesAntes | cru=$sobrouCru | cascata=$pendentesDepois');
    print('[E5] feitas preservadas=${e.revisoes.where((r) => r.topicoId == "top-art5" && r.feita).length}/$feitasAntes '
        '| registros preservados=${e.registros.length}/$registrosAntes');
    print('[E5] top-remedios: parent=${remedios.parentId} prerequisitos=${remedios.prerequisitos}');
    expect(sobrouCru, pendentesAntes, reason: 'defeito documentado do caminho antigo');
    expect(pendentesDepois, 0, reason: 'REGRESSAO: revisao pendente orfa some');
    expect(e.revisoes.where((r) => r.topicoId == 'top-art5' && r.feita).length, feitasAntes,
        reason: 'revisao feita fica (XP)');
    expect(e.registros.length, registrosAntes, reason: 'log historico intacto');
    expect(remedios.prerequisitos, isEmpty, reason: 'aresta pendurada removida');
  });

  test('UAT-E5b REGRESSAO: filho sobe para o avo (nao desaba para a raiz)', () {
    final e = estadoDaMassa(construirMassa());
    // Exclui o intermediario 'top-df' (raiz) -> filhos viram raiz.
    e.excluirTopicoEmCascata('top-df');
    final art5 = e.topicos.firstWhere((t) => t.id == 'top-art5');
    print('[E5b] excluindo a RAIZ top-df -> art5.parent=${art5.parentId}');
    expect(art5.parentId, isNull);

    // Agora com avo: cria neto sob art5 e exclui art5 (que tem pai top-df).
    final e2 = estadoDaMassa(construirMassa());
    e2.topicos = [
      ...e2.topicos,
      const Topico(id: 'top-neto', materiaId: 'mat-const', parentId: 'top-art5', nome: 'Inciso XI'),
    ];
    e2.excluirTopicoEmCascata('top-art5');
    final neto = e2.topicos.firstWhere((t) => t.id == 'top-neto');
    print('[E5b] excluindo o MEIO top-art5 -> neto.parent=${neto.parentId} (avo=top-df)');
    expect(neto.parentId, 'top-df', reason: 'hierarquia encolhe 1 nivel, nao desaba');
  });

  test('UAT-E6 cascata de aula limpa o vinculo dos registros (contraste com materia)', () {
    final e = estadoDaMassa(construirMassa());
    final comAula = e.registros.where((r) => r.aulaId == 'aula-lic00').length;
    e.excluirAulaEmCascata('aula-lic00', hoje);
    final aindaComAula = e.registros.where((r) => r.aulaId == 'aula-lic00').length;
    print('[E6] registros vinculados: antes=$comAula depois=$aindaComAula '
        '(AulaUseCase limpa aulaId; MateriaUseCase NAO limpa materiaId/topicoId)');
    expect(comAula, greaterThan(0));
    expect(aindaComAula, 0);
    expect(e.revisoes.any((r) => r.aulaId == 'aula-lic00' && !r.feita), isFalse);
  });

  test('UAT-E7 excluir todas as materias: dashboard vazio sem excecao', () {
    final e = estadoDaMassa(construirMassa());
    for (final id in e.materias.map((m) => m.id).toList()) {
      e.excluirMateriaEmCascata(id);
    }
    print('[E7] materias=${e.materias.length} topicos=${e.topicos.length} '
        'registros=${e.registros.length} revisoes=${e.revisoes.length}');
    final medidos = DominioService.dominioPorMateria(e.registros, const [], referencia: hoje);
    print('[E7] prontidao=${ProntidaoService.prontidao(e.materias, const {})} '
        '(null esperado, nao 0% inventado)');
    expect(ProntidaoService.prontidao(e.materias, const {}), isNull);
    expect(ProntidaoService.coberturaConfiavel(e.materias, medidos), 0.0);
    expect(StatsService.taxaAcertoGeral(e.registros), isNotNull,
        reason: 'registros orfaos continuam alimentando a taxa geral');
    print('[E7] taxa geral ainda calculada sobre orfaos='
        '${StatsService.taxaAcertoGeral(e.registros)}');
    expect(MapaEstudosService.fronteira(e.topicos, e.registros), isEmpty);
    expect(StatsService.streakDetalhado(e.registros, hoje).dias, greaterThan(0),
        reason: 'streak sobrevive (deriva de registros)');
  });
}
