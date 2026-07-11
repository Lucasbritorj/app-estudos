import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Lembretes locais de revisão. Best-effort: se a plataforma não suportar
/// (ex.: rodando no desktop sem registro de app), o app segue funcionando e
/// a tela de Revisões continua sendo a fonte de verdade.
class NotificacoesService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _pronto = false;

  static Future<void> inicializar() async {
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
          settings: const InitializationSettings(android: android));
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _pronto = true;
    } catch (erro) {
      debugPrint('Notificações indisponíveis nesta plataforma: $erro');
    }
  }

  static int _idNumerico(String id) => id.hashCode & 0x7fffffff;

  /// Agenda lembrete no dia da revisão, na hora configurada. Datas passadas
  /// não agendam nada.
  static Future<void> agendarRevisao({
    required String id,
    required String titulo,
    required DateTime dia,
    required int hora,
  }) async {
    if (!_pronto) return;
    try {
      final quando = tz.TZDateTime(tz.local, dia.year, dia.month, dia.day, hora);
      if (!quando.isAfter(tz.TZDateTime.now(tz.local))) return;
      await _plugin.zonedSchedule(
        id: _idNumerico(id),
        title: 'Revisão de hoje',
        body: titulo,
        scheduledDate: quando,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'revisoes',
            'Revisões espaçadas',
            channelDescription: 'Lembretes de revisão agendada',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (erro) {
      debugPrint('Falha ao agendar notificação: $erro');
    }
  }

  static Future<void> cancelar(String id) async {
    if (!_pronto) return;
    try {
      await _plugin.cancel(id: _idNumerico(id));
    } catch (erro) {
      debugPrint('Falha ao cancelar notificação: $erro');
    }
  }

  static const _idLembreteDiario = 900001;

  /// Lembrete diário de estudo na [hora] (repete todo dia); null desliga.
  /// Idempotente: sempre cancela o anterior antes de agendar.
  static Future<void> agendarLembreteDiario(int? hora) async {
    if (!_pronto) return;
    try {
      await _plugin.cancel(id: _idLembreteDiario);
      if (hora == null) return;
      final agora = tz.TZDateTime.now(tz.local);
      var quando =
          tz.TZDateTime(tz.local, agora.year, agora.month, agora.day, hora);
      if (!quando.isAfter(agora)) {
        quando = quando.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        id: _idLembreteDiario,
        title: 'Hora de estudar',
        body: 'Uma sessão hoje protege o streak. Abra e registre.',
        scheduledDate: quando,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'lembrete-diario',
            'Lembrete diário de estudo',
            channelDescription: 'Lembrete configurável da hora de estudar',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (erro) {
      debugPrint('Falha ao agendar lembrete diário: $erro');
    }
  }
}
