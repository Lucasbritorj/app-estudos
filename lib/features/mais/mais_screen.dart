import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../ambientes/ambientes_screen.dart';
import '../materias/importar_edital.dart';
import '../configuracoes/configuracoes_screen.dart';
import '../exportar/exportar_screen.dart';
import '../leituras/leituras_screen.dart';
import '../mapa/mapa_estudos_screen.dart';
import '../planejamento/planejamento_screen.dart';
import '../resumos/resumos_screen.dart';
import '../simulados/simulados_screen.dart';

class MaisScreen extends ConsumerWidget {
  const MaisScreen({super.key});

  void _abrir(BuildContext context, Widget tela) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mais')),
      body: ConteudoCentral(
        child: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.workspaces_outlined),
            title: const Text('Ambientes'),
            subtitle: const Text(
                'Concursos, cursos e projetos de estudo separados'),
            onTap: () => _abrir(context, const AmbientesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: const Text('Mapa de Estudos'),
            subtitle: const Text(
                'Edital em árvore: status, % de acerto e projeção de leitura'),
            onTap: () => _abrir(context, const MapaEstudosScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste_go),
            title: const Text('Importar edital (colar texto)'),
            subtitle: const Text(
                'Copie do PDF e cole — numeração vira hierarquia de tópicos'),
            onTap: () => mostrarImportarEdital(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Simulados & Provas'),
            subtitle: const Text(
                'Tempo, questões e acertos — taxa e min/questão calculados'),
            onTap: () => _abrir(context, const SimuladosScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Planejamento semanal'),
            subtitle: const Text('Horas por dia e ciclo sugerido por peso'),
            onTap: () => _abrir(context, const PlanejamentoScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.tag),
            title: const Text('Resumos por matéria'),
            subtitle: const Text(
                'Página única por matéria com tags #sigla e data de edição'),
            onTap: () => _abrir(context, const ResumosScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Leituras'),
            subtitle: const Text('Divisão de PDFs em partes com progresso'),
            onTap: () => _abrir(context, const LeiturasScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('Exportar dados'),
            subtitle: const Text('CSV, JSON (backup) e PDF (relatório)'),
            onTap: () => _abrir(context, const ExportarScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Configurações'),
            subtitle: const Text('Intervalos de revisão e hora do lembrete'),
            onTap: () => _abrir(context, const ConfiguracoesScreen()),
          ),
        ],
        ),
      ),
    );
  }
}
