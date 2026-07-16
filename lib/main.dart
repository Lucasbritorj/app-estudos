import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/notificacoes/notificacoes_service.dart';
import 'data/local/hive_boxes.dart';
import 'data/models/configuracoes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await HiveBoxes.openAll();
  await HiveBoxes.migrarAmbientes();
  await HiveBoxes.seedResumos();
  await NotificacoesService.inicializar();
  // Reagenda o lembrete diário no boot (idempotente) — notificação
  // repetida não sobrevive a reinstalação/limpeza sem isso.
  final rawConfig = Hive.box<Map>(HiveBoxes.config).get('config');
  final config = rawConfig == null
      ? const Configuracoes()
      : Configuracoes.fromJson(Map<String, dynamic>.from(rawConfig));
  await NotificacoesService.agendarLembreteDiario(config.horaLembreteEstudo);
  runApp(const ProviderScope(child: AppEstudos()));
}
