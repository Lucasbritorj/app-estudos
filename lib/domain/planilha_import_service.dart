import '../data/models/materia.dart';
import '../data/models/registro_hora.dart';
import '../data/models/revisao.dart';
import '../data/models/topico.dart';

/// Resultado do import da planilha Excel. Matérias novas e atualizadas vêm
/// separadas para a UI mesclar sem substituir nada.
class PlanilhaImportada {
  final List<Materia> materiasNovas;

  /// Matérias já existentes no app com peso/questões/mínimo vindos da aba
  /// de pesos do edital (ex.: Sefaz).
  final List<Materia> materiasAtualizadas;
  final List<Topico> topicosNovos;
  final List<RegistroHora> registros;
  final List<Revisao> revisoes;

  /// "Horas planejadas para a semana (h)" da aba Visão Geral, em minutos.
  /// null quando a planilha não traz o valor.
  final int? metaSemanalMinutos;

  /// Linhas puladas, com o motivo — nunca descartadas em silêncio.
  final List<String> avisos;

  const PlanilhaImportada({
    required this.materiasNovas,
    required this.materiasAtualizadas,
    required this.topicosNovos,
    required this.registros,
    required this.revisoes,
    required this.metaSemanalMinutos,
    required this.avisos,
  });

  String get resumo => [
    '${registros.length} registros',
    '${revisoes.length} revisões',
    '${materiasNovas.length} matérias novas',
    if (materiasAtualizadas.isNotEmpty)
      '${materiasAtualizadas.length} matérias atualizadas (peso/questões)',
    '${topicosNovos.length} tópicos novos',
    if (metaSemanalMinutos != null)
      'meta semanal ${metaSemanalMinutos! ~/ 60}h',
  ].join(', ');
}

/// Religado à UI em 10/07/2026 (pedido "Import Excel completo"): a tela
/// Exportar chama parse() e mescla o resultado — o import continua sendo
/// migração aditiva, nunca substituição. Os testes em
/// planilha_import_test.dart seguem sendo a documentação executável.
///
/// Mapeia as abas da planilha de estudos (XlsxReader.lerAbas) para o domínio.
///
/// Cabeçalhos da planilha real (casados sem acento/caixa, em qualquer aba):
/// - Registro: Data, Matéria, Tarefa, Aula, Página inicial, Página final,
///   Tempo (coluna única OU mesclada sobre subcolunas Horas/Minutos),
///   Comentário, Páginas lidas. "Páginas/hora" é derivada — ignorada.
/// - Pesos do edital (ex.: Sefaz): Matéria, Número questões, Peso, Mínimo.
/// - Visão Geral: "Horas planejadas para a semana (h)" vira meta semanal.
///   Horas feitas/restantes/acumuladas são DERIVADAS — o app recalcula;
///   importá-las duplicaria fonte de verdade.
/// - Revisões: Data, Matéria, título (O que revisar/Conteúdo), Intervalo,
///   Status/Feita.
///
/// IDs são determinísticos por CONTEÚDO — ver [_idDeConteudo]. Até 08/2026 o
/// id de registro e revisão embutia o ÍNDICE DA LINHA
/// (`xlsx-registro-<i>-<data>`), o que só sobrevivia a reimportar o arquivo
/// byte a byte idêntico. Qualquer edição real da planilha — inserir uma
/// sessão nova no topo, apagar uma linha, ou um único clique em "Classificar"
/// no Excel — deslocava as linhas e trocava TODOS os ids abaixo: o `mesclar`
/// (upsert por id) então gravava a coleção inteira de novo. Duas sessões
/// viravam quatro. Pior: quando duas linhas caíam no mesmo índice com a mesma
/// data, o id colidia e uma sessão sobrescrevia a outra em silêncio.
class PlanilhaImportService {
  /// Ids gerados pelo esquema por ÍNDICE, aposentado em 08/2026 (ver a doc
  /// da classe). Distinguível do atual sem ambiguidade: o antigo traz o
  /// índice inteiro logo após o prefixo e TERMINA na data; o atual começa
  /// pela data e continua com hash e contador, então nunca casa com o `$`.
  ///
  /// Existe para o import poder aposentar de uma vez os registros que o
  /// esquema antigo duplicou — ver o call site em `exportar_screen.dart`.
  static final _esquemaAntigo = RegExp(
    r'^xlsx-(registro|revisao)-\d+-\d{4}-\d{2}-\d{2}$',
  );

  static bool idDeEsquemaAntigo(String id) => _esquemaAntigo.hasMatch(id);

  static final _fnvOffset = BigInt.parse('14695981039346656037');
  static final _fnvPrime = BigInt.parse('1099511628211');
  static final _fnvMascara = (BigInt.one << 64) - BigInt.one;

  /// FNV-1a de 64 bits em [BigInt] — deliberadamente NÃO em `int` nativo.
  ///
  /// O app compila para web, onde `int` é double de 53 bits. A versão com
  /// `int` sequer compila (`dart compile js` rejeita a máscara
  /// `0xFFFFFFFFFFFFFFFF`) e, reduzida para caber em 53 bits, produziria ids
  /// DIFERENTES no web e no desktop — exatamente o defeito de identidade que
  /// este id existe para fechar, reencarnado. `BigInt` dá o mesmo resultado
  /// nas duas plataformas (conferido com `dart compile js` + node).
  ///
  /// Hash em vez da chave crua porque a chave carrega texto livre do usuário
  /// (tarefa, título): viraria chave de Hive e campo de backup de tamanho
  /// arbitrário.
  static String _fnv64(String texto) {
    var h = _fnvOffset;
    for (final unidade in texto.codeUnits) {
      h = (h ^ BigInt.from(unidade)) * _fnvPrime & _fnvMascara;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }

  /// Id estável por conteúdo: `xlsx-<tipo>-<data>-<hash>-<n>`.
  ///
  /// [partes] são os campos de IDENTIDADE da linha. Minutos, páginas,
  /// comentário, intervalo e status ficam FORA de propósito: são atributos
  /// da sessão, não a sessão. Com isso, corrigir na planilha um tempo
  /// digitado errado passa a ATUALIZAR o registro — antes criava um segundo
  /// e deixava o errado pendurado.
  ///
  /// [ocorrencias] conta linhas com a mesma chave dentro do mesmo import.
  /// Sem o contador, duas sessões idênticas no mesmo dia (dois blocos de 30
  /// min da mesma tarefa, por exemplo) colapsariam numa só. Linhas idênticas
  /// são intercambiáveis entre si, então o contador não reintroduz
  /// dependência de posição: trocá-las de lugar troca `n` entre duas linhas
  /// com o mesmo conteúdo.
  ///
  /// A data entra em claro além de entrar no hash: um id de Hive legível
  /// vale a dúzia de bytes na hora de inspecionar um backup à mão.
  static String _idDeConteudo(
    String tipo,
    DateTime data,
    List<String> partes,
    Map<String, int> ocorrencias,
  ) {
    final dia = data.toIso8601String().substring(0, 10);
    final chave = '$tipo|$dia|${partes.join('|')}';
    final n = ocorrencias[chave] = (ocorrencias[chave] ?? -1) + 1;
    return 'xlsx-$tipo-$dia-${_fnv64(chave)}-$n';
  }

  static PlanilhaImportada parse(
    Map<String, List<List<String>>> abas, {
    required List<Materia> materiasExistentes,
  }) {
    final avisos = <String>[];
    final materias = <String, Materia>{
      for (final m in materiasExistentes) _normalizar(m.nome): m,
    };
    final materiasNovas = <String, Materia>{};
    final materiasAtualizadas = <String, Materia>{};
    final topicosNovos = <String, Topico>{};
    final registros = <RegistroHora>[];
    final revisoes = <Revisao>[];

    final slotsUsados = materiasExistentes.map((m) => m.corSlot).toSet();
    var proximoSlot = 0;

    Materia materiaDe(String nome, {int? peso, int? questoes, int? minimo}) {
      final chave = _normalizar(nome);
      final original = materias[chave];
      if (original != null) {
        if (peso != null || questoes != null || minimo != null) {
          materiasAtualizadas[chave] = (materiasAtualizadas[chave] ?? original)
              .copyWith(peso: peso, questoes: questoes, minimo: minimo);
        }
        return materiasAtualizadas[chave] ?? original;
      }
      final nova = materiasNovas[chave];
      if (nova != null) {
        if (peso != null || questoes != null || minimo != null) {
          materiasNovas[chave] = nova.copyWith(
            peso: peso,
            questoes: questoes,
            minimo: minimo,
          );
        }
        return materiasNovas[chave]!;
      }
      while (slotsUsados.contains(proximoSlot % 8) && proximoSlot < 8) {
        proximoSlot++;
      }
      final criada = Materia(
        id: 'xlsx-materia-$chave',
        nome: nome.trim(),
        corSlot: proximoSlot % 8,
        peso: peso ?? 1,
        questoes: questoes,
        minimo: minimo,
        criadaEm: DateTime.now(),
      );
      proximoSlot++;
      materiasNovas[chave] = criada;
      return criada;
    }

    Topico? topicoDe(String nome, String materiaId) {
      final texto = nome.trim();
      if (texto.isEmpty) return null;
      final chave = '$materiaId-${_normalizar(texto)}';
      return topicosNovos[chave] ??= Topico(
        id: 'xlsx-topico-$chave',
        materiaId: materiaId,
        nome: texto,
      );
    }

    var achouRegistros = false;
    var achouRevisoes = false;
    var achouPesos = false;

    for (final aba in abas.entries) {
      final cabecalho = _acharCabecalho(aba.value);
      if (cabecalho == null) continue;
      final colunas = cabecalho.colunas;

      final temData = colunas.containsKey('data');
      final ehRegistro =
          temData &&
          (colunas.containsKey('horas') ||
              colunas.containsKey('minutos') ||
              colunas.containsKey('tempo'));
      final ehRevisao =
          temData &&
          (colunas.containsKey('intervalo') ||
              _normalizar(aba.key).contains('revis'));
      final ehPesos = !temData && colunas.containsKey('peso');

      if (ehRegistro && !achouRegistros) {
        achouRegistros = true;
        _lerRegistros(
          aba.key,
          aba.value,
          cabecalho,
          avisos,
          registros,
          materiaDe,
          topicoDe,
        );
      } else if (ehRevisao && !achouRevisoes) {
        achouRevisoes = true;
        _lerRevisoes(
          aba.key,
          aba.value,
          cabecalho,
          avisos,
          revisoes,
          materiaDe,
        );
      } else if (ehPesos && !achouPesos) {
        achouPesos = true;
        _lerPesos(aba.key, aba.value, cabecalho, avisos, materiaDe);
      }
    }

    if (!achouRegistros && !achouRevisoes && !achouPesos) {
      throw const FormatException(
        'Nenhuma aba com cabeçalho reconhecido. Esperado: "Data" + '
        '"Matéria" + tempo (Tempo ou Horas/Minutos) para registros; '
        '"Data" + "Matéria" + "Intervalo" para revisões; '
        '"Matéria" + "Peso" para pesos do edital.',
      );
    }

    return PlanilhaImportada(
      materiasNovas: materiasNovas.values.toList(),
      materiasAtualizadas: materiasAtualizadas.values.toList(),
      topicosNovos: topicosNovos.values.toList(),
      registros: registros,
      revisoes: revisoes,
      metaSemanalMinutos: _acharMetaSemanal(abas),
      avisos: avisos,
    );
  }

  static void _lerRegistros(
    String nomeAba,
    List<List<String>> linhas,
    _Cabecalho cabecalho,
    List<String> avisos,
    List<RegistroHora> registros,
    Materia Function(String nome, {int? peso, int? questoes, int? minimo})
    materiaDe,
    Topico? Function(String nome, String materiaId) topicoDe,
  ) {
    final c = Map<String, int>.from(cabecalho.colunas);
    var inicioDados = cabecalho.linha + 1;
    final ocorrencias = <String, int>{};

    // "Tempo" mesclado sobre subcolunas: a linha seguinte ao cabeçalho traz
    // "Horas"/"Minutos" (ou "h"/"min") sob a célula Tempo.
    final colTempo = c['tempo'];
    if (colTempo != null &&
        !c.containsKey('horas') &&
        !c.containsKey('minutos')) {
      final sub = inicioDados < linhas.length
          ? linhas[inicioDados]
          : const <String>[];
      String subEm(int i) =>
          i >= 0 && i < sub.length ? _normalizar(sub[i]) : '';
      final esquerda = subEm(colTempo);
      final direita = subEm(colTempo + 1);
      if (esquerda.startsWith('hora') || esquerda == 'h') {
        c['horas'] = colTempo;
        if (direita.startsWith('min')) c['minutos'] = colTempo + 1;
        c.remove('tempo');
        inicioDados++;
      } else if (esquerda.startsWith('min')) {
        c['minutos'] = colTempo;
        c.remove('tempo');
        inicioDados++;
      }
    }

    for (var i = inicioDados; i < linhas.length; i++) {
      final linha = linhas[i];
      if (linha.every((celula) => celula.trim().isEmpty)) continue;

      String celula(String coluna) {
        final indice = c[coluna];
        return (indice == null || indice >= linha.length)
            ? ''
            : linha[indice].trim();
      }

      final data = _parseData(celula('data'));
      if (data == null) {
        avisos.add('$nomeAba, linha ${i + 1}: data inválida — pulada.');
        continue;
      }
      final nomeMateria = celula('materia');
      if (nomeMateria.isEmpty) {
        avisos.add('$nomeAba, linha ${i + 1}: sem matéria — pulada.');
        continue;
      }

      final int totalMinutos;
      if (c.containsKey('tempo')) {
        totalMinutos = _parseTempoMinutos(celula('tempo')) ?? 0;
      } else {
        final horas = _parseNumero(celula('horas')) ?? 0;
        final minutos = _parseNumero(celula('minutos')) ?? 0;
        totalMinutos = (horas * 60 + minutos).round();
      }
      if (totalMinutos <= 0) {
        avisos.add('$nomeAba, linha ${i + 1}: sem tempo de estudo — pulada.');
        continue;
      }

      final materia = materiaDe(nomeMateria);
      final topico = topicoDe(celula('topico'), materia.id);
      final tarefa = [
        celula('tarefa'),
        celula('aula'),
      ].where((t) => t.isNotEmpty).join(' · ');

      registros.add(
        RegistroHora(
          id: _idDeConteudo('registro', data, [
            materia.id,
            topico?.id ?? '',
            tarefa,
          ], ocorrencias),
          data: data,
          materiaId: materia.id,
          topicoId: topico?.id,
          tarefa: tarefa,
          minutos: totalMinutos,
          paginaInicial: _parseNumero(celula('pagina inicial'))?.round(),
          paginaFinal: _parseNumero(celula('pagina final'))?.round(),
          paginasLidasManual: _parseNumero(celula('paginas lidas'))?.round(),
          comentario: celula('comentario').isEmpty
              ? null
              : celula('comentario'),
        ),
      );
    }
  }

  static void _lerRevisoes(
    String nomeAba,
    List<List<String>> linhas,
    _Cabecalho cabecalho,
    List<String> avisos,
    List<Revisao> revisoes,
    Materia Function(String nome, {int? peso, int? questoes, int? minimo})
    materiaDe,
  ) {
    final c = cabecalho.colunas;
    final ocorrencias = <String, int>{};
    for (var i = cabecalho.linha + 1; i < linhas.length; i++) {
      final linha = linhas[i];
      if (linha.every((celula) => celula.trim().isEmpty)) continue;

      String celula(String coluna) {
        final indice = c[coluna];
        return (indice == null || indice >= linha.length)
            ? ''
            : linha[indice].trim();
      }

      final data = _parseData(celula('data'));
      final nomeMateria = celula('materia');
      if (data == null || nomeMateria.isEmpty) {
        avisos.add(
          '$nomeAba, linha ${i + 1}: revisão sem data ou matéria — pulada.',
        );
        continue;
      }
      final titulo = celula('titulo').isEmpty
          ? 'Revisão de $nomeMateria'
          : celula('titulo');
      final status = _normalizar(celula('status'));
      final feita =
          status == 'feita' ||
          status == 'concluida' ||
          status == 'ok' ||
          status == 'sim';

      final materiaId = materiaDe(nomeMateria).id;
      revisoes.add(
        Revisao(
          id: _idDeConteudo('revisao', data, [materiaId, titulo], ocorrencias),
          materiaId: materiaId,
          titulo: titulo,
          dataAgendada: data,
          intervaloDias: _parseNumero(celula('intervalo'))?.round() ?? 0,
          feita: feita,
          dataConclusao: feita ? data : null,
        ),
      );
    }
  }

  /// Aba de pesos do edital (Sefaz): Matéria, Número questões, Peso, Mínimo.
  static void _lerPesos(
    String nomeAba,
    List<List<String>> linhas,
    _Cabecalho cabecalho,
    List<String> avisos,
    Materia Function(String nome, {int? peso, int? questoes, int? minimo})
    materiaDe,
  ) {
    final c = cabecalho.colunas;
    for (var i = cabecalho.linha + 1; i < linhas.length; i++) {
      final linha = linhas[i];
      if (linha.every((celula) => celula.trim().isEmpty)) continue;

      String celula(String coluna) {
        final indice = c[coluna];
        return (indice == null || indice >= linha.length)
            ? ''
            : linha[indice].trim();
      }

      final nome = celula('materia');
      if (nome.isEmpty) continue;
      final peso = _parseNumero(celula('peso'))?.round();
      if (peso == null) {
        avisos.add('$nomeAba, linha ${i + 1}: peso inválido — pulada.');
        continue;
      }
      materiaDe(
        nome,
        peso: peso < 1 ? 1 : peso,
        questoes: _parseNumero(celula('questoes'))?.round(),
        minimo: _parseNumero(celula('minimo'))?.round(),
      );
    }
  }

  /// Varre todas as abas atrás do rótulo "Horas planejadas para a semana";
  /// o valor é a primeira célula numérica à direita (ou logo abaixo).
  static int? _acharMetaSemanal(Map<String, List<List<String>>> abas) {
    for (final linhas in abas.values) {
      for (var i = 0; i < linhas.length; i++) {
        for (var j = 0; j < linhas[i].length; j++) {
          final texto = _normalizar(linhas[i][j]);
          if (!texto.contains('planejad') || !texto.contains('semana')) {
            continue;
          }
          double? valor;
          for (var k = j + 1; k < linhas[i].length && valor == null; k++) {
            valor = _parseNumero(linhas[i][k]);
          }
          if (valor == null &&
              i + 1 < linhas.length &&
              j < linhas[i + 1].length) {
            valor = _parseNumero(linhas[i + 1][j]);
          }
          if (valor != null && valor > 0 && valor <= 24 * 7) {
            return (valor * 60).round();
          }
        }
      }
    }
    return null;
  }

  /// Procura nas 10 primeiras linhas não vazias um cabeçalho com "Matéria"
  /// acompanhada de "Data" (registros/revisões) ou "Peso" (edital).
  static _Cabecalho? _acharCabecalho(List<List<String>> linhas) {
    final limite = linhas.length < 10 ? linhas.length : 10;
    for (var i = 0; i < limite; i++) {
      final colunas = <String, int>{};
      for (var j = 0; j < linhas[i].length; j++) {
        final chave = _chaveColuna(_normalizar(linhas[i][j]));
        if (chave != null) colunas.putIfAbsent(chave, () => j);
      }
      if (colunas.containsKey('materia') &&
          (colunas.containsKey('data') || colunas.containsKey('peso'))) {
        return _Cabecalho(linha: i, colunas: colunas);
      }
    }
    return null;
  }

  /// Cabeçalho da planilha -> chave canônica de coluna.
  static String? _chaveColuna(String texto) {
    if (texto.isEmpty) return null;
    if (texto == 'data' || texto == 'dia') return 'data';
    if (texto.startsWith('materia')) return 'materia';
    if (texto.startsWith('topico')) return 'topico';
    if (texto.startsWith('tarefa')) return 'tarefa';
    if (texto.startsWith('aula')) return 'aula';
    if (texto.contains('inicial')) return 'pagina inicial';
    if (texto.contains('final')) return 'pagina final';
    if (texto.contains('lida')) return 'paginas lidas';
    // "Páginas/hora" é derivada; não pode cair em 'horas'.
    if (texto.contains('/hora') || texto.contains('por hora')) return null;
    if (texto == 'tempo' || texto.startsWith('tempo ')) return 'tempo';
    if (texto.startsWith('hora')) return 'horas';
    if (texto.startsWith('min') && !texto.startsWith('minimo')) {
      return 'minutos';
    }
    if (texto.startsWith('coment')) return 'comentario';
    if (texto.startsWith('peso')) return 'peso';
    if (texto.contains('quest')) return 'questoes';
    if (texto.startsWith('minimo')) return 'minimo';
    if (texto.startsWith('intervalo') || texto.contains('dias')) {
      return 'intervalo';
    }
    if (texto.startsWith('status') || texto.startsWith('feita')) {
      return 'status';
    }
    if (texto.contains('revisar') ||
        texto.startsWith('titulo') ||
        texto.startsWith('conteudo') ||
        texto.startsWith('assunto')) {
      return 'titulo';
    }
    return null;
  }

  static const _acentos = 'áàâãäéèêëíìîïóòôõöúùûüç';
  static const _semAcento = 'aaaaaeeeeiiiiooooouuuuc';

  static String _normalizar(String texto) {
    final minusculo = texto.toLowerCase().trim();
    final buffer = StringBuffer();
    for (final char in minusculo.split('')) {
      final i = _acentos.indexOf(char);
      buffer.write(i >= 0 ? _semAcento[i] : char);
    }
    return buffer.toString();
  }

  /// Aceita serial do Excel (sistema 1900), dd/mm/aaaa e ISO-8601.
  static DateTime? _parseData(String texto) {
    final s = texto.trim();
    if (s.isEmpty) return null;
    final serial = double.tryParse(s.replaceAll(',', '.'));
    if (serial != null) {
      if (serial < 20000 || serial > 80000) return null;
      // Epoch 1899-12-30 absorve o bug do ano bissexto de 1900 do Excel.
      return DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
    }
    final br = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2,4})$').firstMatch(s);
    if (br != null) {
      var ano = int.parse(br.group(3)!);
      if (ano < 100) ano += 2000;
      final data = DateTime(
        ano,
        int.parse(br.group(2)!),
        int.parse(br.group(1)!),
      );
      return (data.year < 2000 || data.year > 2100) ? null : data;
    }
    final iso = DateTime.tryParse(s);
    if (iso == null || iso.year < 2000 || iso.year > 2100) return null;
    return DateTime(iso.year, iso.month, iso.day);
  }

  /// Coluna "Tempo" única. Convenções, na ordem:
  /// - "1:30" / "01:30:00" -> relógio (h:mm[:ss]);
  /// - número < 1 -> fração de dia (célula de hora do Excel: 0,0625 = 1h30);
  /// - 1 a 24 -> horas decimais ("1,5" = 90min);
  /// - > 24 -> minutos.
  static int? _parseTempoMinutos(String texto) {
    final s = texto.trim();
    if (s.isEmpty) return null;
    if (s.contains(':')) {
      final partes = s.split(':');
      final h = int.tryParse(partes[0]);
      final m = partes.length > 1 ? int.tryParse(partes[1]) : 0;
      if (h == null || m == null) return null;
      return h * 60 + m;
    }
    final numero = _parseNumero(s);
    if (numero == null || numero <= 0) return null;
    if (numero < 1) return (numero * 24 * 60).round();
    if (numero <= 24) return (numero * 60).round();
    return numero.round();
  }

  /// Aceita "1.5", "1,5" e "1.234,5" (pt-BR com milhar).
  static double? _parseNumero(String texto) {
    final s = texto.trim();
    if (s.isEmpty) return null;
    if (s.contains(',')) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.'));
    }
    return double.tryParse(s);
  }
}

class _Cabecalho {
  final int linha;
  final Map<String, int> colunas;

  const _Cabecalho({required this.linha, required this.colunas});
}
