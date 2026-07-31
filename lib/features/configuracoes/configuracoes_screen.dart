import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../application/apagar_dados_use_case.dart';
import '../../core/notificacoes/notificacoes_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/configuracoes_repositorio.dart';

class ConfiguracoesScreen extends ConsumerStatefulWidget {
  const ConfiguracoesScreen({super.key});

  @override
  ConsumerState<ConfiguracoesScreen> createState() =>
      _ConfiguracoesScreenState();
}

class _ConfiguracoesScreenState extends ConsumerState<ConfiguracoesScreen> {
  late final TextEditingController _intervalos;
  late final TextEditingController _metaSemanal;
  late int _hora;
  int? _horaLembreteEstudo;
  late int _minutosPadraoRevisao;

  @override
  void initState() {
    super.initState();
    final config = ref.read(configuracoesProvider);
    _intervalos = TextEditingController(
      text: config.intervalosRevisao.join(', '),
    );
    _metaSemanal = TextEditingController(
      text: _formatarHoras(config.metaSemanalMinutos),
    );
    _hora = config.horaNotificacao;
    _horaLembreteEstudo = config.horaLembreteEstudo;
    _minutosPadraoRevisao = config.minutosPadraoRevisao;
  }

  @override
  void dispose() {
    _intervalos.dispose();
    _metaSemanal.dispose();
    super.dispose();
  }

  /// 1800 -> "30" · 1830 -> "30,5" (horas com vírgula, convenção pt-BR).
  static String _formatarHoras(int minutos) {
    final horas = minutos / 60.0;
    return horas == horas.roundToDouble()
        ? horas.round().toString()
        : horas.toStringAsFixed(1).replaceAll('.', ',');
  }

  /// "30" ou "22,5" -> minutos; null quando inválido ou <= 0.
  int? _parseMetaSemanal() {
    final texto = _metaSemanal.text.trim().replaceAll(',', '.');
    final horas = double.tryParse(texto);
    if (horas == null || horas <= 0 || horas > 24 * 7) return null;
    return (horas * 60).round();
  }

  List<int>? _parseIntervalos() {
    final valores = _intervalos.text
        .split(RegExp(r'[,;\s]+'))
        .where((s) => s.isNotEmpty)
        .map(int.tryParse)
        .toList();
    if (valores.isEmpty || valores.any((v) => v == null || v <= 0)) {
      return null;
    }
    final unicos = valores.cast<int>().toSet().toList()..sort();
    return unicos;
  }

  Future<void> _salvar() async {
    final intervalos = _parseIntervalos();
    if (intervalos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Intervalos inválidos. Use números de dias separados por vírgula, ex.: 7, 15, 30',
          ),
        ),
      );
      return;
    }
    final metaSemanal = _parseMetaSemanal();
    if (metaSemanal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Meta semanal inválida. Use horas, ex.: 30 ou 22,5'),
        ),
      );
      return;
    }
    final config = ref
        .read(configuracoesProvider)
        .copyWith(
          intervalosRevisao: intervalos,
          horaNotificacao: _hora,
          metaSemanalMinutos: metaSemanal,
          horaLembreteEstudo: _horaLembreteEstudo,
          desligarLembreteEstudo: _horaLembreteEstudo == null,
          minutosPadraoRevisao: _minutosPadraoRevisao,
        );
    await ref.read(configuracoesProvider.notifier).salvar(config);
    await NotificacoesService.agendarLembreteDiario(_horaLembreteEstudo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Salvo. Vale para as próximas revisões; as já agendadas não mudam.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ConteudoCentral(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _intervalos,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Intervalos de revisão (dias)',
                helperText: 'Separados por vírgula. Ex.: 7, 15, 30, 60',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _metaSemanal,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Meta semanal (horas)',
                helperText:
                    'Usada quando o cronograma da semana está vazio. Ex.: 30',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _hora,
              decoration: const InputDecoration(
                labelText: 'Hora do lembrete de revisão',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var h = 5; h <= 23; h++)
                  DropdownMenuItem(
                    value: h,
                    child: Text('${h.toString().padLeft(2, '0')}:00'),
                  ),
              ],
              onChanged: (v) => setState(() => _hora = v ?? _hora),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int?>(
              initialValue: _horaLembreteEstudo,
              decoration: const InputDecoration(
                labelText: 'Lembrete diário de estudo',
                helperText: 'Notificação todo dia na hora escolhida',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Desligado'),
                ),
                for (var h = 5; h <= 23; h++)
                  DropdownMenuItem<int?>(
                    value: h,
                    child: Text('${h.toString().padLeft(2, '0')}:00'),
                  ),
              ],
              onChanged: (v) => setState(() => _horaLembreteEstudo = v),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _minutosPadraoRevisao,
              decoration: const InputDecoration(
                labelText: 'Tempo creditado por revisão concluída',
                helperText:
                    'ESTIMATIVA: quando você conclui uma revisão informando '
                    'questões sem informar o tempo, o app credita estes '
                    'minutos. Isso soma no total de horas sem ter sido '
                    'cronometrado. "Não creditar" mantém só as questões.',
                helperMaxLines: 4,
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Não creditar tempo')),
                DropdownMenuItem(value: 5, child: Text('5 minutos')),
                DropdownMenuItem(value: 10, child: Text('10 minutos')),
                DropdownMenuItem(value: 15, child: Text('15 minutos')),
                DropdownMenuItem(value: 20, child: Text('20 minutos')),
                DropdownMenuItem(value: 30, child: Text('30 minutos')),
              ],
              onChanged: (v) =>
                  setState(() => _minutosPadraoRevisao = v ?? _minutosPadraoRevisao),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _salvar, child: const Text('Salvar')),
            const SizedBox(height: 40),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Zona de perigo',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: StatusColors.critico,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(
                  Icons.delete_forever,
                  color: StatusColors.critico,
                ),
                title: const Text('Apagar todos os dados'),
                subtitle: const Text(
                  'Remove permanentemente tudo o que você registrou. '
                  'Não há como desfazer.',
                ),
                onTap: () => mostrarDialogoApagarDados(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wipe out com trava dupla: mostra a contagem EXATA do que será perdido
/// (ApagarDadosUseCase.contarRegistrosParaApagar) e só libera o botão
/// destrutivo quando o usuário digita "APAGAR" — ação irreversível, sem
/// undo e sem backup automático (ver ApagarDadosUseCase.apagarTudo).
Future<void> mostrarDialogoApagarDados(
  BuildContext context,
  WidgetRef ref,
) async {
  final contagem = ref
      .read(apagarDadosUseCaseProvider)
      .contarRegistrosParaApagar();
  final controller = TextEditingController();
  // Capturados ANTES do showDialog: continuam válidos após o await de
  // apagarTudo() mesmo que o diálogo/tela por trás já tenham sido fechados
  // (Navigator/ScaffoldMessenger são compartilhados pelo MaterialApp, não
  // por Scaffold individual — sobrevivem à navegação entre rotas).
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setStateDialog) {
        final confirmado = controller.text.trim().toUpperCase() == 'APAGAR';
        return AlertDialog(
          title: const Text('Apagar todos os dados'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Isto vai apagar permanentemente ${contagem.registros} '
                  'registros, ${contagem.materias} matérias, '
                  '${contagem.topicos} tópicos, ${contagem.aulas} aulas, '
                  '${contagem.revisoes} revisões, ${contagem.resumos} '
                  'resumos, ${contagem.leituras} leituras, '
                  '${contagem.simulados} simulados, '
                  // O caderno de erros é conteúdo escrito à mão (enunciado e
                  // motivo do erro): omiti-lo da lista escondia justamente o
                  // dado mais caro de reproduzir.
                  '${contagem.questoesErradas} questões do caderno de erros '
                  'e ${contagem.ambientes} ambientes.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'A ação é irreversível e o app não faz backup automático. '
                  'Para manter uma cópia, exporte antes em "Exportar & '
                  'Importar".',
                  style: TextStyle(
                    color: StatusColors.critico,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Digite APAGAR para confirmar',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setStateDialog(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: StatusColors.criticoSuperficie,
                foregroundColor: Colors.white,
              ),
              onPressed: confirmado
                  ? () async {
                      await ref.read(apagarDadosUseCaseProvider).apagarTudo();
                      if (!dialogContext.mounted) return;
                      Navigator.pop(dialogContext);
                      ref.read(abaProvider.notifier).ir(Abas.dashboard);
                      if (navigator.canPop()) navigator.pop();
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Todos os dados foram apagados.'),
                        ),
                      );
                    }
                  : null,
              child: const Text('Apagar tudo'),
            ),
          ],
        );
      },
    ),
  );
}
