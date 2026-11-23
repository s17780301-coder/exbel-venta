import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Una fila de reporte: nombre, cantidad, ventas y ganancia.
class FilaReporte {
  FilaReporte(this.nombre, this.cantidad, this.ventasCentavos, this.gananciaCentavos, {this.extra = ''});
  final String nombre;
  final double cantidad;
  final int ventasCentavos;
  final int gananciaCentavos;
  final String extra;
}

class ReportesRepo {
  ReportesRepo(this.db);
  final Database db;

  /// Parte no devuelta de cada renglón dentro del periodo.
  static const _neto = '''
    (d.importe_centavos * (d.cantidad - d.devuelto) / NULLIF(d.cantidad, 0))''';
  static const _costo = '(d.costo_centavos * (d.cantidad - d.devuelto))';

  String _rango(List<Object?> args, DateTime desde, DateTime hasta) {
    args..add(desde.toIso8601String())..add(hasta.toIso8601String());
    return 'v.fecha >= ? AND v.fecha < ?';
  }

  Future<List<FilaReporte>> _agrupar(String grupo, DateTime desde, DateTime hasta,
      {String join = '', String orden = 'ventas DESC', int limite = 1000}) async {
    final args = <Object?>[];
    final w = _rango(args, desde, hasta);
    final f = await db.rawQuery('''
      SELECT $grupo AS nombre,
             COALESCE(SUM(d.cantidad - d.devuelto), 0) AS cantidad,
             COALESCE(SUM($_neto), 0) AS ventas,
             COALESCE(SUM($_neto - $_costo), 0) AS ganancia
      FROM venta_detalle d JOIN ventas v ON v.id = d.venta_id $join
      WHERE $w AND d.cantidad > d.devuelto
      GROUP BY 1 ORDER BY $orden LIMIT $limite''', args);
    return f
        .map((m) => FilaReporte(
              (m['nombre'] ?? '—').toString(),
              (m['cantidad'] as num).toDouble(),
              (m['ventas'] as num).round(),
              (m['ganancia'] as num).round(),
            ))
        .toList();
  }

  Future<List<FilaReporte>> porDia(DateTime desde, DateTime hasta) =>
      _agrupar('substr(v.fecha, 1, 10)', desde, hasta, orden: 'nombre');

  Future<List<FilaReporte>> porHora(DateTime desde, DateTime hasta) =>
      _agrupar('substr(v.fecha, 12, 2)', desde, hasta, orden: 'nombre');

  Future<List<FilaReporte>> porProducto(DateTime desde, DateTime hasta, {String orden = 'ventas DESC'}) =>
      _agrupar('d.descripcion', desde, hasta, orden: orden);

  Future<List<FilaReporte>> porDepartamento(DateTime desde, DateTime hasta) => _agrupar(
      "COALESCE(dep.nombre, 'Sin departamento')", desde, hasta,
      join: 'LEFT JOIN departamentos dep ON dep.id = d.departamento_id');

  Future<List<FilaReporte>> porCajero(DateTime desde, DateTime hasta) =>
      _agrupar('c.nombre', desde, hasta, join: 'LEFT JOIN cajeros c ON c.id = v.cajero_id');

  Future<List<FilaReporte>> porCliente(DateTime desde, DateTime hasta) => _agrupar(
      "COALESCE(cl.nombre, 'Público en general')", desde, hasta,
      join: 'LEFT JOIN clientes cl ON cl.id = v.cliente_id');

  /// Formas de pago del periodo.
  Future<List<FilaReporte>> porFormaPago(DateTime desde, DateTime hasta) async {
    final args = <Object?>[];
    final w = _rango(args, desde, hasta);
    final m = (await db.rawQuery('''
      SELECT COALESCE(SUM(efectivo_centavos), 0) AS ef, COALESCE(SUM(tarjeta_centavos), 0) AS ta,
             COALESCE(SUM(vales_centavos), 0) AS va, COALESCE(SUM(dolares_centavos), 0) AS dl,
             COALESCE(SUM(credito_centavos), 0) AS cr, COUNT(*) AS n
      FROM ventas v WHERE $w''', args)).first;
    return [
      FilaReporte('Efectivo', 0, m['ef'] as int, 0),
      FilaReporte('Tarjeta', 0, m['ta'] as int, 0),
      FilaReporte('Vales de despensa', 0, m['va'] as int, 0),
      FilaReporte('Dólares', 0, m['dl'] as int, 0),
      FilaReporte('Crédito', 0, m['cr'] as int, 0),
    ];
  }

  /// Productos sin ventas en el periodo (mercancía que no rota).
  Future<List<FilaReporte>> sinMovimiento(DateTime desde, DateTime hasta) async {
    final f = await db.rawQuery('''
      SELECT p.descripcion, p.existencia, p.costo_centavos FROM productos p
      WHERE p.activo = 1 AND NOT EXISTS (
        SELECT 1 FROM venta_detalle d JOIN ventas v ON v.id = d.venta_id
        WHERE d.producto_id = p.id AND v.fecha >= ? AND v.fecha < ?)
      ORDER BY p.existencia * p.costo_centavos DESC''', [desde.toIso8601String(), hasta.toIso8601String()]);
    return f
        .map((m) => FilaReporte(
              m['descripcion'] as String,
              (m['existencia'] as num).toDouble(),
              ((m['existencia'] as num) * (m['costo_centavos'] as int)).round(),
              0,
            ))
        .toList();
  }
}
