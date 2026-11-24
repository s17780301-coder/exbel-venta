import 'dart:async';

import '../data/ajustes_repo.dart';
import '../data/repos.dart';
import 'ids.dart';
import 'nube.dart';

/// Identificador de la tienda en la nube (el mismo para todas sus cajas).
const claveTiendaId = 'tienda_id';

Future<String> tiendaId() async {
  var id = repos.ajustes.texto(claveTiendaId);
  if (id.length != 36) {
    id = nuevoId();
    await repos.ajustes.guardar(claveTiendaId, id);
  }
  return id;
}

/// Código de 6 números (válido 15 minutos) para vincular un celular con
/// exBel Alerta. null si no hay internet.
Future<String?> codigoVinculo() async {
  final r = await nubeRpc('exbel_codigo_vinculo', {
    'p_tienda_id': await tiendaId(),
    'p_nombre': repos.ajustes.texto(Ajuste.nombreNegocio),
    'p_direccion': repos.ajustes.texto(Ajuste.direccion),
    'p_telefono': repos.ajustes.texto(Ajuste.telefono),
  });
  return r is String ? r : null;
}

bool _enviando = false;

/// Alerta silenciosa a los celulares con exBel Alerta. Reintenta hasta 3
/// minutos si no hay internet. true si llegó a la nube.
Future<bool> enviarAlertaEmergencia({required String caja, required String cajero, required String equipo, bool prueba = false}) async {
  if (_enviando && !prueba) return false;
  _enviando = true;
  try {
    final id = await tiendaId();
    final fin = DateTime.now().add(const Duration(minutes: 3));
    while (true) {
      final r = await nubeRpc('exbel_alerta2', {
        'p_tienda_id': id,
        'p_equipo': equipo,
        'p_caja': caja,
        'p_cajero': cajero,
        'p_prueba': prueba,
      });
      if (r != null) {
        // Además del aviso que revisan los celulares cada 5 s, se manda push.
        if (r is int) await nubeFuncion('exbel-push', {'alerta': r});
        return true;
      }
      if (prueba || DateTime.now().isAfter(fin)) return false;
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  } finally {
    _enviando = false;
  }
}

/// Avisa a la nube que esta caja sigue en línea (cada pocos minutos).
Future<void> latido({required String caja, required String cajero, required String equipo}) async {
  try {
    await nubeRpc('exbel_latido', {'p_tienda_id': await tiendaId(), 'p_equipo': equipo, 'p_caja': caja, 'p_cajero': cajero});
  } catch (_) {}
}

/// Botón de pánico: poner la mano sobre el teclado, en cualquier parte.
/// Se activa con 4 o más teclas apretadas al mismo tiempo, o con 3 a la vez
/// dos veces seguidas (por si el teclado no reconoce tantas juntas). El lector
/// de códigos manda una tecla a la vez, así que no lo activa.
class DetectorPanico {
  DateTime? _tres;
  DateTime? _ultima;

  /// [presionadas]: teclas apretadas en este momento (incluida la nueva).
  bool alPresionar(int presionadas, DateTime ahora) {
    var activar = false;
    if (presionadas >= 4) {
      activar = true;
    } else if (presionadas == 3) {
      final antes = _tres;
      if (antes != null && ahora.difference(antes) <= const Duration(milliseconds: 1500)) activar = true;
      _tres = ahora;
    }
    if (!activar) return false;
    // Una sola alerta cada 20 segundos aunque sigan apretando.
    final u = _ultima;
    if (u != null && ahora.difference(u) < const Duration(seconds: 20)) return false;
    _ultima = ahora;
    _tres = null;
    return true;
  }

  /// Mientras hay 3 o más teclas apretadas no se escribe nada en pantalla.
  static bool tragar(int presionadas) => presionadas >= 3;

}
