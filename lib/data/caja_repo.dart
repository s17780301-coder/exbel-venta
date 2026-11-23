import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/db.dart';
import '../core/errores.dart';
import '../core/ids.dart';
import '../models/modelos.dart';

class CajaRepo {
  CajaRepo(this.db);
  final Database db;

  static const _selectTurno = '''
    SELECT t.*, c.nombre AS cajero_nombre FROM turnos t
    LEFT JOIN cajeros c ON c.id = t.cajero_id''';

  /// El turno abierto de esta caja (hay uno a la vez).
  Future<Turno?> turnoAbierto() async {
    final f = await db.rawQuery("$_selectTurno WHERE t.estado = 'abierto' ORDER BY t.abierto DESC LIMIT 1");
    return f.isEmpty ? null : Turno.desdeMapa(f.first);
  }

  Future<Turno> abrirTurno(String cajeroId, int fondoCentavos) async {
    if (await turnoAbierto() != null) throw const ErrorNegocio('Ya hay un turno abierto.');
    if (fondoCentavos < 0) throw const ErrorNegocio('El fondo no puede ser negativo.');
    final id = nuevoId();
    await db.transaction((tx) async {
      await guardarFila(tx, 'turnos', {
        'id': id,
        'numero': await siguienteNumero(tx, 'turnos', 'numero'),
        'cajero_id': cajeroId,
        'abierto': ahoraLocal(),
        'fondo_centavos': fondoCentavos,
        'estado': 'abierto',
      });
    });
    final f = await db.rawQuery('$_selectTurno WHERE t.id = ?', [id]);
    return Turno.desdeMapa(f.first);
  }

  /// Cierra el turno con lo que se contó en la caja. Regresa la diferencia
  /// (positiva = sobrante, negativa = faltante).
  Future<int> cerrarTurno(String turnoId, int contadoCentavos) async {
    final corte = await corteTurno(turnoId);
    await db.update(
        'turnos',
        {
          'cerrado': ahoraLocal(),
          'contado_centavos': contadoCentavos,
          'esperado_centavos': corte.esperadoCentavos,
          'estado': 'cerrado',
          'actualizado': ahoraUtc(),
          'sincronizado': 0,
        },
        where: 'id = ?',
        whereArgs: [turnoId]);
    return contadoCentavos - corte.esperadoCentavos;
  }

  Future<List<Turno>> turnos({DateTime? desde, DateTime? hasta}) async {
    final where = <String>['1 = 1'];
    final args = <Object?>[];
    if (desde != null) {
      where.add('t.abierto >= ?');
      args.add(desde.toIso8601String());
    }
    if (hasta != null) {
      where.add('t.abierto < ?');
      args.add(hasta.toIso8601String());
    }
    final f = await db.rawQuery('$_selectTurno WHERE ${where.join(' AND ')} ORDER BY t.abierto DESC', args);
    return f.map(Turno.desdeMapa).toList();
  }

  // ---------------- Entradas y salidas de efectivo ----------------

  Future<void> registrarMovimiento(String turnoId, String tipo, int montoCentavos, String concepto) async {
    if (montoCentavos <= 0) throw const ErrorNegocio('Escribe una cantidad mayor a cero.');
    if (tipo == 'salida') {
      final esperado = (await corteTurno(turnoId)).esperadoCentavos;
      if (montoCentavos > esperado) {
        throw ErrorNegocio('No hay suficiente efectivo en la caja (hay ${(esperado / 100).toStringAsFixed(2)}).');
      }
    }
    await guardarFila(db, 'movimientos_caja', {
      'id': nuevoId(),
      'turno_id': turnoId,
      'fecha': ahoraLocal(),
      'tipo': tipo,
      'monto_centavos': montoCentavos,
      'concepto': concepto.trim(),
      'cancelado': 0,
    });
  }

  Future<List<MovimientoCaja>> movimientosCaja(List<String> turnoIds) async {
    if (turnoIds.isEmpty) return [];
    final f = await db.query('movimientos_caja',
        where: 'turno_id IN (${List.filled(turnoIds.length, '?').join(',')})',
        whereArgs: turnoIds,
        orderBy: 'fecha DESC');
    return f.map(MovimientoCaja.desdeMapa).toList();
  }

  // ---------------- Cortes ----------------

  Future<Corte> corteTurno(String turnoId) async {
    final f = await db.rawQuery('$_selectTurno WHERE t.id = ?', [turnoId]);
    if (f.isEmpty) throw const ErrorNegocio('No se encontró el turno.');
    final t = Turno.desdeMapa(f.first);
    return _corte([turnoId], t.fondoCentavos, 'Turno ${t.numero} · ${t.cajeroNombre ?? ''}', turno: t);
  }

  /// Todos los turnos que se abrieron ese día.
  Future<Corte> corteDia(DateTime dia) async {
    final inicio = DateTime(dia.year, dia.month, dia.day);
    final ts = await turnos(desde: inicio, hasta: inicio.add(const Duration(days: 1)));
    final fondo = ts.fold<int>(0, (s, t) => s + t.fondoCentavos);
    return _corte(ts.map((t) => t.id).toList(), fondo, 'Corte del día');
  }

  Future<Corte> _corte(List<String> turnoIds, int fondo, String titulo, {Turno? turno}) async {
    final enT = turnoIds.isEmpty ? "('')" : '(${List.filled(turnoIds.length, '?').join(',')})';
    final a = turnoIds;

    final v = (await db.rawQuery('''
      SELECT COUNT(*) AS n,
             COALESCE(SUM(total_centavos), 0) AS total,
             COALESCE(SUM(efectivo_centavos), 0) AS efectivo,
             COALESCE(SUM(tarjeta_centavos), 0) AS tarjeta,
             COALESCE(SUM(transferencia_centavos), 0) AS transferencia,
             COALESCE(SUM(vales_centavos), 0) AS vales,
             COALESCE(SUM(dolares_centavos), 0) AS dolares,
             COALESCE(SUM(credito_centavos), 0) AS credito
      FROM ventas WHERE turno_id IN $enT''', a)).first;

    // Renglones con su parte no devuelta.
    final det = await db.rawQuery('''
      SELECT d.cantidad, d.devuelto, d.importe_centavos, d.costo_centavos, d.iva, d.ieps,
             COALESCE(dep.nombre, 'Sin departamento') AS departamento
      FROM venta_detalle d JOIN ventas v ON v.id = d.venta_id
      LEFT JOIN departamentos dep ON dep.id = d.departamento_id
      WHERE v.turno_id IN $enT''', a);
    var ganancia = 0, iva = 0, ieps = 0;
    final porDep = <String, (int, int)>{};
    for (final d in det) {
      final cant = (d['cantidad'] as num).toDouble();
      final queda = cant - (d['devuelto'] as num).toDouble();
      if (cant <= 0 || queda <= 0) continue;
      final factor = queda / cant;
      final importe = ((d['importe_centavos'] as int) * factor).round();
      final costo = ((d['costo_centavos'] as int) * queda).round();
      final g = importe - costo;
      ganancia += g;
      final (i1, i2) = desgloseImpuestos(importe, (d['iva'] as num).toDouble(), (d['ieps'] as num).toDouble());
      iva += i1;
      ieps += i2;
      final dep = d['departamento'] as String;
      final prev = porDep[dep] ?? (0, 0);
      porDep[dep] = (prev.$1 + importe, prev.$2 + g);
    }

    final ab = (await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN forma_pago = 'efectivo' THEN monto_centavos ELSE 0 END), 0) AS ef,
             COALESCE(SUM(CASE WHEN forma_pago <> 'efectivo' THEN monto_centavos ELSE 0 END), 0) AS otros
      FROM abonos WHERE cancelado = 0 AND turno_id IN $enT''', a)).first;

    final mc = (await db.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN tipo = 'entrada' THEN monto_centavos ELSE 0 END), 0) AS ent,
             COALESCE(SUM(CASE WHEN tipo = 'salida' THEN monto_centavos ELSE 0 END), 0) AS sal
      FROM movimientos_caja WHERE cancelado = 0 AND turno_id IN $enT''', a)).first;

    final dv = (await db.rawQuery('''
      SELECT COALESCE(SUM(total_centavos), 0) AS total, COALESCE(SUM(efectivo_centavos), 0) AS ef
      FROM devoluciones WHERE turno_id IN $enT''', a)).first;

    final deps = porDep.entries.map((e) => (e.key, e.value.$1, e.value.$2)).toList()
      ..sort((x, y) => y.$2.compareTo(x.$2));

    return Corte(
      titulo: titulo,
      turno: turno,
      fondoCentavos: fondo,
      ventasCentavos: v['total'] as int,
      numeroVentas: v['n'] as int,
      gananciaCentavos: ganancia,
      efectivoCentavos: v['efectivo'] as int,
      tarjetaCentavos: v['tarjeta'] as int,
      transferenciaCentavos: v['transferencia'] as int,
      valesCentavos: v['vales'] as int,
      dolaresCentavos: v['dolares'] as int,
      creditoCentavos: v['credito'] as int,
      abonosEfectivoCentavos: ab['ef'] as int,
      abonosOtrosCentavos: ab['otros'] as int,
      entradasCentavos: mc['ent'] as int,
      salidasCentavos: mc['sal'] as int,
      devolucionesCentavos: dv['total'] as int,
      devolucionesEfectivoCentavos: dv['ef'] as int,
      ivaCentavos: iva,
      iepsCentavos: ieps,
      porDepartamento: deps,
    );
  }
}
