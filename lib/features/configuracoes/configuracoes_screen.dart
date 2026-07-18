import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
            const SizedBox(height: 24),
            FilledButton(onPressed: _salvar, child: const Text('Salvar')),
          ],
        ),
      ),
    );
  }
}
