import 'dart:convert';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../errores.dart';

/// Puerto de exBel venta en la red local.
const puertoRed = 7420;
const puertoDescubrir = 7421;

/// Base de datos de la CAJA PRINCIPAL vista desde una caja adicional: cada
/// consulta viaja por la red local. Los repositorios no notan la diferencia.
class DatabaseRemota with _Remoto implements Database {
  DatabaseRemota(this.host, this.clave, {this.puerto = puertoRed});
  final String host;
  final String clave;
  final int puerto;
  final _http = HttpClient()..connectionTimeout = const Duration(seconds: 5);

  @override
  DatabaseRemota get _base => this;
  @override
  String? get _tx => null;

  Future<Object?> llamar(String op, Map<String, Object?> a, {String? tx}) async {
    try {
      final req = await _http.post(host, puerto, '/rpc');
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({'clave': clave, 'op': op, 'a': a, 'tx': tx})));
      final res = await req.close().timeout(const Duration(seconds: 40));
      final cuerpo = await utf8.decodeStream(res);
      final m = jsonDecode(cuerpo) as Map;
      if (m['ok'] != true) {
        final e = (m['error'] ?? 'Error en la caja principal').toString();
        if (m['clave'] == true) throw ErrorNegocio(e);
        throw Exception(e);
      }
      return m['r'];
    } on SocketException {
      throw ErrorNegocio('No hay conexión con la caja principal ($host). Revisa que esté prendida, con exBel venta abierto '
          'y en la misma red.');
    } on HttpException {
      throw ErrorNegocio('Se perdió la conexión con la caja principal ($host).');
    }
  }

  /// Regresa el nombre de la tienda y de la caja principal.
  Future<Map<String, Object?>> ping() async => Map<String, Object?>.from((await llamar('ping', {})) as Map);

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    final id = (await llamar('begin', {})) as String;
    final tx = TransaccionRemota(this, id);
    try {
      final r = await action(tx);
      await llamar('commit', {}, tx: id);
      return r;
    } catch (_) {
      try {
        await llamar('rollback', {}, tx: id);
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> close() async => _http.close(force: true);

  @override
  bool get isOpen => true;

  @override
  String get path => 'red://$host:$puerto';

  @override
  Database get database => this;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No disponible en una caja conectada: ${invocation.memberName}');
}

class TransaccionRemota with _Remoto implements Transaction {
  TransaccionRemota(this._b, this._id);
  final DatabaseRemota _b;
  final String _id;

  @override
  DatabaseRemota get _base => _b;
  @override
  String? get _tx => _id;

  @override
  Database get database => _b;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('No disponible en una caja conectada: ${invocation.memberName}');
}

List<Map<String, Object?>> _filas(Object? r) =>
    [for (final f in (r as List)) Map<String, Object?>.from(f as Map)];

mixin _Remoto {
  DatabaseRemota get _base;
  String? get _tx;

  Future<Object?> _l(String op, Map<String, Object?> a) => _base.llamar(op, a, tx: _tx);

  Future<void> execute(String sql, [List<Object?>? arguments]) async => _l('execute', {'sql': sql, 'args': arguments});

  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async =>
      (await _l('rawInsert', {'sql': sql, 'args': arguments})) as int;

  Future<int> insert(String table, Map<String, Object?> values, {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async =>
      (await _l('insert', {'table': table, 'values': values, 'conflict': conflictAlgorithm?.index})) as int;

  Future<List<Map<String, Object?>>> query(String table,
          {bool? distinct,
          List<String>? columns,
          String? where,
          List<Object?>? whereArgs,
          String? groupBy,
          String? having,
          String? orderBy,
          int? limit,
          int? offset}) async =>
      _filas(await _l('query', {
        'table': table,
        'distinct': distinct,
        'columns': columns,
        'where': where,
        'whereArgs': whereArgs,
        'groupBy': groupBy,
        'having': having,
        'orderBy': orderBy,
        'limit': limit,
        'offset': offset,
      }));

  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async =>
      _filas(await _l('rawQuery', {'sql': sql, 'args': arguments}));

  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async =>
      (await _l('rawUpdate', {'sql': sql, 'args': arguments})) as int;

  Future<int> update(String table, Map<String, Object?> values,
          {String? where, List<Object?>? whereArgs, ConflictAlgorithm? conflictAlgorithm}) async =>
      (await _l('update', {
        'table': table,
        'values': values,
        'where': where,
        'whereArgs': whereArgs,
        'conflict': conflictAlgorithm?.index,
      })) as int;

  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async =>
      (await _l('rawDelete', {'sql': sql, 'args': arguments})) as int;

  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async =>
      (await _l('delete', {'table': table, 'where': where, 'whereArgs': whereArgs})) as int;
}

/// Busca la caja principal en la red local. Regresa (ip, descripción).
Future<List<(String, String)>> buscarCajaPrincipal({Duration espera = const Duration(seconds: 2)}) async {
  final r = <(String, String)>[];
  RawDatagramSocket? s;
  try {
    s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.broadcastEnabled = true;
    s.listen((e) {
      if (e != RawSocketEvent.read) return;
      final d = s!.receive();
      if (d == null) return;
      final t = utf8.decode(d.data, allowMalformed: true);
      if (t.startsWith('EXBEL!') && !r.any((x) => x.$1 == d.address.address)) {
        r.add((d.address.address, t.substring(6)));
      }
    });
    s.send(utf8.encode('EXBEL?'), InternetAddress('255.255.255.255'), puertoDescubrir);
    await Future<void>.delayed(espera);
  } catch (_) {
  } finally {
    s?.close();
  }
  return r;
}
