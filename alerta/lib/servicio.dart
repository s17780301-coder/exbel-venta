import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nube.dart';

/// Servicio que vigila las cajas todo el tiempo (aunque la app esté cerrada).
@pragma('vm:entry-point')
void iniciarVigilancia() {
  FlutterForegroundTask.setTaskHandler(Vigilancia());
}

void configurarServicio() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'exbel_vigilancia',
      channelName: 'Vigilancia de cajas',
      channelDescription: 'Mantiene exBel Alerta atento a las cajas',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

Future<void> arrancarServicio() async {
  if (await FlutterForegroundTask.isRunningService) return;
  await FlutterForegroundTask.startService(
    serviceId: 4711,
    notificationTitle: 'exBel Alerta',
    notificationText: 'Vigilando las cajas',
    callback: iniciarVigilancia,
  );
}

/// Alerta que está sonando (para la pantalla roja).
class AlertaActiva {
  AlertaActiva({required this.id, required this.token, required this.tienda, required this.caja, required this.cajero,
      required this.creado, required this.prueba, this.direccion = '', this.telefono = ''});
  final int id;
  final String token, tienda, caja, cajero, direccion, telefono;
  final DateTime creado;
  final bool prueba;

  Map<String, Object> aMapa() => {
        'id': id, 'token': token, 'tienda': tienda, 'caja': caja, 'cajero': cajero, 'creado': creado.toIso8601String(),
        'prueba': prueba, 'direccion': direccion, 'telefono': telefono,
      };
  static AlertaActiva deMapa(Map m) => AlertaActiva(
        id: m['id'] as int, token: '${m['token']}', tienda: '${m['tienda']}', caja: '${m['caja']}', cajero: '${m['cajero']}',
        creado: DateTime.tryParse('${m['creado']}') ?? DateTime.now(), prueba: m['prueba'] == true,
        direccion: '${m['direccion'] ?? ''}', telefono: '${m['telefono'] ?? ''}');
}

Future<AlertaActiva?> alertaActiva() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  final t = p.getString('alerta_activa');
  if (t == null) return null;
  try {
    return AlertaActiva.deMapa(jsonDecode(t) as Map);
  } catch (_) {
    return null;
  }
}

Future<void> limpiarAlerta() async {
  final p = await SharedPreferences.getInstance();
  await p.remove('alerta_activa');
  await Alarm.stopAll();
}

/// Suena la sirena a todo volumen, en bucle, con la pantalla de alerta.
Future<void> sonarSirena(AlertaActiva a) async {
  final p = await SharedPreferences.getInstance();
  await p.setString('alerta_activa', jsonEncode(a.aMapa()));
  await Alarm.set(
    alarmSettings: AlarmSettings(
      id: 1 + a.id % 100000,
      dateTime: DateTime.now().add(const Duration(seconds: 1)),
      assetAudioPath: 'assets/sirena.wav',
      loopAudio: true,
      vibrate: true,
      androidFullScreenIntent: true,
      androidStopAlarmOnTermination: false,
      volumeSettings: VolumeSettings.fixed(volume: 1.0, volumeEnforced: true),
      notificationSettings: NotificationSettings(
        title: a.prueba ? 'Prueba de alerta · ${a.tienda}' : '¡EMERGENCIA! ${a.tienda}',
        body: '${a.caja} · ${a.cajero.isEmpty ? 'sin cajero' : a.cajero}. Toca para ver.',
        stopButton: null,
      ),
    ),
  );
}

/// Revisa la nube: si hay alerta nueva suena; si otro la atendió, se calla.
Future<void> revisarAlertas() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  final activa = await alertaActiva();
  for (final v in await vinculos()) {
    final clave = 'desde_${v.token}';
    final desde = p.getInt(clave);
    Object? r;
    try {
      r = await rpc('exbel_pendientes', {'p_token': v.token, 'p_desde': desde ?? 0});
    } catch (_) {
      continue;
    }
    if (r is! Map) continue;
    await p.setString('estado_${v.token}', jsonEncode(r));
    final alertas = (r['alertas'] as List?) ?? [];
    var maximo = desde ?? 0;
    for (final a in alertas.cast<Map>()) {
      final id = a['id'] as int;
      if (id > maximo) maximo = id;
      final creado = DateTime.tryParse('${a['creado']}')?.toLocal() ?? DateTime.now();
      // La primera vez que se revisa no suenan alertas viejas.
      final reciente = DateTime.now().difference(creado).inMinutes < 10;
      if (desde != null && a['atendida_en'] == null && reciente) {
        await sonarSirena(AlertaActiva(
            id: id, token: v.token, tienda: '${r['tienda']}', caja: '${a['caja'] ?? ''}', cajero: '${a['cajero'] ?? ''}',
            creado: creado, prueba: a['prueba'] == true, direccion: '${r['direccion'] ?? ''}', telefono: '${r['telefono'] ?? ''}'));
      }
    }
    await p.setInt(clave, maximo);
    // ¿La que suena ya la atendió alguien más?
    if (activa != null && activa.token == v.token) {
      final hist = ((r['historial'] as List?) ?? []).cast<Map>();
      final h = hist.where((x) => x['id'] == activa.id).firstOrNull;
      if (h != null && h['atendida_por'] != null) {
        await p.setString('atendida_por_${activa.id}', '${h['atendida_por']}');
        await limpiarAlerta();
      }
    }
  }
}

class Vigilancia extends TaskHandler {
  bool _ocupado = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Alarm.init();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    if (_ocupado) return;
    _ocupado = true;
    revisarAlertas().catchError((Object e) => debugPrint('$e')).whenComplete(() => _ocupado = false);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
