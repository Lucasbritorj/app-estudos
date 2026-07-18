import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/notas_ricas.dart';

/// Renderiza notas com a formatação leve (parseNotas).
class NotasRicasView extends StatelessWidget {
  final String texto;

  const NotasRicasView({super.key, required this.texto});

  @override
  Widget build(BuildContext context) {
    final linhas = parseNotas(texto);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final linha in linhas)
          Padding(
            padding: EdgeInsets.only(left: linha.bullet ? 8 : 0, bottom: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  if (linha.bullet)
                    const TextSpan(
                      text: '•  ',
                      style: TextStyle(color: VizColors.muted),
                    ),
                  for (final s in linha.segmentos)
                    TextSpan(
                      text: s.texto,
                      style: TextStyle(
                        fontWeight: s.negrito
                            ? FontWeight.w700
                            : FontWeight.w400,
                        backgroundColor: s.destaque
                            ? const Color(0x33FAB219)
                            : null,
                        color: s.destaque
                            ? VizColors.inkPrimary
                            : VizColors.inkSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Editor de notas com toolbar (negrito, destaque, lista) e pré-visualização.
/// Grava texto puro com marcadores **/**, ==/== e "- " — nada binário.
class NotasEditor extends StatefulWidget {
  final TextEditingController controller;
  final String rotulo;

  /// Altura do campo em linhas (páginas de resumo usam área maior).
  final int linhas;

  const NotasEditor({
    super.key,
    required this.controller,
    this.rotulo = 'Notas',
    this.linhas = 4,
  });

  @override
  State<NotasEditor> createState() => _NotasEditorState();
}

class _NotasEditorState extends State<NotasEditor> {
  var _preview = false;

  /// Envolve a seleção com [marcador]; sem seleção, insere par vazio e
  /// deixa o cursor no meio.
  void _envolver(String marcador) {
    final c = widget.controller;
    final sel = c.selection;
    final texto = c.text;
    if (!sel.isValid) {
      c.text = '$texto$marcador$marcador';
      c.selection = TextSelection.collapsed(
        offset: texto.length + marcador.length,
      );
      return;
    }
    final trecho = sel.textInside(texto);
    c.value = TextEditingValue(
      text:
          '${sel.textBefore(texto)}$marcador$trecho$marcador'
          '${sel.textAfter(texto)}',
      selection: TextSelection.collapsed(
        offset: sel.start + marcador.length + trecho.length,
      ),
    );
    setState(() {});
  }

  /// Prefixa "- " nas linhas da seleção (ou na linha do cursor).
  void _listar() {
    final c = widget.controller;
    final texto = c.text;
    final sel = c.selection.isValid
        ? c.selection
        : TextSelection.collapsed(offset: texto.length);
    final inicioLinha =
        texto.lastIndexOf('\n', sel.start > 0 ? sel.start - 1 : 0) + 1;
    final trecho = texto.substring(inicioLinha, sel.end);
    final comBullets = trecho
        .split('\n')
        .map((l) => l.startsWith('- ') ? l : '- $l')
        .join('\n');
    c.value = TextEditingValue(
      text:
          texto.substring(0, inicioLinha) +
          comBullets +
          texto.substring(sel.end),
      selection: TextSelection.collapsed(
        offset: inicioLinha + comBullets.length,
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.rotulo,
              style: const TextStyle(color: VizColors.muted, fontSize: 12),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Negrito (**texto**)',
              icon: const Icon(Icons.format_bold, size: 18),
              onPressed: _preview ? null : () => _envolver('**'),
            ),
            IconButton(
              tooltip: 'Destaque (==texto==)',
              icon: const Icon(Icons.border_color_outlined, size: 18),
              onPressed: _preview ? null : () => _envolver('=='),
            ),
            IconButton(
              tooltip: 'Lista (- item)',
              icon: const Icon(Icons.format_list_bulleted, size: 18),
              onPressed: _preview ? null : _listar,
            ),
            IconButton(
              tooltip: _preview ? 'Editar' : 'Pré-visualizar',
              icon: Icon(
                _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                size: 18,
              ),
              onPressed: () => setState(() => _preview = !_preview),
            ),
          ],
        ),
        if (_preview)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: VizColors.gridline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.controller.text.trim().isEmpty
                ? const Text(
                    'Sem notas',
                    style: TextStyle(color: VizColors.muted),
                  )
                : NotasRicasView(texto: widget.controller.text),
          )
        else
          TextField(
            controller: widget.controller,
            maxLines: widget.linhas,
            minLines: widget.linhas < 3 ? widget.linhas : 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '**negrito** · ==destaque== · "- " para lista',
            ),
          ),
      ],
    );
  }
}
