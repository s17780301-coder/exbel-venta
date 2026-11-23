import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/db.dart';
import '../core/errores.dart';
import '../core/formato.dart';
import '../core/ids.dart';
import '../models/modelos.dart';

const _selectVenta = '''
  SELECT v.*, c.nombre AS cajero_nombre, cl.nombre AS cliente_nombre,
    (SELECT COALESCE(SUM(d.cantidad), 0) FROM venta_detalle d WHERE d.venta_id = v.id) AS articulos
  FROM ventas v
  LEFT JOIN cajeros c ON c.id = v.cajero_id
  LEFT JOIN clientes cl ON cl.id = v.cliente_id''';

class VentasRepo {
  VentasRepo(this.db);
  final Database db;

  /// Registra la venta, descuenta el inventario y carga el crédito al
  /// cliente. Todo o nada.
  Future<Venta> registrar({
    required List<Renglon> renglones,
    required Pago pago,
    required String turnoId,
    required String cajeroId,
    Cliente? cliente,
    String notas = '',
  }) async {
    final validos = renglones.where((r) => r.cantidad > 0).toList();
    if (validos.isEmpty) throw const ErrorNegocio('La venta no tiene artículos.');
    final total = validos.fold<int>(0, (s, r) => s + r.importeCentavos);
    if (pago.totalCentavos != total) {
      throw ErrorNegocio('El pago (${formatoPesos(pago.totalCentavos)}) no cuadra con el total (${formatoPesos(total)}).');
    }
    if (pago.creditoCentavos > 0 && cliente == null) {
      throw const ErrorNegocio('Para vender a crédito elige un cliente.');
    }

    final id = nuevoId();
    late int folio;
    await db.transaction((tx) async {
      if (cliente != null && pago.creditoCentavos > 0) {
        final c = await tx.query('clientes', where: 'id = ?', whereArgs: [cliente.id]);
        if (c.isEmpty) throw const ErrorNegocio('No se encontró el cliente.');
        final saldo = c.first['saldo_centavos'] as int;
        final limite = c.first['limite_centavos'] as int;
        if (limite > 0 && saldo + pago.creditoCentavos > limite) {
          throw ErrorNegocio('${cliente.nombre} excede su límite de crédito '
              '(${formatoPesos(limite)}). Debe ${formatoPesos(saldo)}.');
        }
      }
      folio = await siguienteNumero(tx, 'ventas', 'folio');
      await guardarFila(tx, 'ventas', {
        'id': id,
        'folio': folio,
        'fecha': ahoraLocal(),
        'turno_id': turnoId,
        'cajero_id': cajeroId,
        'cliente_id': cliente?.id,
        'total_centavos': total,
        'efectivo_centavos': pago.efectivoCentavos,
        'tarjeta_centavos': pago.tarjetaCentavos,
        'transferencia_centavos': pago.transferenciaCentavos,
        'vales_centavos': pago.valesCentavos,
        'dolares_centavos': pago.dolaresCentavos,
        'credito_centavos': pago.creditoCentavos,
        'recibido_centavos': pago.recibidoCentavos,
        'referencia': pago.referencia,
        'notas': notas,
        'estado': 'activa',
      });
      for (final r in validos) {
        await guardarFila(tx, 'venta_detalle', {
          'id': nuevoId(),
          'venta_id': id,
          'producto_id': r.producto?.id,
          'codigo': r.codigo,
          'descripcion': r.descripcion,
          'departamento_id': r.departamentoId,
          'cantidad': r.cantidad,
          'precio_centavos': r.precioUnitarioCentavos,
          'costo_centavos': r.costoCentavos,
          'importe_centavos': r.importeCentavos,
          'iva': r.iva,
          'ieps': r.ieps,
          'mayoreo': r.conMayoreo ? 1 : 0,
          'devuelto': 0.0,
        });
        final p = r.producto;
        if (p != null) {
          await _moverProducto(tx, p.id, -r.cantidad, 'Venta', 'Venta folio $folio', cajeroId, id);
        }
      }
      if (cliente != null && pago.creditoCentavos > 0) {
        await tx.rawUpdate(
            'UPDATE clientes SET saldo_centavos = saldo_centavos + ?, actualizado = ?, sincronizado = 0 WHERE id = ?',
            [pago.creditoCentavos, ahoraUtc(), cliente.id]);
      }
    });
    return (await porId(id))!;
  }

  /// Mueve el inventario de un producto; si es paquete, el de sus componentes.
  Future<void> _moverProducto(Transaction tx, String productoId, double cantidad, String tipo,
      String descripcion, String cajeroId, String referencia) async {
    final f = await tx.query('productos',
        columns: ['tipo', 'kit_descuenta_componentes', 'costo_centavos'], where: 'id = ?', whereArgs: [productoId]);
    if (f.isEmpty) return;
    if (f.first['tipo'] == 'kit' && f.first['kit_descuenta_componentes'] == 1) {
      final comps = await tx.query('kit_componentes', where: 'kit_id = ?', whereArgs: [productoId]);
      for (final c in comps) {
        await moverInventario(tx,
            productoId: c['producto_id'] as String,
            cantidad: cantidad * (c['cantidad'] as num).toDouble(),
            tipo: tipo,
            descripcion: '$descripcion (paquete)',
            cajeroId: cajeroId,
            referenciaId: referencia);
      }
    } else {
      await moverInventario(tx,
          productoId: productoId,
          cantidad: cantidad,
          tipo: tipo,
          descripcion: descripcion,
          costoCentavos: f.first['costo_centavos'] as int,
          cajeroId: cajeroId,
          referenciaId: referencia);
    }
  }

  Future<Venta?> porId(String id) async {
    final f = await db.rawQuery('$_selectVenta WHERE v.id = ?', [id]);
    return f.isEmpty ? null : Venta.desdeMapa(f.first);
  }

  Future<Venta?> porFolio(int folio) async {
    final f = await db.rawQuery('$_selectVenta WHERE v.folio = ?', [folio]);
    return f.isEmpty ? null : Venta.desdeMapa(f.first);
  }

  Future<List<Venta>> listar({DateTime? desde, DateTime? hasta, String? cajeroId, String? turnoId,
      String? clienteId, bool soloCredito = false, String texto = '', int limite = 2000}) async {
    final where = <String>['1 = 1'];
    final args = <Object?>[];
    if (desde != null) {
      where.add('v.fecha >= ?');
      args.add(desde.toIso8601String());
    }
    if (hasta != null) {
      where.add('v.fecha < ?');
      args.add(hasta.toIso8601String());
    }
    if (cajeroId != null) {
      where.add('v.cajero_id = ?');
      args.add(cajeroId);
    }
    if (turnoId != null) {
      where.add('v.turno_id = ?');
      args.add(turnoId);
    }
    if (clienteId != null) {
      where.add('v.cliente_id = ?');
      args.add(clienteId);
    }
    if (soloCredito) where.add('v.credito_centavos > 0');
    final t = texto.trim();
    if (t.isNotEmpty) {
      where.add('(CAST(v.folio AS TEXT) = ? OR cl.nombre LIKE ? OR v.notas LIKE ?)');
      args..add(t)..add('%$t%')..add('%$t%');
    }
    final f = await db.rawQuery(
        '$_selectVenta WHERE ${where.join(' AND ')} ORDER BY v.fecha DESC LIMIT $limite', args);
    return f.map(Venta.desdeMapa).toList();
  }

  Future<List<LineaVendida>> detalle(String ventaId) async {
    final f = await db.query('venta_detalle', where: 'venta_id = ?', whereArgs: [ventaId], orderBy: 'rowid');
    return f.map(LineaVendida.desdeMapa).toList();
  }

  /// Lo que se ha devuelto de la venta: (total, a crédito).
  Future<(int, int)> devuelto(String ventaId) async {
    final f = (await db.rawQuery('''
      SELECT COALESCE(SUM(total_centavos), 0) AS t, COALESCE(SUM(credito_centavos), 0) AS c
      FROM devoluciones WHERE venta_id = ?''', [ventaId])).first;
    return (f['t'] as int, f['c'] as int);
  }

  /// Devuelve mercancía de una venta. `cantidades`: id del renglón →
  /// cantidad a devolver. Primero se descuenta del crédito pendiente de esa
  /// venta; el resto se le regresa en efectivo. Regresa el efectivo a
  /// entregar.
  Future<int> devolver({
    required String ventaId,
    required Map<String, double> cantidades,
    required String turnoId,
    required String cajeroId,
    String motivo = '',
    bool cancelar = false,
  }) async {
    var efectivo = 0;
    await db.transaction((tx) async {
      final vf = await tx.query('ventas', where: 'id = ?', whereArgs: [ventaId]);
      if (vf.isEmpty) throw const ErrorNegocio('No se encontró la venta.');
      final v = vf.first;
      if (v['estado'] == 'cancelada') throw const ErrorNegocio('Esa venta ya está cancelada.');
      final folio = v['folio'] as int;
      final lineas = await tx.query('venta_detalle', where: 'venta_id = ?', whereArgs: [ventaId]);
      var total = 0;
      final partes = <String>[];
      for (final l in lineas) {
        final lid = l['id'] as String;
        final cant = (l['cantidad'] as num).toDouble();
        final yaDev = (l['devuelto'] as num).toDouble();
        final queda = cant - yaDev;
        var dev = cancelar ? queda : (cantidades[lid] ?? 0);
        if (dev <= 0) continue;
        if (dev > queda + 1e-9) {
          throw ErrorNegocio('De "${l['descripcion']}" solo quedan ${formatoCantidad(queda)} por devolver.');
        }
        final importe = l['importe_centavos'] as int;
        // Lo que falta por devolver del renglón, para no perder centavos.
        final yaDevImporte = (importe * yaDev / cant).round();
        final hastaAhora = (importe * (yaDev + dev) / cant).round();
        total += hastaAhora - yaDevImporte;
        partes.add('${formatoCantidad(dev)} ${l['descripcion']}');
        await tx.update('venta_detalle',
            {'devuelto': yaDev + dev, 'actualizado': ahoraUtc(), 'sincronizado': 0},
            where: 'id = ?', whereArgs: [lid]);
        final pid = l['producto_id'] as String?;
        if (pid != null) {
          await _moverProducto(tx, pid, dev, cancelar ? 'Cancelación' : 'Devolución',
              '${cancelar ? 'Cancelación' : 'Devolución'} folio $folio', cajeroId, ventaId);
        }
      }
      if (total <= 0) throw const ErrorNegocio('Indica qué artículos se devuelven.');

      // Crédito aún pendiente de esta venta.
      final credito = v['credito_centavos'] as int;
      final previo = (await tx.rawQuery(
              'SELECT COALESCE(SUM(credito_centavos), 0) AS c FROM devoluciones WHERE venta_id = ?', [ventaId]))
          .first['c'] as int;
      var aCredito = 0;
      final clienteId = v['cliente_id'] as String?;
      if (clienteId != null && credito - previo > 0) {
        final saldo = (await tx.query('clientes', columns: ['saldo_centavos'], where: 'id = ?', whereArgs: [clienteId]))
            .first['saldo_centavos'] as int;
        aCredito = [total, credito - previo, saldo].reduce((a, b) => a < b ? a : b);
        if (aCredito > 0) {
          await tx.rawUpdate(
              'UPDATE clientes SET saldo_centavos = saldo_centavos - ?, actualizado = ?, sincronizado = 0 WHERE id = ?',
              [aCredito, ahoraUtc(), clienteId]);
        }
      }
      efectivo = total - aCredito;
      await guardarFila(tx, 'devoluciones', {
        'id': nuevoId(),
        'venta_id': ventaId,
        'turno_id': turnoId,
        'fecha': ahoraLocal(),
        'total_centavos': total,
        'efectivo_centavos': efectivo,
        'credito_centavos': aCredito,
        'descripcion': [if (motivo.isNotEmpty) motivo, partes.join(', ')].join(' — '),
      });
      final todo = (await tx.rawQuery(
                  'SELECT COUNT(*) AS n FROM venta_detalle WHERE venta_id = ? AND devuelto < cantidad - 0.0000001',
                  [ventaId]))
              .first['n'] ==
          0;
      if (cancelar || todo) {
        await tx.update('ventas', {'estado': 'cancelada', 'actualizado': ahoraUtc(), 'sincronizado': 0},
            where: 'id = ?', whereArgs: [ventaId]);
      } else {
        await tx.update('ventas', {'estado': 'devolucion', 'actualizado': ahoraUtc(), 'sincronizado': 0},
            where: 'id = ?', whereArgs: [ventaId]);
      }
    });
    return efectivo;
  }

  /// Cancela la venta completa: regresa la mercancía y el dinero.
  Future<int> cancelar(String ventaId, {required String turnoId, required String cajeroId, String motivo = 'Cancelación'}) =>
      devolver(ventaId: ventaId, cantidades: const {}, turnoId: turnoId, cajeroId: cajeroId, motivo: motivo, cancelar: true);
}
