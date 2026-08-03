import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/boot/falha_boot.dart';
import 'core/notificacoes/notificacoes_service.dart';
import 'data/local/hive_boxes.dart';
import 'data/models/configuracoes.dart';

void main() {
  // O boot inteiro roda dentro de um zone guardado para que erro assíncrono
  // que escape de um `await` não suma no vazio. `ensureInitialized()` e
  // `runApp` precisam acontecer no MESMO zone — por isso os dois moram dentro
  // de [iniciar], e não aqui fora.
  runZonedGuarded(iniciar, (erro, pilha) {
    FlutterError.presentError(
      FlutterErrorDetails(
        exception: erro,
        stack: pilha,
        library: 'boot',
        context: ErrorDescription('erro assíncrono não capturado no boot'),
      ),
    );
  });
}

/// Sequência de boot. Separada de [main] para poder ser reexecutada pelo botão
/// "Tentar de novo" da [FalhaBootApp] — `runApp` pode ser chamado de novo e
/// troca a árvore inteira, então uma segunda tentativa bem-sucedida substitui
/// a tela de falha pelo app sem exigir que o usuário recarregue a página.
Future<void> iniciar() async {
  WidgetsFlutterBinding.ensureInitialized();
  _instalarCapturaDeErro();

  // Fronteira do que é fatal: sem armazenamento aberto e migrado não existe
  // app — todo o estado do produto mora no Hive. Falhar aqui precisa produzir
  // uma TELA, nunca o retângulo branco que o `runApp` jamais chamado deixava.
  var passo = PassoBoot.armazenamento;
  try {
    await Hive.initFlutter();
    await HiveBoxes.openAll();

    passo = PassoBoot.migracao;
    await HiveBoxes.migrar();
    await HiveBoxes.seedResumos();
  } catch (erro, pilha) {
    FlutterError.presentError(
      FlutterErrorDetails(
        exception: erro,
        stack: pilha,
        library: 'boot',
        context: ErrorDescription('ao preparar o armazenamento local'),
      ),
    );
    runApp(
      FalhaBootApp(
        passo: passo,
        erro: erro,
        pilha: pilha,
        aoTentarNovamente: iniciar,
      ),
    );
    return;
  }

  // Daqui para baixo NADA é fatal. Lembrete é conveniência; os dados já estão
  // abertos e a tela de Revisões continua sendo a fonte de verdade. Antes,
  // uma configuração corrompida derrubava o boot inteiro por causa de um
  // agendamento — trocava o acesso a todo o histórico por um lembrete.
  await _prepararLembreteDiario();

  runApp(const ProviderScope(child: AppEstudos()));
}

/// Reagenda o lembrete diário no boot (idempotente): notificação repetida não
/// sobrevive a reinstalação/limpeza sem isso.
Future<void> _prepararLembreteDiario() async {
  try {
    await NotificacoesService.inicializar();
    final bruto = Hive.box<Map>(HiveBoxes.config).get('config');
    final config = bruto == null
        ? const Configuracoes()
        : Configuracoes.fromJson(Map<String, dynamic>.from(bruto));
    await NotificacoesService.agendarLembreteDiario(config.horaLembreteEstudo);
  } catch (erro, pilha) {
    FlutterError.presentError(
      FlutterErrorDetails(
        exception: erro,
        stack: pilha,
        library: 'boot',
        context: ErrorDescription(
          'ao reagendar o lembrete diário — o app segue normalmente',
        ),
      ),
    );
  }
}

void _instalarCapturaDeErro() {
  // `FlutterError.onError` fica no padrão de propósito: o handler default já
  // chama `presentError`, então sobrescrevê-lo para fazer a mesma coisa seria
  // ruído. O ganho real está nos dois de baixo.

  // Troca a caixa cinza vazia do release por algo legível na subárvore que
  // falhou. Em debug o console segue recebendo o dump completo.
  ErrorWidget.builder = construirWidgetDeErro;

  // Erro assíncrono da plataforma que não passa pelo zone (callback de plugin,
  // por exemplo). Em release devolve `true` para manter o app de pé com o erro
  // registrado; em debug devolve `false` para o crash aparecer alto e claro em
  // vez de ser mascarado durante o desenvolvimento.
  WidgetsBinding.instance.platformDispatcher.onError = (erro, pilha) {
    FlutterError.presentError(
      FlutterErrorDetails(exception: erro, stack: pilha, library: 'app'),
    );
    return !kDebugMode;
  };
}
