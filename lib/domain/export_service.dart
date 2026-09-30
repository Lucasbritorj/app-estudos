import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../data/models/ambiente.dart';
import '../data/models/configuracoes.dart';
import '../data/models/aula.dart';
import '../data/models/materia.dart';
import '../data/models/questao_errada.dart';
import '../data/models/registro_hora.dart';
import '../data/models/resumo.dart';
import '../data/models/revisao.dart';
import '../data/models/simulado.dart';
import '../data/models/topico.dart';
import '../data/models/leitura.dart';
import 'stats_service.dart';

/// Serialização de export — funções puras, testáveis.
class ExportService {
  /// Valor do campo `escopo` no backup de um único ambiente. Contrato com
  /// [ImportService]: backup com essa marca é PARCIAL e não pode substituir
  /// as coleções globais.
  static const escopoAmbiente = 'ambiente';

  /// Rótulos das linhas sintéticas de dimensão criadas para chaves que só
  /// existem no fato (entidade excluída com histórico preservado).
  ///
  /// [nomeMateriaExcluida] é o ÚLTIMO recurso: quando `materiasHistoricas`
  /// traz o tombstone, o nome real é usado. Sem isso, N matérias excluídas
  /// viravam N linhas com o mesmo rótulo — ids distintos, nome idêntico —, e
  /// um gráfico agrupado por nome fundia todas numa barra só.
  static const nomeMateriaExcluida = '(matéria excluída)';
  static const nomeTopicoExcluido = '(tópico excluído)';
  static const nomeAmbienteExcluido = '(ambiente excluído)';

  /// CSV com separador ';' e decimal com vírgula (convenção Excel pt-BR).
  static String csvRegistros(
    List<RegistroHora> registros,
    Map<String, Materia> materias,
    Map<String, Topico> topicos,
  ) {
    final buffer = StringBuffer(
      'Data;Matéria;Tópico;Tarefa;Minutos;Pág. inicial;Pág. final;Páginas lidas;Pág/h;Comentário\r\n',
    );
    final ordenados = [...registros]..sort((a, b) => a.data.compareTo(b.data));
    for (final r in ordenados) {
      final ritmo = r.paginasPorHora;
      buffer.write(
        [
          '${_doisDigitos(r.data.day)}/${_doisDigitos(r.data.month)}/${r.data.year}',
          _campo(materias[r.materiaId]?.nome ?? ''),
          _campo(topicos[r.topicoId]?.nome ?? ''),
          _campo(r.tarefa),
          '${r.minutos}',
          r.paginaInicial?.toString() ?? '',
          r.paginaFinal?.toString() ?? '',
          r.paginasLidas?.toString() ?? '',
          ritmo == null ? '' : ritmo.toStringAsFixed(1).replaceAll('.', ','),
          _campo(r.comentario ?? ''),
        ].join(';'),
      );
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  /// CSV "flat" para BI (Power BI/ThoughtSpot): 1 linha por sessão, união de
  /// horas + questões + metas. Separador ',', decimal com PONTO, datas ISO
  /// YYYY-MM-DD, colunas snake_case — injeta direto sem transformação.
  ///
  /// [materiasHistoricas] inclui as excluídas (tombstone). Sem ela, sessão de
  /// matéria excluída saía com `materia` e `peso_materia` VAZIOS — e como o
  /// flat não carrega `materia_id`, duas matérias excluídas diferentes viravam
  /// o mesmo balde em branco e qualquer medida ponderada perdia aqueles
  /// minutos. `materia_excluida` diz qual linha veio de matéria que não existe
  /// mais, para o filtro do BI.
  static String csvBi(
    List<RegistroHora> registros,
    Map<String, Materia> materias,
    Map<String, Topico> topicos, {
    required int metaSemanalMinutos,
    Map<String, Materia> materiasHistoricas = const {},
  }) {
    final buffer = StringBuffer(
      'data,semana_inicio,materia,peso_materia,topico,tarefa,minutos,horas,'
      'pagina_inicial,pagina_final,paginas_lidas,paginas_por_hora,'
      'questoes,acertos,taxa_acerto,meta_semanal_minutos,comentario,'
      'materia_excluida\r\n',
    );
    final ordenados = [...registros]..sort((a, b) => a.data.compareTo(b.data));
    for (final r in ordenados) {
      final viva = materias[r.materiaId];
      final materia = viva ?? materiasHistoricas[r.materiaId];
      buffer.write(
        [
          _iso(r.data),
          _iso(StatsService.inicioDaSemana(r.data)),
          _campoBi(materia?.nome ?? ''),
          materia?.peso.toString() ?? '',
          _campoBi(topicos[r.topicoId]?.nome ?? ''),
          _campoBi(r.tarefa),
          '${r.minutos}',
          (r.minutos / 60.0).toStringAsFixed(4),
          r.paginaInicial?.toString() ?? '',
          r.paginaFinal?.toString() ?? '',
          r.paginasLidas?.toString() ?? '',
          r.paginasPorHora?.toStringAsFixed(2) ?? '',
          r.questoes?.toString() ?? '',
          r.acertos?.toString() ?? '',
          r.taxaAcerto?.toStringAsFixed(4) ?? '',
          '$metaSemanalMinutos',
          _campoBi(r.comentario ?? ''),
          // Coluna no FIM de propósito: `UAT-G9` e `export_service_test` leem
          // campos por POSIÇÃO, então inserir no meio quebraria a leitura.
          '${viva == null}',
        ].join(','),
      );
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  /// Modelo estrela para BI (Power BI/DAX): 1 tabela fato no grão sessão
  /// (só chaves e medidas) + dimensões normalizadas. Nome de arquivo →
  /// conteúdo CSV (separador ',', decimal ponto, datas ISO, snake_case).
  /// A dim_data cobre do primeiro ao último registro — relacionamento
  /// 1:* pronto, sem CALENDARAUTO.
  ///
  /// [materiasHistoricas] inclui as excluídas (tombstone) e é o que dá nome,
  /// peso e ambiente REAIS às linhas sintéticas de [dimMateria]. Sem ela o
  /// modelo continua íntegro, só que anônimo.
  static Map<String, String> modeloEstrela({
    required List<RegistroHora> registros,
    required List<Materia> materias,
    required List<Topico> topicos,
    required List<Ambiente> ambientes,
    Map<String, Materia> materiasHistoricas = const {},
  }) {
    final fato = StringBuffer(
      'registro_id,data,materia_id,topico_id,aula_id,tipo,minutos,horas,'
      'paginas_lidas,questoes,acertos,erros,taxa_acerto\r\n',
    );
    final ordenados = [...registros]..sort((a, b) => a.data.compareTo(b.data));
    for (final r in ordenados) {
      final erros = (r.questoes != null && r.acertos != null)
          ? r.questoes! - r.acertos!
          : null;
      fato.write(
        [
          r.id,
          _iso(r.data),
          r.materiaId,
          r.topicoId ?? '',
          r.aulaId ?? '',
          r.tipo.name,
          '${r.minutos}',
          (r.minutos / 60.0).toStringAsFixed(4),
          r.paginasLidas?.toString() ?? '',
          r.questoes?.toString() ?? '',
          r.acertos?.toString() ?? '',
          erros?.toString() ?? '',
          r.taxaAcerto?.toStringAsFixed(4) ?? '',
        ].join(','),
      );
      fato.write('\r\n');
    }

    // `excluida` fica no FIM e é coluna própria porque `arquivada` não podia
    // acumular os dois sentidos: arquivar é estado legítimo de matéria viva,
    // excluir é outra coisa. A linha sintética marcava `arquivada=true` e
    // misturava as duas leituras em qualquer filtro do BI.
    final dimMateria = StringBuffer(
      'materia_id,nome,ambiente_id,peso,intimidade,questoes_prova,minimo,'
      'arquivada,excluida\r\n',
    );
    final ambientesReferenciados = <String>{};
    void linhaMateria(Materia m, {required bool excluida}) {
      ambientesReferenciados.add(m.ambienteId);
      dimMateria.write(
        [
          m.id,
          _campoBi(m.nome),
          m.ambienteId,
          '${m.peso}',
          '${m.intimidade}',
          m.questoes?.toString() ?? '',
          m.minimo?.toString() ?? '',
          '${m.arquivada}',
          '$excluida',
        ].join(','),
      );
      dimMateria.write('\r\n');
    }

    for (final m in materias) {
      linhaMateria(m, excluida: false);
    }
    // Chave do fato sem linha na dimensão = relacionamento quebrado no Power
    // BI (linha em branco, medida que não soma por matéria). Acontece sempre
    // que uma matéria é excluída: a cascata preserva os registros de propósito
    // (log histórico), mas a matéria some. Uma linha sintética por chave órfã
    // mantém a integridade referencial do modelo estrela.
    //
    // Com o tombstone em mãos ([materiasHistoricas]) a linha sai com nome,
    // peso, ambiente e intimidade REAIS. O rótulo genérico só entra quando o
    // tombstone não veio — aí duas matérias excluídas realmente são
    // indistinguíveis, e o `materia_id` continua sendo a única chave.
    final idsMateria = {for (final m in materias) m.id};
    for (final id in ordenados.map((r) => r.materiaId).toSet()) {
      if (idsMateria.contains(id)) continue;
      final tombstone = materiasHistoricas[id];
      if (tombstone != null) {
        linhaMateria(tombstone, excluida: true);
        continue;
      }
      dimMateria.write(
        [
          id,
          _campoBi(nomeMateriaExcluida),
          '', // ambiente desconhecido: a matéria não existe mais
          '', '', '', '', // peso/intimidade/questões/mínimo: sem dado
          'true', // fora dos filtros de matéria ativa
          'true',
        ].join(','),
      );
      dimMateria.write('\r\n');
    }

    final dimTopico = StringBuffer('topico_id,materia_id,nome,concluido\r\n');
    for (final t in topicos) {
      dimTopico.write(
        [t.id, t.materiaId, _campoBi(t.nome), '${t.concluido}'].join(','),
      );
      dimTopico.write('\r\n');
    }
    final idsTopico = {for (final t in topicos) t.id};
    for (final r in ordenados) {
      final id = r.topicoId;
      if (id == null || id.isEmpty || !idsTopico.add(id)) continue;
      dimTopico.write(
        [id, r.materiaId, _campoBi(nomeTopicoExcluido), 'false'].join(','),
      );
      dimTopico.write('\r\n');
    }

    final dimAmbiente = StringBuffer('ambiente_id,nome,data_prova\r\n');
    for (final a in ambientes) {
      dimAmbiente.write(
        [
          a.id,
          _campoBi(a.nome),
          a.dataProva == null ? '' : _iso(a.dataProva!),
        ].join(','),
      );
      dimAmbiente.write('\r\n');
    }
    // Mesmo tratamento de chave órfã que matéria e tópico recebem, um nível
    // acima: `dim_materia.ambiente_id` -> `dim_ambiente`. A UI impede excluir
    // ambiente que ainda tem matéria (`ambientes_screen.dart`), mas um backup
    // importado pode trazer a referência pendurada — e o tombstone de uma
    // matéria pode apontar para ambiente que sumiu depois dela.
    //
    // `ambiente_id` vazio fica FORA: só aparece na linha sintética sem
    // tombstone, onde o ambiente é de fato desconhecido. Uma linha de
    // dimensão com chave vazia seria pior que a ausência.
    final idsAmbiente = {for (final a in ambientes) a.id};
    for (final id in ambientesReferenciados) {
      if (id.isEmpty || idsAmbiente.contains(id)) continue;
      dimAmbiente.write([id, _campoBi(nomeAmbienteExcluido), ''].join(','));
      dimAmbiente.write('\r\n');
    }

    final dimData = StringBuffer(
      'data,ano,mes,nome_mes,dia,dia_semana,nome_dia_semana,semana_inicio,'
      'trimestre,eh_fim_de_semana\r\n',
    );
    if (ordenados.isNotEmpty) {
      const nomesMes = [
        'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', //
        'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
      ];
      const nomesDia = [
        'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', //
        'domingo',
      ];
      final primeiro = StatsService.dataSemHora(ordenados.first.data);
      final ultimo = StatsService.dataSemHora(ordenados.last.data);
      for (
        var d = primeiro;
        !d.isAfter(ultimo);
        d = DateTime(d.year, d.month, d.day + 1)
      ) {
        dimData.write(
          [
            _iso(d),
            '${d.year}',
            '${d.month}',
            nomesMes[d.month - 1],
            '${d.day}',
            '${d.weekday}',
            nomesDia[d.weekday - 1],
            _iso(StatsService.inicioDaSemana(d)),
            '${(d.month - 1) ~/ 3 + 1}',
            '${d.weekday >= 6}',
          ].join(','),
        );
        dimData.write('\r\n');
      }
    }

    return {
      'fato_registros.csv': fato.toString(),
      'dim_materia.csv': dimMateria.toString(),
      'dim_topico.csv': dimTopico.toString(),
      'dim_ambiente.csv': dimAmbiente.toString(),
      'dim_data.csv': dimData.toString(),
    };
  }

  /// Zipa o modelo estrela (1 arquivo por tabela) para compartilhar de uma
  /// vez — o pacote archive já é dependência (leitor .xlsx).
  static Uint8List zipModeloEstrela(Map<String, String> tabelas) {
    final archive = Archive();
    for (final e in tabelas.entries) {
      final bytes = utf8.encode(e.value);
      archive.addFile(ArchiveFile(e.key, bytes.length, bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _iso(DateTime d) =>
      '${d.year}-${_doisDigitos(d.month)}-${_doisDigitos(d.day)}';

  /// Campo CSV de BI (separador vírgula): aspas quando contém , aspas ou
  /// quebra de linha.
  static String _campoBi(String valor) {
    final texto = _semFormula(valor);
    if (texto.contains(',') ||
        texto.contains('"') ||
        texto.contains('\n') ||
        texto.contains('\r')) {
      return '"${texto.replaceAll('"', '""')}"';
    }
    return texto;
  }

  /// Neutraliza início de fórmula (CSV injection, CWE-1236): o Excel executa
  /// células iniciadas em = + - @ tab CR mesmo entre aspas — dado vindo de
  /// planilha/edital/backup de terceiro rodaria no Excel de quem abre o
  /// export. O apóstrofo força texto sem alterar o conteúdo exibido.
  static String _semFormula(String valor) {
    if (valor.isEmpty) return valor;
    const gatilhos = ['=', '+', '-', '@', '\t', '\r'];
    return gatilhos.contains(valor[0]) ? "'$valor" : valor;
  }

  /// Dump completo para backup/re-import futuro. `ambientes` e `resumos` são
  /// campos tolerantes: backups antigos sem eles continuam válidos (ambiente
  /// cai no "Geral"; resumos vira lista vazia).
  static String jsonCompleto({
    List<Ambiente> ambientes = const [],
    required List<Materia> materias,
    required List<Topico> topicos,
    required List<Aula> aulas,
    required List<RegistroHora> registros,
    required List<Revisao> revisoes,
    required List<Leitura> leituras,
    required Map<int, int> planejamento,
    List<Simulado> simulados = const [],
    List<Resumo> resumos = const [],
    List<QuestaoErrada> questoesErradas = const [],
    // Fotos do caderno de erros (F1): id da questão -> bytes crus (NÃO já em
    // base64 — quem chama passa o mesmo formato que lê de
    // `AnexosQuestaoRepositorio`, e a codificação fica só aqui dentro,
    // simétrico ao resto desta classe, que recebe listas de modelos
    // tipados, não JSON pré-serializado). Campo tolerante, igual
    // `ambientes`/`resumos`: backup sem foto nenhuma não precisa passar
    // nada.
    Map<String, Uint8List> anexos = const {},
    Configuracoes? configuracoes,
    Map<String, Map>? extensoes,
    List<Map>? conclusoesRevisao,
    String? escopo,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'exportadoEm': DateTime.now().toIso8601String(),
      'versao': 1,
      // Marca de backup PARCIAL (ver jsonAmbiente): as coleções globais
      // (leituras, resumos, planejamento) saem vazias por escopo, não por o
      // usuário não ter nada. Sem essa marca, restaurar um backup de ambiente
      // em modo "substituir" apagava a lista de leituras, os resumos e o
      // cronograma inteiros — perda irreversível.
      // ignore: use_null_aware_elements
      if (escopo != null) 'escopo': escopo,
      'ambientes': ambientes.map((a) => a.toJson()).toList(),
      'materias': materias.map((m) => m.toJson()).toList(),
      'topicos': topicos.map((t) => t.toJson()).toList(),
      'aulas': aulas.map((a) => a.toJson()).toList(),
      'registros': registros.map((r) => r.toJson()).toList(),
      'revisoes': revisoes.map((r) => r.toJson()).toList(),
      'leituras': leituras.map((l) => l.toJson()).toList(),
      'planejamento': planejamento.map((k, v) => MapEntry(k.toString(), v)),
      'simulados': simulados.map((s) => s.toJson()).toList(),
      'resumos': resumos.map((r) => r.toJson()).toList(),
      'questoesErradas': questoesErradas.map((q) => q.toJson()).toList(),
      // Base64: JSON não tem tipo binário. Custa +33% de tamanho sobre os
      // bytes crus, mas só entra no arquivo quem de fato tem foto anexada —
      // é exatamente o trade-off que justifica a compressão obrigatória na
      // captura (ver `_selecionarFoto` em caderno_screen.dart).
      'anexos': anexos.map((id, bytes) => MapEntry(id, base64Encode(bytes))),
      // Preferências do usuário (meta semanal, intervalos, lembretes) faziam
      // parte do "backup completo" só no nome: restaurar numa instalação nova
      // devolvia os dados e perdia a configuração. Campo tolerante — backup
      // sem ele continua válido na versão 1.
      'configuracoes': configuracoes?.toJson(),
      'extensoes': ?extensoes,
      'conclusoesRevisao': ?conclusoesRevisao,
    });
  }

  /// Backup de UM ambiente: o ambiente + suas matérias e tudo que pende
  /// delas (tópicos, aulas, registros, revisões). Formato = versão 1, então
  /// pode ser importado tanto como substituição quanto como mescla.
  /// Leituras, planejamento e resumos são globais — ficam de fora de
  /// propósito. `Resumo` não tem `materiaId`/`ambienteId` (ver
  /// catalogo_materias.dart): a página é casada por nome normalizado com
  /// QUALQUER matéria do usuário, de qualquer ambiente, então não há como
  /// filtrar por ambiente sem quebrar esse casamento.
  static String jsonAmbiente({
    required Ambiente ambiente,
    required List<Materia> materias,
    required List<Topico> topicos,
    required List<Aula> aulas,
    required List<RegistroHora> registros,
    required List<Revisao> revisoes,
    List<Simulado> simulados = const [],
    List<QuestaoErrada> questoesErradas = const [],
    Map<String, Uint8List> anexos = const {},
  }) {
    final minhasMaterias = materias
        .where((m) => m.ambienteId == ambiente.id)
        .toList();
    final ids = minhasMaterias.map((m) => m.id).toSet();
    final minhasQuestoes = questoesErradas
        .where((q) => ids.contains(q.materiaId))
        .toList();
    // Só os anexos das questões que de fato entraram neste backup parcial —
    // sem o filtro, a foto de uma questão de OUTRO ambiente vazaria para
    // dentro de um arquivo que devia conter só este ambiente.
    final idsQuestao = minhasQuestoes.map((q) => q.id).toSet();
    return jsonCompleto(
      ambientes: [ambiente],
      materias: minhasMaterias,
      topicos: topicos.where((t) => ids.contains(t.materiaId)).toList(),
      aulas: aulas.where((a) => ids.contains(a.materiaId)).toList(),
      registros: registros.where((r) => ids.contains(r.materiaId)).toList(),
      revisoes: revisoes.where((r) => ids.contains(r.materiaId)).toList(),
      leituras: const [],
      planejamento: const {},
      simulados: simulados.where((s) => s.ambienteId == ambiente.id).toList(),
      questoesErradas: minhasQuestoes,
      anexos: {
        for (final e in anexos.entries)
          if (idsQuestao.contains(e.key)) e.key: e.value,
      },
      escopo: escopoAmbiente,
    );
  }

  static String _doisDigitos(int n) => n.toString().padLeft(2, '0');

  /// Campo CSV: envolve em aspas quando contém ; aspas ou quebra de linha.
  static String _campo(String valor) {
    final texto = _semFormula(valor);
    if (texto.contains(';') ||
        texto.contains('"') ||
        texto.contains('\n') ||
        texto.contains('\r')) {
      return '"${texto.replaceAll('"', '""')}"';
    }
    return texto;
  }
}
