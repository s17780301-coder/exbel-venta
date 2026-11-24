import 'dart:convert';
import 'dart:io';

import '../data/repos.dart';
import 'nube.dart';

/// Contacto que recibe la alerta por WhatsApp (CallMeBot).
class ContactoEmergencia {
  ContactoEmergencia({required this.nombre, required this.telefono, required this.clave});
  final String nombre;

  /// Con lada de país: +52 1 55 1234 5678 (se limpian espacios y guiones).
  final String telefono;

  /// APIKEY que CallMeBot le manda a ese número al activarlo.
  final String clave;

  Map<String, String> aMapa() => {'nombre': nombre, 'telefono': telefono, 'clave': clave};
  static ContactoEmergencia deMapa(Map m) =>
      ContactoEmergencia(nombre: '${m['nombre'] ?? ''}', telefono: '${m['telefono'] ?? ''}', clave: '${m['clave'] ?? ''}');

  String get telefonoLimpio {
    var t = telefono.replaceAll(RegExp(r'[^0-9+]'), '');
    if (!t.startsWith('+')) t = t.length == 10 ? '+52$t' : '+$t';
    return t;
  }
}

const claveContactosEmergencia = 'emergencia_contactos';
const claveMensajeEmergencia = 'emergencia_mensaje';
const mensajeEmergenciaOmision =
    '🚨 *EMERGENCIA* en {tienda} ({caja}). Cajero: {cajero}. Hora: {hora}. Por favor llamen o vengan de inmediato.';

List<ContactoEmergencia> contactosEmergencia() {
  try {
    final t = repos.ajustes.texto(claveContactosEmergencia);
    if (t.isEmpty) return [];
    return [for (final m in jsonDecode(t) as List) ContactoEmergencia.deMapa(m as Map)];
  } catch (_) {
    return [];
  }
}

Future<void> guardarContactosEmergencia(List<ContactoEmergencia> l) =>
    repos.ajustes.guardar(claveContactosEmergencia, jsonEncode([for (final c in l) c.aMapa()]));

/// Envía un WhatsApp con CallMeBot. true si salió.
Future<bool> enviarWhatsApp(ContactoEmergencia c, String texto) async {
  if (c.clave.trim().isEmpty || c.telefono.trim().isEmpty) return false;
  final url = Uri.https('api.callmebot.com', '/whatsapp.php', {'phone': c.telefonoLimpio, 'text': texto, 'apikey': c.clave.trim()});
  for (var intento = 0; intento < 3; intento++) {
    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final res = await (await cliente.getUrl(url)).close().timeout(const Duration(seconds: 15));
      final cuerpo = await utf8.decodeStream(res);
      if (res.statusCode < 300 && !cuerpo.toLowerCase().contains('error')) return true;
    } catch (_) {
    } finally {
      cliente.close(force: true);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  return false;
}

bool _enviando = false;

/// Alerta silenciosa a todos los contactos. Regresa (enviadas, fallidas).
Future<(int, int)> enviarAlertaEmergencia({required String tienda, required String caja, required String cajero, required String equipo, bool prueba = false}) async {
  if (_enviando && !prueba) return (0, 0);
  _enviando = true;
  try {
    final ahora = DateTime.now();
    final hora = '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')} '
        '${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}';
    var plantilla = repos.ajustes.texto(claveMensajeEmergencia);
    if (plantilla.trim().isEmpty) plantilla = mensajeEmergenciaOmision;
    var texto = plantilla
        .replaceAll('{tienda}', tienda)
        .replaceAll('{caja}', caja)
        .replaceAll('{cajero}', cajero.isEmpty ? 'sin cajero' : cajero)
        .replaceAll('{hora}', hora);
    if (prueba) texto = 'PRUEBA del botón de emergencia de exBel venta (no es una emergencia real).\n\n$texto';
    final contactos = contactosEmergencia();
    final res = await Future.wait([for (final c in contactos) enviarWhatsApp(c, texto)]);
    final ok = res.where((x) => x).length;
    if (!prueba) {
      await nubeRpc('exbel_alerta', {
        'p_equipo': equipo,
        'p_tienda': tienda,
        'p_caja': caja,
        'p_cajero': cajero,
        'p_enviadas': ok,
        'p_fallidas': contactos.length - ok,
      });
    }
    return (ok, contactos.length - ok);
  } finally {
    _enviando = false;
  }
}
