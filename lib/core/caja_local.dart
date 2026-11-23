import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

/// Configuración propia de ESTA computadora (no se comparte entre cajas):
/// si es la caja principal o una caja adicional, su nombre, la dirección de
/// la principal y los ajustes que son de cada caja (impresora, cajón,
/// tamaño de pantalla, tickets en espera…). Se guarda en caja.json.
class CajaLocal {
  String? _ruta;
  Map<String, Object?> _datos = {};

  /// 'principal' (guarda la base de datos) o 'secundaria' (se conecta).
  String get modo => (_datos['modo'] as String?) ?? 'principal';
  bool get esSecundaria => modo == 'secundaria';
  String get nombreCaja => (_datos['nombreCaja'] as String?) ?? (esSecundaria ? 'Caja 2' : 'Caja 1');
  String get servidor => (_datos['servidor'] as String?) ?? '';
  String get clave => (_datos['clave'] as String?) ?? '';

  /// En la principal: si otras cajas se pueden conectar.
  bool get redActiva => _datos['red'] == true;

  Map<String, String> get ajustes => Map<String, String>.from((_datos['ajustes'] as Map?) ?? {});

  Future<void> cargar(Directory carpeta) async {
    _ruta = p.join(carpeta.path, 'caja.json');
    try {
      final f = File(_ruta!);
      if (await f.exists()) _datos = Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {
      _datos = {};
    }
  }

  Future<void> _guardar() async {
    final r = _ruta;
    if (r == null) return; // pruebas: solo en memoria
    await File(r).writeAsString(const JsonEncoder.withIndent('  ').convert(_datos));
  }

  Future<void> cambiar({String? modo, String? nombreCaja, String? servidor, String? clave, bool? red}) async {
    if (modo != null) _datos['modo'] = modo;
    if (nombreCaja != null) _datos['nombreCaja'] = nombreCaja.trim();
    if (servidor != null) _datos['servidor'] = servidor.trim();
    if (clave != null) _datos['clave'] = clave.trim();
    if (red != null) _datos['red'] = red;
    await _guardar();
  }

  /// Clave de red de la principal (se genera la primera vez).
  Future<String> claveDeRed() async {
    if (clave.isEmpty) {
      final r = Random.secure();
      await cambiar(clave: List.generate(6, (_) => r.nextInt(10)).join());
    }
    return clave;
  }

  String? ajuste(String k) => ajustes[k];

  Future<void> guardarAjuste(String k, String v) async {
    final a = ajustes..[k] = v;
    _datos['ajustes'] = a;
    await _guardar();
  }
}

final cajaLocal = CajaLocal();
