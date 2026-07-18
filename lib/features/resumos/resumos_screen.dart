import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/haptica.dart';
import '../../core/widgets/notas_editor.dart';
import '../../data/catalogo/catalogo_materias.dart';
import '../../data/models/materia.dart';
import '../../data/models/resumo.dart';
import '../../data/repositories/repositorios.dart';

String _normalizar(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const para = 'aaaaaeeeeiiiiooooouuuuc';
  final baixo = s.toLowerCase().trim();
  final sb = StringBuffer();
  for (final rune in baixo.runes) {
    final ch = String.fromCharCode(rune);
    final i = de.indexOf(ch);
    sb.write(i >= 0 ? para[i] : ch);
  }
  return sb.toString();
}

/// Páginas visíveis: catálogo (seed) + matérias do usuário que não casam
/// com nenhuma página existente — estas ganham sigla derivada (com sufixo
/// numérico em colisão) e só são gravadas quando o usuário salva texto.
List<Resumo> paginasResumo(List<Resumo> resumos, List<Materia> materias) {
  final nomesExistentes = resumos.map((r) => _normalizar(r.nome)).toSet();
  final siglasUsadas = resumos.map((r) => r.sigla).toSet();
  final extras = <Resumo>[];
  for (final m in materias) {
    if (nomesExistentes.contains(_normalizar(m.nome))) continue;
    var sigla = siglaPara(m.nome);
    var n = 2;
    while (siglasUsadas.contains(sigla)) {
      sigla = '${siglaPara(m.nome)}$n';
      n++;
    }
    siglasUsadas.add(sigla);
    extras.add(Resumo(sigla: sigla, nome: m.nome));
  }
  return [...resumos, ...extras]
    ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
}

/// Siglas citadas no texto via #TAG que existem como página — as
/// "ligações" estilo Obsidian entre resumos.
List<String> ligacoesNoTexto(String texto, Set<String> siglasConhecidas) {
  final vistas = <String>{};
  for (final m in RegExp(r'#([A-Za-z][A-Za-z0-9]{1,5})').allMatches(texto)) {
    final sigla = m.group(1)!.toUpperCase();
    if (siglasConhecidas.contains(sigla)) vistas.add(sigla);
  }
  return vistas.toList()..sort();
}

/// Resumos por matéria: uma tag #sigla por matéria (tooltip = nome
/// completo), cada tag abre a página única consolidada com data de edição.
class ResumosScreen extends ConsumerWidget {
  const ResumosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paginas = paginasResumo(
      ref.watch(resumosProvider),
      ref.watch(materiasProvider),
    );
    final comTexto = paginas.where((p) => p.texto.trim().isNotEmpty).toList()
      ..sort(
        (a, b) => (b.atualizadoEm ?? DateTime(0)).compareTo(
          a.atualizadoEm ?? DateTime(0),
        ),
      );
    final vazias = paginas.where((p) => p.texto.trim().isEmpty).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Resumos por matéria')),
      body: ConteudoCentral(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const Text(
              'Uma página por matéria, estilo Obsidian: toque na tag para '
              'abrir; passe o mouse para ver o nome completo. Cite outra '
              'matéria no texto com #SIGLA para criar ligação.',
              style: TextStyle(color: VizColors.muted, fontSize: 12),
            ),
            if (comTexto.isNotEmpty) ...[
              const SizedBox(height: 14),
              const _RotuloSecao('Minhas anotações'),
              _GradeDeTags(paginas: comTexto),
            ],
            const SizedBox(height: 14),
            const _RotuloSecao('Todas as matérias'),
            _GradeDeTags(paginas: vazias),
          ],
        ),
      ),
    );
  }
}

class _RotuloSecao extends StatelessWidget {
  final String texto;

  const _RotuloSecao(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        texto,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: VizColors.inkSecondary),
      ),
    );
  }
}

class _GradeDeTags extends StatelessWidget {
  final List<Resumo> paginas;

  const _GradeDeTags({required this.paginas});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [for (final p in paginas) TagResumo(pagina: p)],
    );
  }
}

/// A tag #SIGLA: tooltip com o nome completo, cor viva quando a página tem
/// conteúdo, apagada quando ainda está em branco.
class TagResumo extends StatelessWidget {
  final Resumo pagina;

  const TagResumo({super.key, required this.pagina});

  @override
  Widget build(BuildContext context) {
    final temTexto = pagina.texto.trim().isNotEmpty;
    final tinta = temTexto ? LuminaColors.safiraClara : VizColors.muted;

    return Tooltip(
      message: pagina.nome,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: temTexto ? tinta.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            Haptica.selecao();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ResumoPage(sigla: pagina.sigla, paginaInicial: pagina),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: temTexto
                    ? tinta.withValues(alpha: 0.4)
                    : VizColors.gridline,
              ),
            ),
            child: Text(
              '#${pagina.sigla}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: temTexto ? FontWeight.w600 : FontWeight.w400,
                color: temTexto ? VizColors.inkPrimary : VizColors.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Página única da matéria: nome no topo, tag, data da última edição,
/// editor markdown-lite e ligações #SIGLA citadas no texto.
class ResumoPage extends ConsumerStatefulWidget {
  final String sigla;

  /// Página ainda não gravada (matéria do usuário fora do catálogo).
  final Resumo paginaInicial;

  const ResumoPage({
    super.key,
    required this.sigla,
    required this.paginaInicial,
  });

  @override
  ConsumerState<ResumoPage> createState() => _ResumoPageState();
}

class _ResumoPageState extends ConsumerState<ResumoPage> {
  late final TextEditingController _texto = TextEditingController(
    text: widget.paginaInicial.texto,
  );

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resumos = ref.watch(resumosProvider);
    final pagina =
        resumos.where((r) => r.sigla == widget.sigla).firstOrNull ??
        widget.paginaInicial;
    final siglas = {
      ...resumos.map((r) => r.sigla),
      ...paginasResumo(
        resumos,
        ref.watch(materiasProvider),
      ).map((r) => r.sigla),
    };
    final ligacoes = ligacoesNoTexto(_texto.text, siglas)..remove(pagina.sigla);

    return Scaffold(
      appBar: AppBar(title: Text(pagina.nome)),
      body: ConteudoCentral(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(
              children: [
                TagResumo(pagina: pagina),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    pagina.atualizadoEm == null
                        ? 'Nunca editado'
                        : 'Editado em ${formatarData(pagina.atualizadoEm!)} '
                              'às ${pagina.atualizadoEm!.hour.toString().padLeft(2, '0')}:'
                              '${pagina.atualizadoEm!.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      color: VizColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            NotasEditor(
              controller: _texto,
              rotulo: 'Resumo consolidado',
              linhas: 16,
            ),
            if (ligacoes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Ligações',
                style: TextStyle(color: VizColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final sigla in ligacoes) _LigacaoChip(sigla: sigla),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref
                    .read(resumosProvider.notifier)
                    .salvarTexto(pagina, _texto.text);
                Haptica.leve();
                if (!mounted) return;
                setState(() {});
                messenger.showSnackBar(
                  const SnackBar(content: Text('Resumo salvo')),
                );
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salvar resumo'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ligação para outra página citada no texto via #SIGLA.
class _LigacaoChip extends ConsumerWidget {
  final String sigla;

  const _LigacaoChip({required this.sigla});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paginas = paginasResumo(
      ref.watch(resumosProvider),
      ref.watch(materiasProvider),
    );
    final destino = paginas.where((p) => p.sigla == sigla).firstOrNull;
    if (destino == null) return const SizedBox.shrink();
    return TagResumo(pagina: destino);
  }
}
