import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/estado_vazio.dart';
import '../../data/models/materia.dart';
import '../../data/models/resumo.dart';
import '../../data/repositories/ambiente_filtros.dart';
import '../../data/repositories/repositorios.dart';
import '../../domain/busca_service.dart';
import '../aulas/aulas_screen.dart';
import '../caderno/caderno_providers.dart';
import '../caderno/caderno_screen.dart';
import '../materias/topicos_screen.dart';
import '../resumos/resumos_screen.dart';
import '../simulados/simulados_screen.dart';

/// Busca global do app: acha matéria, tópico, questão do caderno de erros,
/// resumo, aula ou simulado por nome, sem precisar navegar a árvore inteira
/// do edital (200+ tópicos espalhados em 6 telas diferentes). O ranking e a
/// normalização de acento vivem em [BuscaService] — domínio puro, testado à
/// parte; esta tela só liga o campo de texto às listas dos providers e
/// decide a navegação por tipo de resultado.
class BuscaScreen extends ConsumerStatefulWidget {
  const BuscaScreen({super.key});

  @override
  ConsumerState<BuscaScreen> createState() => _BuscaScreenState();
}

class _BuscaScreenState extends ConsumerState<BuscaScreen> {
  final _controller = TextEditingController();
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    // O resultado depende só do texto do campo — nada mais no app precisa
    // reagir à busca — então um setState local é mais simples que subir o
    // termo digitado pra um provider.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _foco.dispose();
    super.dispose();
  }

  void _abrir(Widget tela) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
  }

  void _navegar(ResultadoBusca resultado) {
    final tela = _telaPara(
      resultado,
      ref.read(materiasProvider),
      ref.read(resumosProvider),
    );
    if (tela != null) _abrir(tela);
  }

  @override
  Widget build(BuildContext context) {
    final termo = _controller.text;
    final ativo = ref.watch(ambienteAtivoProvider);

    // Mesmo escopo por ambiente do resto do app (materiasDoAmbienteProvider
    // etc. em data/repositories/ambiente_filtros.dart): dentro de um
    // concurso específico, resultado de OUTRO ambiente só atrapalharia.
    // Tópico e aula não têm ambienteId próprio — herdam o escopo pela
    // matéria dona, igual a registrosDoAmbienteProvider/
    // revisoesDoAmbienteProvider. Resumo segue ResumosScreen, que nunca
    // filtra por ambiente (a página é por matéria, não por concurso).
    final materias = ref.watch(materiasDoAmbienteProvider);
    final idsMaterias = materias.map((m) => m.id).toSet();

    final topicos = ativo == null
        ? ref.watch(topicosProvider)
        : ref
              .watch(topicosProvider)
              .where((t) => idsMaterias.contains(t.materiaId))
              .toList();

    final aulas = ativo == null
        ? ref.watch(aulasProvider)
        : ref
              .watch(aulasProvider)
              .where((a) => idsMaterias.contains(a.materiaId))
              .toList();

    final simulados = ativo == null
        ? ref.watch(simuladosProvider)
        : ref
              .watch(simuladosProvider)
              .where((s) => s.ambienteId == ativo.id)
              .toList();

    final resumos = paginasResumo(
      ref.watch(resumosProvider),
      ref.watch(materiasProvider),
    );

    final questoes = ref.watch(questoesErradasDoAmbienteProvider);

    final resultados = BuscaService.buscar(
      termo,
      materias: materias,
      topicos: topicos,
      questoes: questoes,
      resumos: resumos,
      aulas: aulas,
      simulados: simulados,
    );

    final agrupados = <TipoResultadoBusca, List<ResultadoBusca>>{};
    for (final r in resultados) {
      agrupados.putIfAbsent(r.tipo, () => []).add(r);
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _foco,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: const TextStyle(color: VizColors.inkPrimary, fontSize: 16),
          decoration: const InputDecoration(
            border: InputBorder.none,
            hintText: 'Buscar matérias, tópicos, questões...',
            hintStyle: TextStyle(color: VizColors.muted, fontSize: 16),
          ),
        ),
        actions: [
          if (termo.isNotEmpty)
            IconButton(
              tooltip: 'Limpar busca',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                _foco.requestFocus();
              },
            ),
        ],
      ),
      body: ConteudoCentral(
        child: _Corpo(
          termo: termo,
          agrupados: agrupados,
          onTap: _navegar,
        ),
      ),
    );
  }
}

/// Decide a tela de destino de cada tipo de resultado. Tópico e aula não têm
/// tela própria de detalhe: abrem a tela da matéria dona (mesmo destino que
/// MateriasScreen usa pro próprio card). Questão e simulado abrem a lista
/// (caderno/simulados) — nenhuma das duas telas aceita abrir direto num item
/// específico hoje. `null` quando a matéria referenciada já não existe mais
/// (excluída entre a busca ter rodado e o toque no resultado).
Widget? _telaPara(
  ResultadoBusca resultado,
  List<Materia> materias,
  List<Resumo> resumos,
) {
  Materia? materiaPorId(String? id) =>
      id == null ? null : materias.where((m) => m.id == id).firstOrNull;

  switch (resultado.tipo) {
    case TipoResultadoBusca.materia:
      final materia = materiaPorId(resultado.id);
      return materia == null ? null : TopicosScreen(materia: materia);
    case TipoResultadoBusca.topico:
      final materia = materiaPorId(resultado.materiaId);
      return materia == null ? null : TopicosScreen(materia: materia);
    case TipoResultadoBusca.aula:
      final materia = materiaPorId(resultado.materiaId);
      return materia == null ? null : AulasScreen(materia: materia);
    case TipoResultadoBusca.questao:
      return const CadernoScreen();
    case TipoResultadoBusca.simulado:
      return const SimuladosScreen();
    case TipoResultadoBusca.resumo:
      final pagina =
          resumos.where((p) => p.sigla == resultado.id).firstOrNull ??
          Resumo(sigla: resultado.id, nome: resultado.titulo);
      return ResumoPage(sigla: resultado.id, paginaInicial: pagina);
  }
}

class _Corpo extends StatelessWidget {
  final String termo;
  final Map<TipoResultadoBusca, List<ResultadoBusca>> agrupados;
  final ValueChanged<ResultadoBusca> onTap;

  const _Corpo({
    required this.termo,
    required this.agrupados,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (termo.trim().length < BuscaService.tamanhoMinimo) {
      return const EstadoVazio(
        icone: Icons.search,
        titulo: 'Busque em todo o app',
        descricao:
            'Digite ao menos 2 letras para achar matérias, tópicos do '
            'edital, questões do caderno de erros, resumos, aulas e '
            'simulados — tudo num só lugar.',
      );
    }
    if (agrupados.isEmpty) {
      return EstadoVazio(
        icone: Icons.search_off,
        titulo: 'Nada encontrado',
        descricao: 'Nenhum resultado para "${termo.trim()}".',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final tipo in TipoResultadoBusca.values)
          if (agrupados[tipo] != null) ...[
            _RotuloGrupo(tipo: tipo, quantidade: agrupados[tipo]!.length),
            for (final r in agrupados[tipo]!)
              _LinhaResultado(resultado: r, onTap: () => onTap(r)),
            const SizedBox(height: Spacing.sm),
          ],
      ],
    );
  }
}

class _RotuloGrupo extends StatelessWidget {
  final TipoResultadoBusca tipo;
  final int quantidade;

  const _RotuloGrupo({required this.tipo, required this.quantidade});

  String get _rotulo => switch (tipo) {
    TipoResultadoBusca.materia => 'Matérias',
    TipoResultadoBusca.topico => 'Tópicos',
    TipoResultadoBusca.questao => 'Caderno de erros',
    TipoResultadoBusca.resumo => 'Resumos',
    TipoResultadoBusca.aula => 'Aulas',
    TipoResultadoBusca.simulado => 'Simulados',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Spacing.md, 4, Spacing.xs),
      child: Text(
        '$_rotulo ($quantidade)'.toUpperCase(),
        style: LuminaText.rotuloUppercase,
      ),
    );
  }
}

class _LinhaResultado extends StatelessWidget {
  final ResultadoBusca resultado;
  final VoidCallback onTap;

  const _LinhaResultado({required this.resultado, required this.onTap});

  IconData get _icone => switch (resultado.tipo) {
    TipoResultadoBusca.materia => Icons.menu_book_outlined,
    TipoResultadoBusca.topico => Icons.account_tree_outlined,
    TipoResultadoBusca.questao => Icons.quiz_outlined,
    TipoResultadoBusca.resumo => Icons.tag,
    TipoResultadoBusca.aula => Icons.school_outlined,
    TipoResultadoBusca.simulado => Icons.fact_check_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: Spacing.xs),
      child: ListTile(
        leading: Icon(_icone, color: LuminaColors.safiraClara),
        title: Text(
          resultado.titulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          resultado.subtitulo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: VizColors.muted, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: VizColors.muted),
        onTap: onTap,
      ),
    );
  }
}
