import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/db.dart';
import '../core/errores.dart';
import '../core/ids.dart';
import '../models/modelos.dart';

class CajerosRepo {
  CajerosRepo(this.db);
  final Database db;

  static String _hash(String id, String clave) =>
      sha256.convert(utf8.encode('exbel:$id:$clave')).toString();

  Future<bool> hayCajeros() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM cajeros')).first['n'] as int > 0;

  Future<List<Cajero>> listar({bool soloActivos = true}) async {
    final f = await db.query('cajeros',
        where: soloActivos ? 'activo = 1' : null, orderBy: 'administrador DESC, nombre');
    return f.map(Cajero.desdeMapa).toList();
  }

  Future<Cajero> guardar({
    String? id,
    required String usuario,
    required String nombre,
    String? clave,
    bool administrador = false,
    Set<String> permisos = const {},
  }) async {
    usuario = usuario.trim().toLowerCase();
    if (usuario.isEmpty || nombre.trim().isEmpty) {
      throw const ErrorNegocio('Escribe el usuario y el nombre del cajero.');
    }
    final repetido = await db.query('cajeros',
        where: 'usuario = ? AND activo = 1 AND id <> ?', whereArgs: [usuario, id ?? '']);
    if (repetido.isNotEmpty) throw ErrorNegocio('Ya hay un cajero con el usuario "$usuario".');
    final nuevo = id == null;
    if (nuevo && (clave == null || clave.isEmpty)) {
      throw const ErrorNegocio('Ponle una contraseña al cajero.');
    }
    final cid = id ?? nuevoId();
    if (!administrador && !nuevo) {
      final admins = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM cajeros WHERE administrador = 1 AND activo = 1 AND id <> ?',
          [cid]);
      if ((admins.first['n'] as int) == 0) {
        throw const ErrorNegocio('Debe quedar al menos un administrador.');
      }
    }
    final valores = <String, Object?>{
      'id': cid,
      'usuario': usuario,
      'nombre': nombre.trim(),
      'administrador': administrador ? 1 : 0,
      'permisos': permisos.join(','),
      'activo': 1,
    };
    if (clave != null && clave.isNotEmpty) {
      valores['clave_hash'] = _hash(cid, clave);
    } else {
      final f = await db.query('cajeros', columns: ['clave_hash'], where: 'id = ?', whereArgs: [cid]);
      valores['clave_hash'] = f.first['clave_hash'];
    }
    await guardarFila(db, 'cajeros', valores);
    return Cajero.desdeMapa(valores);
  }

  Future<void> eliminar(String id) async {
    final f = await db.query('cajeros', where: 'id = ?', whereArgs: [id]);
    if (f.isEmpty) return;
    if (f.first['administrador'] == 1) {
      final admins = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM cajeros WHERE administrador = 1 AND activo = 1');
      if ((admins.first['n'] as int) <= 1) {
        throw const ErrorNegocio('No se puede eliminar al único administrador.');
      }
    }
    await db.update('cajeros', {'activo': 0, 'actualizado': ahoraUtc(), 'sincronizado': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Regresa el cajero si el usuario y la contraseña son correctos.
  Future<Cajero?> entrar(String usuario, String clave) async {
    final f = await db.query('cajeros',
        where: 'usuario = ? AND activo = 1', whereArgs: [usuario.trim().toLowerCase()]);
    if (f.isEmpty) return null;
    final c = f.first;
    if (c['clave_hash'] != _hash(c['id'] as String, clave)) return null;
    return Cajero.desdeMapa(c);
  }

  /// Para autorizar una acción con la clave de un supervisor.
  Future<Cajero?> autorizar(String clave, String permiso) async {
    for (final f in await db.query('cajeros', where: 'activo = 1')) {
      if (f['clave_hash'] == _hash(f['id'] as String, clave)) {
        final c = Cajero.desdeMapa(f);
        if (c.puede(permiso)) return c;
      }
    }
    return null;
  }
}
