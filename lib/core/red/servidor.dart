import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../ids.dart';
import 'db_remota.dart';

/// Servidor de la CAJA PRINCIPAL: las cajas adicionales le mandan sus
/// consultas por la red local. Cada transacción de otra caja se ejecuta
/// completa aquí (todo o nada).
class ServidorCaja {
  ServidorCaja(this.db, {required this.clave, required this.descripcion, this.puerto = puertoRed, this.puertoUdp = puertoDescubrir});
  final Database db;
  final String clave;

  /// "Miscelánea Karina | Caja 1": lo que ven las otras cajas al buscarla.
  final String Function() descripcion;
  final int puerto;
  final int puertoUdp;

  HttpServer? _http;
  RawDatagramSocket? _udp;
  final _sesiones = <String, _Sesion>{};

  bool get activo => _http != null;
  int get puertoReal => _http?.port ?? puerto;

  Future<void> iniciar() async {
    if (_http != null) return;
    _http = await HttpServer.bind(InternetAddress.anyIPv4, puerto);
    _http!.listen(_atender, onError: (_) {});
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, puertoUdp);
      _udp!.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = _udp!.receive();
        if (d == null) return;
        if (utf8.decode(d.data, allowMalformed: true) == 'EXBEL?') {
          _udp!.send(utf8.encode('EXBEL!${descripcion()}'), d.address, d.port);
        }
      });
    } catch (_) {
      // Sin búsqueda automática; se puede escribir la dirección a mano.
    }
  }

  Future<void> detener() async {
    await _http?.close(force: true);
    _http = null;
    _udp?.close();
    _udp = null;
  }

  Future<void> _atender(HttpRequest req) async {
    Map<String, Object?> resp;
    try {
      final m = jsonDecode(await utf8.decodeStream(req)) as Map;
      if (m['clave'] != clave) {
        resp = {'ok': false, 'clave': true, 'error': 'La clave de red no coincide con la de la caja principal.'};
      } else {
        resp = {'ok': true, 'r': await _operar(m['op'] as String, Map<String, Object?>.from((m['a'] as Map?) ?? {}), m['tx'] as String?)};
      }
    } catch (e) {
      resp = {'ok': false, 'error': '$e'};
    }
    req.response.headers.contentType = ContentType.json;
    req.response.add(utf8.encode(jsonEncode(resp)));
    await req.response.close();
  }

  Future<Object?> _operar(String op, Map<String, Object?> a, String? tx) async {
    switch (op) {
      case 'ping':
        return {'tienda': descripcion(), 'ok': true};
      case 'begin':
        return _empezar();
      case 'commit':
      case 'rollback':
        final s = _sesiones[tx];
        if (s == null) throw StateError('La operación tardó demasiado y se canceló. Inténtalo de nuevo.');
        return s.mandar(op, a);
    }
    if (tx != null) {
      final s = _sesiones[tx];
      if (s == null) throw StateError('La operación tardó demasiado y se canceló. Inténtalo de nuevo.');
      return s.mandar(op, a);
    }
    return ejecutar(db, op, a);
  }

  Future<String> _empezar() async {
    final id = nuevoId();
    final s = _Sesion();
    _sesiones[id] = s;
    final lista = Completer<void>();
    unawaited(db.transaction((txn) async {
      lista.complete();
      s.vigilar();
      await for (final o in s.ordenes.stream) {
        s.vigilar();
        if (o.op == 'commit') {
          o.c.complete(true);
          return;
        }
        if (o.op == 'rollback') {
          o.c.complete(true);
          throw _Deshacer();
        }
        try {
          o.c.complete(await ejecutar(txn, o.op, o.a));
        } catch (e) {
          o.c.completeError(e);
        }
      }
    }).catchError((Object _) {}).whenComplete(() {
      _sesiones.remove(id);
      s.cerrar();
    }));
    await lista.future;
    return id;
  }
}

class _Deshacer implements Exception {}

class _Orden {
  _Orden(this.op, this.a);
  final String op;
  final Map<String, Object?> a;
  final c = Completer<Object?>();
}

class _Sesion {
  final ordenes = StreamController<_Orden>();
  Timer? _limite;

  /// Si la otra caja deja de responder 30 s, se deshace lo que iba.
  void vigilar() {
    _limite?.cancel();
    _limite = Timer(const Duration(seconds: 30), () {
      if (!ordenes.isClosed) ordenes.add(_Orden('rollback', const {}));
    });
  }

  Future<Object?> mandar(String op, Map<String, Object?> a) {
    final o = _Orden(op, a);
    ordenes.add(o);
    return o.c.future;
  }

  void cerrar() {
    _limite?.cancel();
    if (!ordenes.isClosed) ordenes.close();
  }
}

List<Object?>? _lista(Object? x) => (x as List?)?.cast<Object?>();

/// Ejecuta en la base de la principal lo que pidió otra caja.
Future<Object?> ejecutar(DatabaseExecutor ex, String op, Map<String, Object?> a) async {
  ConflictAlgorithm? conflicto() => a['conflict'] == null ? null : ConflictAlgorithm.values[a['conflict'] as int];
  switch (op) {
    case 'query':
      return ex.query(a['table'] as String,
          distinct: a['distinct'] as bool?,
          columns: (a['columns'] as List?)?.cast<String>(),
          where: a['where'] as String?,
          whereArgs: _lista(a['whereArgs']),
          groupBy: a['groupBy'] as String?,
          having: a['having'] as String?,
          orderBy: a['orderBy'] as String?,
          limit: a['limit'] as int?,
          offset: a['offset'] as int?);
    case 'rawQuery':
      return ex.rawQuery(a['sql'] as String, _lista(a['args']));
    case 'insert':
      return ex.insert(a['table'] as String, Map<String, Object?>.from(a['values'] as Map), conflictAlgorithm: conflicto());
    case 'update':
      return ex.update(a['table'] as String, Map<String, Object?>.from(a['values'] as Map),
          where: a['where'] as String?, whereArgs: _lista(a['whereArgs']), conflictAlgorithm: conflicto());
    case 'delete':
      return ex.delete(a['table'] as String, where: a['where'] as String?, whereArgs: _lista(a['whereArgs']));
    case 'rawInsert':
      return ex.rawInsert(a['sql'] as String, _lista(a['args']));
    case 'rawUpdate':
      return ex.rawUpdate(a['sql'] as String, _lista(a['args']));
    case 'rawDelete':
      return ex.rawDelete(a['sql'] as String, _lista(a['args']));
    case 'execute':
      await ex.execute(a['sql'] as String, _lista(a['args']));
      return null;
  }
  throw UnsupportedError('Operación desconocida: $op');
}

/// Servidor activo en esta computadora (si es la caja principal).
ServidorCaja? servidorCaja;
