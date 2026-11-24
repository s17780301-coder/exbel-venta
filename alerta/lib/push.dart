import 'package:alarm/alarm.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import 'firebase_opciones.dart';
import 'nube.dart';
import 'servicio.dart';

/// Llega una alerta por push (también con la app cerrada).
@pragma('vm:entry-point')
Future<void> alertaEnFondo(RemoteMessage m) async {
  WidgetsFlutterBinding.ensureInitialized();
  final o = opcionesFirebase;
  if (o != null) await Firebase.initializeApp(options: o);
  await Alarm.init();
  await _sonar(m);
}

Future<void> _sonar(RemoteMessage m) async {
  final d = m.data;
  if (d['tipo'] != 'alerta') return;
  final id = int.tryParse('${d['id']}') ?? 0;
  if (id <= 0) return;
  final creado = DateTime.tryParse('${d['creado']}') ?? DateTime.now();
  if (DateTime.now().difference(creado).inMinutes >= 10) return;
  final ya = await alertaActiva();
  if (ya != null && ya.id == id) return;
  final vs = await vinculos();
  final v = vs.where((x) => x.tienda == d['tienda']).firstOrNull ?? vs.firstOrNull;
  await sonarSirena(AlertaActiva(
    id: id,
    token: v?.token ?? '',
    tienda: '${d['tienda'] ?? ''}',
    caja: '${d['caja'] ?? ''}',
    cajero: '${d['cajero'] ?? ''}',
    direccion: '${d['direccion'] ?? ''}',
    telefono: '${d['telefono'] ?? ''}',
    creado: creado,
    prueba: d['prueba'] == '1',
  ));
}

/// Prende push y registra este celular en cada tienda vinculada.
Future<void> iniciarPush() async {
  final o = opcionesFirebase;
  if (o == null) return;
  try {
    await Firebase.initializeApp(options: o);
    FirebaseMessaging.onBackgroundMessage(alertaEnFondo);
    FirebaseMessaging.onMessage.listen(_sonar);
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission(alert: true, sound: true, criticalAlert: true);
    final t = await fm.getToken();
    if (t != null) await registrarPush(t);
    fm.onTokenRefresh.listen(registrarPush);
  } catch (_) {}
}

Future<void> registrarPush([String? fcm]) async {
  if (opcionesFirebase == null) return;
  try {
    fcm ??= await FirebaseMessaging.instance.getToken();
    if (fcm == null) return;
    for (final v in await vinculos()) {
      await rpc('exbel_push_token', {'p_token': v.token, 'p_fcm': fcm});
    }
  } catch (_) {}
}
