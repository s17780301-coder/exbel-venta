import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'nube.dart';

/// Prueba de 7 días y activación por equipo.
///
/// Cada computadora tiene un "código de equipo". exBel entrega un código de
/// activación que solo sirve para ese equipo. La fecha de inicio de la prueba
/// se guarda en dos lugares distintos y se usa la más
/// antigua; si el reloj se atrasa, cuenta la fecha más reciente que se vio.
const diasDePrueba = 7;
/// La clave real se pone al compilar (secreto de GitHub); no va en el código.
const _sal = String.fromEnvironment('EXBEL_SAL', defaultValue: 'solo-pruebas');

String codigoActivacionPara(String equipo) {
  final h = Hmac(sha256, utf8.encode(_sal)).convert(utf8.encode('exbel-venta|${equipo.toUpperCase().replaceAll('-', '')}'));
  final hex = h.toString().toUpperCase();
  return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
}

String _limpio(String c) => c.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');

class EstadoLicencia {
  EstadoLicencia({required this.equipo, required this.activada, required this.diasRestantes, required this.inicio});
  final String equipo;
  final bool activada;
  final int diasRestantes;
  final DateTime inicio;
  bool get vencida => !activada && diasRestantes <= 0;
}

class Licencia {
  Licencia._();
  static final instancia = Licencia._();

  String? _ruta;
  Map<String, Object?> _d = {};
  String equipo = '';
  EstadoLicencia? estado;

  /// Segunda copia, en otra carpeta del usuario.
  File? get _copia {
    final base = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['HOME'];
    if (base == null) return null;
    return File(p.join(base, 'Microsoft', 'CLR_v4.0', 'UsageLogs', '.exbv'));
  }

  Map<String, Object?> _otra = {};

  Future<void> _leerCopia() async {
    try {
      final f = _copia;
      if (f != null && await f.exists()) _otra = Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {
      _otra = {};
    }
  }

  Future<String?> _leerRegistro(String nombre) async => _otra[nombre] as String?;

  Future<void> _escribirRegistro(String nombre, String valor) async {
    _otra[nombre] = valor;
    try {
      final f = _copia;
      if (f == null) return;
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(_otra));
    } catch (_) {}
  }

  Future<String> _idEquipo() async {
    final e = Platform.environment;
    final base = [
      Platform.localHostname,
      e['COMPUTERNAME'] ?? '',
      e['PROCESSOR_IDENTIFIER'] ?? '',
      e['NUMBER_OF_PROCESSORS'] ?? '',
      e['SystemDrive'] ?? '',
    ].join('|');
    final h = sha256.convert(utf8.encode('exbel-equipo|$base')).toString().toUpperCase();
    return '${h.substring(0, 4)}-${h.substring(4, 8)}';
  }

  Future<EstadoLicencia> cargar(Directory carpeta) async {
    _ruta = p.join(carpeta.path, 'licencia.json');
    try {
      final f = File(_ruta!);
      if (await f.exists()) _d = Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {
      _d = {};
    }
    await _leerCopia();
    equipo = await _idEquipo();
    final ahora = DateTime.now();

    // Inicio de la prueba: el más antiguo de archivo y registro.
    final fechas = <DateTime>[
      if (DateTime.tryParse('${_d['inicio'] ?? ''}') case final f?) f,
      if (DateTime.tryParse(await _leerRegistro('inicio') ?? '') case final f?) f,
    ]..sort();
    final inicio = fechas.isEmpty ? ahora : fechas.first;

    // Fecha más reciente vista (por si atrasan el reloj).
    final vistas = <DateTime>[
      ahora,
      if (DateTime.tryParse('${_d['visto'] ?? ''}') case final f?) f,
      if (DateTime.tryParse(await _leerRegistro('visto') ?? '') case final f?) f,
    ]..sort();
    final visto = vistas.last;

    _d['inicio'] = inicio.toIso8601String();
    _d['visto'] = visto.toIso8601String();
    await _guardar();
    await _escribirRegistro('inicio', inicio.toIso8601String());
    await _escribirRegistro('visto', visto.toIso8601String());

    final codigo = (_d['activacion'] as String?) ?? await _leerRegistro('activacion') ?? '';
    final activada = codigo.isNotEmpty && _limpio(codigo) == _limpio(codigoActivacionPara(equipo));
    final usados = visto.difference(inicio).inHours / 24;
    final restantes = (diasDePrueba - usados).ceil().clamp(0, diasDePrueba);
    return estado = EstadoLicencia(equipo: equipo, activada: activada, diasRestantes: restantes, inicio: inicio);
  }

  /// Se reporta a la nube: la prueba cuenta desde la fecha más antigua
  /// conocida (aunque reinstalen o cambien de usuario de Windows) y, si la
  /// tienda ya fue activada desde el panel, se activa sola.
  Future<void> sincronizarNube({String? tienda, String? caja, String? version}) async {
    final e = estado;
    if (e == null || equipo.isEmpty) return;
    final r = await nubeRpc('exbel_registrar', {
      'p_equipo': equipo,
      'p_tienda': tienda,
      'p_caja': caja,
      'p_version': version,
      'p_inicio_local': e.inicio.toUtc().toIso8601String(),
      // Si se activó con código en esta caja, la nube lo comprueba y lo registra.
      if (e.activada && '${_d['activacion'] ?? ''}'.isNotEmpty) 'p_activacion': '${_d['activacion']}',
    });
    if (r is! Map) return;
    final inicioNube = DateTime.tryParse('${r['prueba_inicio']}')?.toLocal();
    final ahoraNube = DateTime.tryParse('${r['ahora']}')?.toLocal();
    var inicio = e.inicio;
    if (inicioNube != null && inicioNube.isBefore(inicio)) {
      inicio = inicioNube;
      _d['inicio'] = inicio.toIso8601String();
      await _guardar();
      await _escribirRegistro('inicio', inicio.toIso8601String());
    }
    var activada = e.activada;
    if (r['activado'] == true && !activada) {
      final codigo = codigoActivacionPara(equipo);
      _d['activacion'] = codigo;
      await _guardar();
      await _escribirRegistro('activacion', codigo);
      activada = true;
    }
    final ahora = ahoraNube != null && ahoraNube.isAfter(DateTime.now()) ? ahoraNube : DateTime.now();
    final usados = ahora.difference(inicio).inHours / 24;
    estado = EstadoLicencia(
        equipo: equipo, activada: activada, diasRestantes: (diasDePrueba - usados).ceil().clamp(0, diasDePrueba), inicio: inicio);
  }

  /// true si el código es correcto para este equipo.
  Future<bool> activar(String codigo) async {
    if (_limpio(codigo) != _limpio(codigoActivacionPara(equipo))) return false;
    _d['activacion'] = codigo.trim().toUpperCase();
    await _guardar();
    await _escribirRegistro('activacion', codigo.trim().toUpperCase());
    final e = estado;
    estado = EstadoLicencia(equipo: equipo, activada: true, diasRestantes: e?.diasRestantes ?? 0, inicio: e?.inicio ?? DateTime.now());
    // Avisa a la nube (sin esperar): así la venta queda registrada en Supabase.
    unawaited(sincronizarNube().catchError((_) {}));
    return true;
  }

  Future<void> _guardar() async {
    final r = _ruta;
    if (r == null) return;
    try {
      await File(r).writeAsString(jsonEncode(_d));
    } catch (_) {}
  }
}
