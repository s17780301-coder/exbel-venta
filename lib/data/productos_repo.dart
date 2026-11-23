import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/db.dart';
import '../core/errores.dart';
import '../core/ids.dart';
import '../models/modelos.dart';

class MovimientoInventario {
  MovimientoInventario({required this.fecha, required this.producto, required this.tipo,
      required this.habia, required this.cantidad, required this.hay, required this.descripcion,
      this.cajero, this.costoCentavos = 0});
  final DateTime fecha;
  final String producto;
  final String tipo;
  final double habia;
  final double cantidad;
  final double hay;
  final String descripcion;
  final String? cajero;
  final int costoCentavos;
}

const _selectProducto = '''
  SELECT p.*, d.nombre AS departamento_nombre
  FROM productos p LEFT JOIN departamentos d ON d.id = p.departamento_id''';

class ProductosRepo {
  ProductosRepo(this.db);
  final Database db;

  // ---------------- Departamentos ----------------

  Future<List<Departamento>> departamentos() async =>
      (await db.query('departamentos', orderBy: 'nombre')).map(Departamento.desdeMapa).toList();

  Future<Departamento> guardarDepartamento({String? id, required String nombre}) async {
    nombre = nombre.trim();
    if (nombre.isEmpty) throw const ErrorNegocio('Escribe el nombre del departamento.');
    final rep = await db.query('departamentos',
        where: 'LOWER(nombre) = LOWER(?) AND id <> ?', whereArgs: [nombre, id ?? '']);
    if (rep.isNotEmpty) throw ErrorNegocio('Ya existe el departamento "$nombre".');
    final d = Departamento(id: id ?? nuevoId(), nombre: nombre);
    await guardarFila(db, 'departamentos', {'id': d.id, 'nombre': d.nombre});
    return d;
  }

  Future<void> eliminarDepartamento(String id) async {
    await db.transaction((tx) async {
      await tx.update('productos', {'departamento_id': null, 'actualizado': ahoraUtc(), 'sincronizado': 0},
          where: 'departamento_id = ?', whereArgs: [id]);
      await tx.delete('departamentos', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------- Productos ----------------

  Future<Producto?> porId(String id) async {
    final f = await db.rawQuery('$_selectProducto WHERE p.id = ?', [id]);
    return f.isEmpty ? null : Producto.desdeMapa(f.first);
  }

  /// Busca por código exacto (lector de código de barras).
  Future<Producto?> porCodigo(String codigo) async {
    codigo = codigo.trim();
    if (codigo.isEmpty) return null;
    final f = await db.rawQuery(
        '$_selectProducto WHERE p.activo = 1 AND p.codigo = ? COLLATE NOCASE LIMIT 1', [codigo]);
    return f.isEmpty ? null : Producto.desdeMapa(f.first);
  }

  /// Busca por descripción o código. Todas las palabras deben aparecer;
  /// con `%` al inicio busca en cualquier parte (como Eleventa).
  Future<List<Producto>> buscar(String texto,
      {String? departamentoId, bool soloBajos = false, bool soloFavoritos = false, int limite = 300}) async {
    final where = <String>['p.activo = 1'];
    final args = <Object?>[];
    final palabras = texto.trim().replaceAll('%', ' ').split(RegExp(r'\s+')).where((x) => x.isNotEmpty);
    for (final w in palabras) {
      where.add('(p.descripcion LIKE ? OR p.codigo LIKE ?)');
      args..add('%$w%')..add('$w%');
    }
    if (departamentoId != null) {
      where.add('p.departamento_id = ?');
      args.add(departamentoId);
    }
    if (soloBajos) where.add('p.usa_inventario = 1 AND p.minimo > 0 AND p.existencia <= p.minimo');
    if (soloFavoritos) where.add('p.favorito = 1');
    final f = await db.rawQuery(
        '$_selectProducto WHERE ${where.join(' AND ')} ORDER BY p.descripcion LIMIT $limite', args);
    return f.map(Producto.desdeMapa).toList();
  }

  Future<int> contar() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM productos WHERE activo = 1')).first['n'] as int;

  /// Guarda el producto. La existencia inicial (solo al crearlo) entra como
  /// movimiento de inventario.
  Future<Producto> guardar(Producto p, {double existenciaInicial = 0, String? cajeroId}) async {
    if (p.descripcion.trim().isEmpty) throw const ErrorNegocio('Escribe la descripción del producto.');
    if (p.precioCentavos <= 0 && !p.esKit) throw const ErrorNegocio('Escribe el precio de venta.');
    if (p.codigo.trim().isNotEmpty) {
      final rep = await db.query('productos',
          where: 'codigo = ? COLLATE NOCASE AND activo = 1 AND id <> ?', whereArgs: [p.codigo.trim(), p.id]);
      if (rep.isNotEmpty) {
        throw ErrorNegocio('El código ${p.codigo} ya es de "${rep.first['descripcion']}".');
      }
    }
    if (p.tieneMayoreo && p.mayoreoCentavos >= p.precioCentavos) {
      throw const ErrorNegocio('El precio de mayoreo debe ser menor al precio normal.');
    }
    final nuevo = (await db.query('productos', where: 'id = ?', whereArgs: [p.id])).isEmpty;
    await db.transaction((tx) async {
      final m = p.aMapa();
      if (nuevo) m['existencia'] = 0.0;
      await guardarFila(tx, 'productos', m);
      if (nuevo && existenciaInicial != 0) {
        await moverInventario(tx,
            productoId: p.id,
            cantidad: existenciaInicial,
            tipo: 'Inicial',
            descripcion: 'Existencia inicial',
            costoCentavos: p.costoCentavos,
            cajeroId: cajeroId);
      }
    });
    return (await porId(p.id))!;
  }

  /// Los productos no se borran (tienen ventas); se dan de baja.
  Future<void> eliminar(String id) async {
    await db.update('productos', {'activo': 0, 'actualizado': ahoraUtc(), 'sincronizado': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> marcarFavorito(String id, bool favorito) async {
    await db.update('productos', {'favorito': favorito ? 1 : 0, 'actualizado': ahoraUtc(), 'sincronizado': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Cambia los precios de varios productos a la vez: por porcentaje sobre
  /// el precio actual o recalculando con una ganancia sobre el costo.
  Future<int> cambiarPrecios(List<String> ids, {double? porcentaje, double? gananciaSobreCosto}) async {
    var n = 0;
    await db.transaction((tx) async {
      for (final id in ids) {
        final f = await tx.query('productos', where: 'id = ?', whereArgs: [id]);
        if (f.isEmpty) continue;
        final precio = f.first['precio_centavos'] as int;
        final costo = f.first['costo_centavos'] as int;
        int nuevo;
        if (porcentaje != null) {
          nuevo = (precio * (1 + porcentaje / 100)).round();
        } else if (gananciaSobreCosto != null && costo > 0) {
          nuevo = (costo * (1 + gananciaSobreCosto / 100)).round();
        } else {
          continue;
        }
        await tx.update('productos', {'precio_centavos': nuevo, 'actualizado': ahoraUtc(), 'sincronizado': 0},
            where: 'id = ?', whereArgs: [id]);
        n++;
      }
    });
    return n;
  }

  // ---------------- Kits ----------------

  Future<List<Componente>> componentes(String kitId) async {
    final f = await db.rawQuery('''
      SELECT k.producto_id, k.cantidad, p.descripcion, p.precio_centavos
      FROM kit_componentes k JOIN productos p ON p.id = k.producto_id
      WHERE k.kit_id = ? ORDER BY p.descripcion''', [kitId]);
    return f
        .map((m) => Componente(
              productoId: m['producto_id'] as String,
              descripcion: m['descripcion'] as String,
              cantidad: (m['cantidad'] as num).toDouble(),
              precioCentavos: m['precio_centavos'] as int,
            ))
        .toList();
  }

  Future<void> guardarComponentes(String kitId, List<Componente> lista) async {
    if (lista.any((c) => c.productoId == kitId)) {
      throw const ErrorNegocio('Un paquete no puede contenerse a sí mismo.');
    }
    await db.transaction((tx) async {
      await tx.delete('kit_componentes', where: 'kit_id = ?', whereArgs: [kitId]);
      for (final c in lista) {
        await tx.insert('kit_componentes',
            {'kit_id': kitId, 'producto_id': c.productoId, 'cantidad': c.cantidad});
      }
    });
  }

  // ---------------- Promociones ----------------

  Future<List<Promocion>> promociones({bool soloActivas = false}) async {
    final f = await db.query('promociones', where: soloActivas ? 'activa = 1' : null, orderBy: 'nombre');
    return f.map(Promocion.desdeMapa).toList();
  }

  Future<Promocion?> promocionDe(String productoId) async {
    final f = await db.query('promociones',
        where: 'producto_id = ? AND activa = 1', whereArgs: [productoId], limit: 1);
    return f.isEmpty ? null : Promocion.desdeMapa(f.first);
  }

  Future<void> guardarPromocion(Promocion p) async {
    if (p.cantidad < 2) throw const ErrorNegocio('La promoción debe ser de 2 piezas o más.');
    if (p.precioCentavos <= 0) throw const ErrorNegocio('Escribe el precio de la promoción.');
    await db.transaction((tx) async {
      if (p.activa) {
        await tx.update('promociones', {'activa': 0, 'actualizado': ahoraUtc(), 'sincronizado': 0},
            where: 'producto_id = ? AND id <> ?', whereArgs: [p.productoId, p.id]);
      }
      await guardarFila(tx, 'promociones', {
        'id': p.id,
        'producto_id': p.productoId,
        'nombre': p.nombre,
        'cantidad': p.cantidad,
        'precio_centavos': p.precioCentavos,
        'activa': p.activa ? 1 : 0,
      });
    });
  }

  Future<void> eliminarPromocion(String id) => db.delete('promociones', where: 'id = ?', whereArgs: [id]);

  // ---------------- Inventario ----------------

  /// Entrada de mercancía. Actualiza el costo (último o promedio) y, si se
  /// indica, el precio de venta.
  Future<void> agregarInventario(String productoId, double cantidad,
      {int? costoCentavos, int? nuevoPrecioCentavos, bool costoPromedio = false, String? cajeroId}) async {
    if (cantidad <= 0) throw const ErrorNegocio('La cantidad debe ser mayor a cero.');
    await db.transaction((tx) async {
      final f = await tx.query('productos', where: 'id = ?', whereArgs: [productoId]);
      if (f.isEmpty) throw const ErrorNegocio('No se encontró el producto.');
      if (f.first['usa_inventario'] != 1) {
        throw const ErrorNegocio('Este producto no usa inventario. Actívalo en el producto.');
      }
      final cambios = <String, Object?>{};
      if (costoCentavos != null && costoCentavos > 0) {
        final antes = f.first['costo_centavos'] as int;
        final exist = (f.first['existencia'] as num).toDouble();
        cambios['costo_centavos'] = costoPromedio && exist > 0 && antes > 0
            ? ((antes * exist + costoCentavos * cantidad) / (exist + cantidad)).round()
            : costoCentavos;
      }
      if (nuevoPrecioCentavos != null && nuevoPrecioCentavos > 0) cambios['precio_centavos'] = nuevoPrecioCentavos;
      if (cambios.isNotEmpty) {
        await tx.update('productos', {...cambios, 'actualizado': ahoraUtc(), 'sincronizado': 0},
            where: 'id = ?', whereArgs: [productoId]);
      }
      await moverInventario(tx,
          productoId: productoId,
          cantidad: cantidad,
          tipo: 'Entrada',
          descripcion: 'Entrada de mercancía',
          costoCentavos: costoCentavos ?? (f.first['costo_centavos'] as int),
          cajeroId: cajeroId);
    });
  }

  /// Ajuste por conteo físico: deja la existencia en `nuevaExistencia`.
  Future<void> ajustarInventario(String productoId, double nuevaExistencia,
      {String motivo = 'Ajuste', String? cajeroId}) async {
    await db.transaction((tx) async {
      final f = await tx.query('productos', where: 'id = ?', whereArgs: [productoId]);
      if (f.isEmpty) throw const ErrorNegocio('No se encontró el producto.');
      final actual = (f.first['existencia'] as num).toDouble();
      await moverInventario(tx,
          productoId: productoId,
          cantidad: nuevaExistencia - actual,
          tipo: 'Ajuste',
          descripcion: motivo,
          costoCentavos: f.first['costo_centavos'] as int,
          cajeroId: cajeroId);
    });
  }

  /// Salida sin venta: merma, caducado, consumo propio.
  Future<void> salidaInventario(String productoId, double cantidad,
      {String motivo = 'Merma', String? cajeroId}) async {
    if (cantidad <= 0) throw const ErrorNegocio('La cantidad debe ser mayor a cero.');
    await db.transaction((tx) async {
      final f = await tx.query('productos', columns: ['costo_centavos'], where: 'id = ?', whereArgs: [productoId]);
      await moverInventario(tx,
          productoId: productoId,
          cantidad: -cantidad,
          tipo: 'Salida',
          descripcion: motivo,
          costoCentavos: f.isEmpty ? 0 : f.first['costo_centavos'] as int,
          cajeroId: cajeroId);
    });
  }

  Future<List<MovimientoInventario>> movimientos(
      {String? productoId, DateTime? desde, DateTime? hasta, String? tipo, int limite = 1000}) async {
    final where = <String>['1 = 1'];
    final args = <Object?>[];
    if (productoId != null) {
      where.add('m.producto_id = ?');
      args.add(productoId);
    }
    if (desde != null) {
      where.add('m.fecha >= ?');
      args.add(desde.toIso8601String());
    }
    if (hasta != null) {
      where.add('m.fecha < ?');
      args.add(hasta.toIso8601String());
    }
    if (tipo != null) {
      where.add('m.tipo = ?');
      args.add(tipo);
    }
    final f = await db.rawQuery('''
      SELECT m.*, p.descripcion AS producto, c.nombre AS cajero
      FROM movimientos_inventario m
      JOIN productos p ON p.id = m.producto_id
      LEFT JOIN cajeros c ON c.id = m.cajero_id
      WHERE ${where.join(' AND ')}
      ORDER BY m.fecha DESC LIMIT $limite''', args);
    return f
        .map((m) => MovimientoInventario(
              fecha: DateTime.parse(m['fecha'] as String),
              producto: m['producto'] as String,
              tipo: m['tipo'] as String,
              habia: (m['habia'] as num).toDouble(),
              cantidad: (m['cantidad'] as num).toDouble(),
              hay: (m['hay'] as num).toDouble(),
              descripcion: m['descripcion'] as String,
              cajero: m['cajero'] as String?,
              costoCentavos: m['costo_centavos'] as int,
            ))
        .toList();
  }

  /// (piezas, costo del inventario, valor a precio de venta)
  Future<(double, int, int)> valorInventario({String? departamentoId}) async {
    final f = await db.rawQuery('''
      SELECT COALESCE(SUM(existencia), 0) AS piezas,
             COALESCE(SUM(existencia * costo_centavos), 0) AS costo,
             COALESCE(SUM(existencia * precio_centavos), 0) AS venta
      FROM productos
      WHERE activo = 1 AND usa_inventario = 1 AND existencia > 0
      ${departamentoId == null ? '' : 'AND departamento_id = ?'}''',
        [if (departamentoId != null) departamentoId]);
    final m = f.first;
    return ((m['piezas'] as num).toDouble(), (m['costo'] as num).round(), (m['venta'] as num).round());
  }
}
