import '../data/models/aula.dart';
import '../data/models/materia.dart';
import '../data/models/questao_errada.dart';
import '../data/models/resumo.dart';
import '../data/models/simulado.dart';
import '../data/models/topico.dart';

/// Tipo do item encontrado pela busca global — usado pela tela pra agrupar
/// os resultados e decidir pra onde navegar (cada tipo abre uma tela).
enum TipoResultadoBusca { materia, topico, questao, resumo, aula, simulado }

/// Um item encontrado, já com título/subtítulo prontos pra exibição e o
/// score de relevância que ordena a lista (maior = mais relevante).
class ResultadoBusca {
  final TipoResultadoBusca tipo;
  final String id;
  final String titulo;
  final String subtitulo;
  final double score;

  /// Matéria dona do item. Só preenchido para tópico e aula: nenhuma das
  /// duas tem tela própria de detalhe — a navegação abre TopicosScreen /
  /// AulasScreen da matéria (mesmo destino que MateriasScreen usa pro
  /// próprio card), então a tela precisa desse id pra buscar a Materia
  /// completa antes de navegar.
  final String? materiaId;

  const ResultadoBusca({
    required this.tipo,
    required this.id,
    required this.titulo,
    required this.subtitulo,
    required this.score,
    this.materiaId,
  });
}

/// Busca global sobre as coleções do app.
///
/// Domínio puro (sem Hive, sem Riverpod, sem BuildContext): recebe as listas
/// já carregadas pela tela e devolve o resultado ranqueado. Com um edital de
/// 200+ tópicos espalhados em 6 telas diferentes, esta é a única forma de
/// achar um item sem navegar a árvore inteira.
class BuscaService {
  /// Abaixo disto o termo não distingue nada (a base inteira "bateria" e a
  /// tela viraria uma lista do app inteiro) — exposto como público porque a
  /// tela usa a MESMA constante pra decidir quando mostrar a dica em vez da
  /// lista de resultados.
  static const tamanhoMinimo = 2;

  /// Teto defensivo: um texto de milhares de caracteres colado por engano no
  /// campo (ou vazado de outro lugar) faria cada `contains()` abaixo
  /// trabalhar O(termo × item) por item da base à toa — cortar aqui é mais
  /// barato que otimizar o casamento de string, e nenhuma busca legítima
  /// digitada por uma pessoa precisa de mais que isso.
  static const _tamanhoMaximoTermo = 300;

  // Mesma tabela de tradução de lib/data/models/bancas.dart (Bancas.
  // _semAcento). O método de origem é privado à classe — não dá pra
  // importar —, e é só uma tabela pequena, então duplicar aqui custa menos
  // do que promover um helper compartilhado entre dois domínios sem relação
  // (bancas de prova × busca global) só por causa desta função.
  static const _comAcento = 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç';
  static const _semAcentoMapa = 'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc';

  static final RegExp _naoAlfanumerico = RegExp(r'[^a-z0-9]+');
  static final RegExp _espacos = RegExp(r'\s+');

  static String _semAcento(String texto) {
    final buffer = StringBuffer();
    for (final rune in texto.runes) {
      final char = String.fromCharCode(rune);
      final i = _comAcento.indexOf(char);
      buffer.write(i >= 0 ? _semAcentoMapa[i] : char);
    }
    return buffer.toString();
  }

  /// minúsculas + sem acento + espaços colapsados, aplicado no MESMO
  /// tratamento pro termo buscado e pro texto de cada item — senão
  /// "orcamentaria" nunca bateria com "Orçamentária".
  static String _normalizar(String texto) {
    final semAcento = _semAcento(texto).toLowerCase().trim();
    return semAcento.replaceAll(_espacos, ' ');
  }

  /// Tokens "palavra" do texto normalizado, usados só pra achar match de
  /// palavra inteira. O padrão de split é FIXO (nunca compilado a partir do
  /// termo digitado), então entrada tipo ".*" no termo buscado não vira
  /// regex nenhuma — é sempre comparação de string literal.
  static List<String> _palavras(String textoNormalizado) => textoNormalizado
      .split(_naoAlfanumerico)
      .where((p) => p.isNotEmpty)
      .toList();

  /// Camada de relevância do match: 0 é a melhor (prefixo do título) e 3 a
  /// pior ainda válida (substring no corpo); null quando o termo não aparece
  /// em lugar nenhum. Ordem pedida: prefixo do título > palavra inteira no
  /// título > substring no título > substring no corpo.
  static int? _nivel(String termoNorm, String tituloNorm, String corpoNorm) {
    if (tituloNorm.startsWith(termoNorm)) return 0;
    if (_palavras(tituloNorm).contains(termoNorm)) return 1;
    if (tituloNorm.contains(termoNorm)) return 2;
    if (corpoNorm.contains(termoNorm)) return 3;
    return null;
  }

  static List<ResultadoBusca> buscar(
    String termo, {
    List<Materia> materias = const [],
    List<Topico> topicos = const [],
    List<QuestaoErrada> questoes = const [],
    List<Resumo> resumos = const [],
    List<Aula> aulas = const [],
    List<Simulado> simulados = const [],
  }) {
    // Contrato duro: a busca NUNCA lança. Uma tela que quebra a cada tecla
    // digitada é bem pior que uma busca que só não encontra nada — cobre
    // qualquer degenerado de unicode que escape da normalização acima.
    try {
      final bruto = termo.trim();
      if (bruto.length < tamanhoMinimo) return const [];
      final limitado = bruto.length > _tamanhoMaximoTermo
          ? bruto.substring(0, _tamanhoMaximoTermo)
          : bruto;
      final termoNorm = _normalizar(limitado);
      if (termoNorm.length < tamanhoMinimo) return const [];

      final materiasPorId = {for (final m in materias) m.id: m};
      final resultados = <ResultadoBusca>[];

      void tentar({
        required TipoResultadoBusca tipo,
        required String id,
        required String titulo,
        required String subtitulo,
        required String corpo,
        String? materiaId,
      }) {
        final nivel = _nivel(
          termoNorm,
          _normalizar(titulo),
          _normalizar(corpo),
        );
        if (nivel == null) return;
        resultados.add(
          ResultadoBusca(
            tipo: tipo,
            id: id,
            titulo: titulo,
            subtitulo: subtitulo,
            // Nível 0..3 vira score 3..0 (maior = mais relevante): quem
            // consome só compara `>`, sem precisar saber a escala interna.
            score: (3 - nivel).toDouble(),
            materiaId: materiaId,
          ),
        );
      }

      for (final m in materias) {
        tentar(
          tipo: TipoResultadoBusca.materia,
          id: m.id,
          titulo: m.nome,
          subtitulo: 'Matéria',
          corpo: m.notas,
        );
      }

      for (final t in topicos) {
        final materia = materiasPorId[t.materiaId];
        tentar(
          tipo: TipoResultadoBusca.topico,
          id: t.id,
          titulo: t.nome,
          subtitulo: materia == null ? 'Tópico' : 'Tópico · ${materia.nome}',
          corpo: t.notas,
          materiaId: t.materiaId,
        );
      }

      for (final q in questoes) {
        final materia = materiasPorId[q.materiaId];
        tentar(
          tipo: TipoResultadoBusca.questao,
          id: q.id,
          titulo: q.enunciado,
          subtitulo: [
            'Caderno de erros',
            if (materia != null) materia.nome,
            if (q.banca != null) q.banca!,
          ].join(' · '),
          corpo: q.comentario,
          materiaId: q.materiaId,
        );
      }

      for (final r in resumos) {
        // Página em branco (placeholder que a tela de Resumos gera pra TODA
        // matéria sem página própria — ver paginasResumo em
        // features/resumos/resumos_screen.dart) tem o MESMO nome da matéria
        // e nada de conteúdo: bater aqui só duplicaria o resultado de
        // TipoResultadoBusca.materia com um card idêntico e vazio por baixo.
        // Só entra na busca a página que já foi escrita.
        if (r.texto.trim().isEmpty) continue;
        tentar(
          tipo: TipoResultadoBusca.resumo,
          id: r.sigla,
          titulo: r.nome,
          subtitulo: 'Resumo · #${r.sigla}',
          corpo: r.texto,
        );
      }

      for (final a in aulas) {
        final materia = materiasPorId[a.materiaId];
        tentar(
          tipo: TipoResultadoBusca.aula,
          id: a.id,
          titulo: a.nome,
          subtitulo: materia == null ? 'Aula' : 'Aula · ${materia.nome}',
          corpo: '',
          materiaId: a.materiaId,
        );
      }

      for (final s in simulados) {
        tentar(
          tipo: TipoResultadoBusca.simulado,
          id: s.id,
          titulo: s.nome,
          subtitulo: [
            s.tipo == TipoSimulado.prova ? 'Prova' : 'Simulado',
            if (s.cargo.isNotEmpty) s.cargo,
          ].join(' · '),
          corpo: [s.cargo, s.comentario, s.banca ?? ''].join(' '),
        );
      }

      // Ranking: score desc; empate por nome (mesma convenção dos
      // repositórios — MateriasRepositorio.comparar etc. — minúsculas, nunca
      // por ordem de inserção das seções acima).
      resultados.sort((a, b) {
        final porScore = b.score.compareTo(a.score);
        if (porScore != 0) return porScore;
        return a.titulo.toLowerCase().compareTo(b.titulo.toLowerCase());
      });
      return resultados;
    } catch (_) {
      // Qualquer falha inesperada (unicode degenerado etc.) — busca que não
      // acha nada nunca deve virar tela de erro.
      return const [];
    }
  }
}
