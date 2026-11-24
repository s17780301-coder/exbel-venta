import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/db.dart';
import '../core/errores.dart';
import '../core/formato.dart';
import '../core/ids.dart';
import '../models/modelos.dart';

/// Un renglón del estado de cuenta.
class MovimientoCuenta {
  MovimientoCuenta({required this.fecha, required this.concepto, required this.cargoCentavos,
      required this.abonoCentavos, this.ventaId, this.abonoId, this.cancelado = false});
  final DateTime fecha;
  final String concepto;
  final int cargoCentavos;
  final int abonoCentavos;
  final String? ventaId;
  final String? abonoId;
  final bool cancelado;
  int saldoCentavos = 0;
}

class ClientesRepo {
  ClientesRepo(this.db);
  final Database db;

  Future<List<Cliente>> buscar(String texto, {bool soloConSaldo = false}) async {
    final where = <String>['activo = 1'];
    final args = <Object?>[];
    for (final w in texto.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty)) {
      where.add('(nombre LIKE ? OR telefono LIKE ? OR CAST(numero AS TEXT) = ?)');
      args..add('%$w%')..add('%$w%')..add(w);
    }
    if (soloConSaldo) where.add('saldo_centavos > 0');
    final f = await db.query('clientes', where: where.join(' AND '), whereArgs: args, orderBy: 'nombre');
    return f.map(Cliente.desdeMapa).toList();
  }

  Future<Cliente?> porId(String id) async {
    final f = await db.query('clientes', where: 'id = ?', whereArgs: [id]);
    return f.isEmpty ? null : Cliente.desdeMapa(f.first);
  }

  Future<Cliente> guardar(Cliente c) async {
    if (c.nombre.trim().isEmpty) throw const ErrorNegocio('Escribe el nombre del cliente.');
    final existe = (await db.query('clientes', where: 'id = ?', whereArgs: [c.id])).isNotEmpty;
    await db.transaction((tx) async {
      final m = c.aMapa();
      if (!existe) {
        m['numero'] = await siguienteNumero(tx, 'clientes', 'numero');
        m['saldo_centavos'] = 0;
      } else {
        m.remove('numero');
      }
      m['nombre'] = c.nombre.trim();
      await guardarFila(tx, 'clientes', m);
    });
    return (await porId(c.id))!;
  }

  Future<void> eliminar(String id) async {
    final c = await porId(id);
    if (c == null) return;
    if (c.saldoCentavos > 0) {
      throw ErrorNegocio('${c.nombre} todavía debe ${formatoPesos(c.saldoCentavos)}. Liquida su cuenta primero.');
    }
    await db.update('clientes', {'activo': 0, 'actualizado': ahoraUtc(), 'sincronizado': 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<int> saldoTotal() async =>
      (await db.rawQuery('SELECT COALESCE(SUM(saldo_centavos), 0) AS s FROM clientes WHERE activo = 1'))
          .first['s'] as int;

  /// Deuda que el cliente ya traía (de otro sistema, o de la
  /// libreta). Se suma a su saldo y aparece en el estado de cuenta.
  Future<void> fijarSaldoAnterior(String clienteId, int montoCentavos) async {
    if (montoCentavos < 0) throw const ErrorNegocio('El saldo anterior no puede ser negativo.');
    await db.transaction((tx) async {
      final f = await tx.query('clientes', columns: ['saldo_anterior_centavos'], where: 'id = ?', whereArgs: [clienteId]);
      if (f.isEmpty) throw const ErrorNegocio('No se encontró el cliente.');
      final antes = f.first['saldo_anterior_centavos'] as int;
      await tx.rawUpdate(
          'UPDATE clientes SET saldo_anterior_centavos = ?, saldo_anterior_fecha = COALESCE(saldo_anterior_fecha, ?), '
          'saldo_centavos = saldo_centavos + ?, actualizado = ?, sincronizado = 0 WHERE id = ?',
          [montoCentavos, ahoraLocal(), montoCentavos - antes, ahoraUtc(), clienteId]);
    });
  }

  /// Recibe un abono. Si no se indica venta, se aplica a la cuenta general.
  Future<void> abonar({
    required String clienteId,
    required int montoCentavos,
    required String turnoId,
    String formaPago = 'efectivo',
    String? ventaId,
  }) async {
    if (montoCentavos <= 0) throw const ErrorNegocio('Escribe una cantidad mayor a cero.');
    await db.transaction((tx) async {
      final f = await tx.query('clientes', where: 'id = ?', whereArgs: [clienteId]);
      if (f.isEmpty) throw const ErrorNegocio('No se encontró el cliente.');
      final saldo = f.first['saldo_centavos'] as int;
      if (montoCentavos > saldo) {
        throw ErrorNegocio('El abono es mayor a lo que debe (${formatoPesos(saldo)}).');
      }
      await guardarFila(tx, 'abonos', {
        'id': nuevoId(),
        'cliente_id': clienteId,
        'turno_id': turnoId,
        'venta_id': ventaId,
        'fecha': ahoraLocal(),
        'monto_centavos': montoCentavos,
        'forma_pago': formaPago,
        'cancelado': 0,
      });
      await tx.rawUpdate(
          'UPDATE clientes SET saldo_centavos = saldo_centavos - ?, actualizado = ?, sincronizado = 0 WHERE id = ?',
          [montoCentavos, ahoraUtc(), clienteId]);
    });
  }

  /// Deshace un abono (por error de captura).
  Future<void> cancelarAbono(String abonoId) async {
    await db.transaction((tx) async {
      final f = await tx.query('abonos', where: 'id = ?', whereArgs: [abonoId]);
      if (f.isEmpty || f.first['cancelado'] == 1) return;
      await tx.update('abonos', {'cancelado': 1, 'actualizado': ahoraUtc(), 'sincronizado': 0},
          where: 'id = ?', whereArgs: [abonoId]);
      await tx.rawUpdate(
          'UPDATE clientes SET saldo_centavos = saldo_centavos + ?, actualizado = ?, sincronizado = 0 WHERE id = ?',
          [f.first['monto_centavos'], ahoraUtc(), f.first['cliente_id']]);
    });
  }

  /// Cargos (ventas a crédito, menos devoluciones) y abonos, con saldo
  /// acumulado, del más antiguo al más reciente.
  Future<List<MovimientoCuenta>> estadoDeCuenta(String clienteId) async {
    final movs = <MovimientoCuenta>[];
    final cl = await db.query('clientes',
        columns: ['saldo_anterior_centavos', 'saldo_anterior_fecha'], where: 'id = ?', whereArgs: [clienteId]);
    if (cl.isNotEmpty && (cl.first['saldo_anterior_centavos'] as int) > 0) {
      movs.add(MovimientoCuenta(
        fecha: DateTime.tryParse((cl.first['saldo_anterior_fecha'] as String?) ?? '') ?? DateTime(2000),
        concepto: 'Saldo anterior',
        cargoCentavos: cl.first['saldo_anterior_centavos'] as int,
        abonoCentavos: 0,
      ));
    }
    for (final v in await db.query('ventas',
        where: 'cliente_id = ? AND credito_centavos > 0', whereArgs: [clienteId])) {
      movs.add(MovimientoCuenta(
        fecha: DateTime.parse(v['fecha'] as String),
        concepto: 'Venta folio ${v['folio']}',
        cargoCentavos: v['credito_centavos'] as int,
        abonoCentavos: 0,
        ventaId: v['id'] as String,
      ));
    }
    for (final d in await db.rawQuery('''
        SELECT d.*, v.folio FROM devoluciones d JOIN ventas v ON v.id = d.venta_id
        WHERE v.cliente_id = ? AND d.credito_centavos > 0''', [clienteId])) {
      movs.add(MovimientoCuenta(
        fecha: DateTime.parse(d['fecha'] as String),
        concepto: 'Devolución folio ${d['folio']}',
        cargoCentavos: 0,
        abonoCentavos: d['credito_centavos'] as int,
        ventaId: d['venta_id'] as String,
      ));
    }
    for (final a in await db.query('abonos', where: 'cliente_id = ?', whereArgs: [clienteId])) {
      final cancelado = a['cancelado'] == 1;
      movs.add(MovimientoCuenta(
        fecha: DateTime.parse(a['fecha'] as String),
        concepto: 'Abono (${a['forma_pago']})${cancelado ? ' — cancelado' : ''}',
        cargoCentavos: 0,
        abonoCentavos: cancelado ? 0 : a['monto_centavos'] as int,
        abonoId: a['id'] as String,
        cancelado: cancelado,
      ));
    }
    movs.sort((a, b) => a.fecha.compareTo(b.fecha));
    var saldo = 0;
    for (final m in movs) {
      saldo += m.cargoCentavos - m.abonoCentavos;
      m.saldoCentavos = saldo;
    }
    return movs;
  }

  /// Fecha de la compra a crédito más antigua sin pagar (primeras entradas,
  /// primeras salidas), para saber cuántos días lleva debiendo.
  Future<DateTime?> deudaMasAntigua(String clienteId) async {
    final c = await porId(clienteId);
    if (c == null || c.saldoCentavos <= 0) return null;
    final cuenta = await estadoDeCuenta(clienteId);
    var pagado = cuenta.fold<int>(0, (s, m) => s + m.abonoCentavos);
    for (final m in cuenta.where((m) => m.cargoCentavos > 0)) {
      if (pagado >= m.cargoCentavos) {
        pagado -= m.cargoCentavos;
      } else {
        return m.fecha;
      }
    }
    return null;
  }
}
