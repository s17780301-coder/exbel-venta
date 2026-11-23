import 'dart:convert';

import 'package:excel/excel.dart' show Excel, CellValue, IntCellValue, DoubleCellValue, BoolCellValue;

import '../core/db.dart';
import '../core/ids.dart';
import '../models/modelos.dart';
import 'repos.dart';

/// Lee un archivo de Excel (.xlsx) o CSV y regresa sus filas como texto.
List<List<String>> leerTabla(List<int> bytes, String nombre) {
  final n = nombre.toLowerCase();
  if (n.endsWith('.xlsx')) {
    final excel = Excel.decodeBytes(bytes);
    // La hoja con más filas (el catálogo).
    List<List<String>> mejor = [];
    for (final hoja in excel.tables.values) {
      final filas = [
        for (final fila in hoja.rows) [for (final c in fila) _celda(c?.value)],
      ].where((f) => f.any((x) => x.trim().isNotEmpty)).toList();
      if (filas.length > mejor.length) mejor = filas;
    }
    return mejor;
  }
  String texto;
  try {
    texto = utf8.decode(bytes);
  } catch (_) {
    texto = latin1.decode(bytes);
  }
  return leerCsvTexto(texto);
}

String _celda(CellValue? v) {
  if (v == null) return '';
  if (v is IntCellValue) return '${v.value}';
  if (v is DoubleCellValue) {
    final d = v.value;
    // Los códigos de barras llegan como número: 7501055300846.0
    return d == d.roundToDouble() && d.abs() < 1e15 ? d.toInt().toString() : d.toString();
  }
  if (v is BoolCellValue) return v.value ? 'si' : 'no';
  return v.toString().trim();
}

List<List<String>> leerCsvTexto(String texto) {
  if (texto.startsWith('﻿')) texto = texto.substring(1);
  final primera = texto.split('\n').first;
  final sep = ';'.allMatches(primera).length > ','.allMatches(primera).length
      ? ';'
      : ('\t'.allMatches(primera).length > ','.allMatches(primera).length ? '\t' : ',');
  final filas = <List<String>>[];
  var fila = <String>[];
  final campo = StringBuffer();
  var comillas = false;
  for (var i = 0; i < texto.length; i++) {
    final c = texto[i];
    if (comillas) {
      if (c == '"') {
        if (i + 1 < texto.length && texto[i + 1] == '"') {
          campo.write('"');
          i++;
        } else {
          comillas = false;
        }
      } else {
        campo.write(c);
      }
    } else if (c == '"') {
      comillas = true;
    } else if (c == sep) {
      fila.add(campo.toString());
      campo.clear();
    } else if (c == '\n') {
      fila.add(campo.toString());
      campo.clear();
      if (fila.any((x) => x.trim().isNotEmpty)) filas.add(fila);
      fila = <String>[];
    } else if (c != '\r') {
      campo.write(c);
    }
  }
  fila.add(campo.toString());
  if (fila.any((x) => x.trim().isNotEmpty)) filas.add(fila);
  return filas;
}

/// "Código de Barras" -> "codigo de barras"
String normalizar(String s) {
  const acentos = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    b.write(acentos[ch] ?? ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

/// Un dato que se puede importar y cómo se puede llamar su columna en
/// Eleventa, SICAR, Abarrotes PDV o un Excel hecho a mano.
class Campo {
  const Campo(this.clave, this.nombre, this.sinonimos, {this.obligatorio = false});
  final String clave;
  final String nombre;
  final List<String> sinonimos;
  final bool obligatorio;
}

const camposProducto = <Campo>[
  Campo('codigo', 'Código', ['codigo', 'codigo de barras', 'cod barras', 'clave', 'sku', 'cod', 'codigo producto']),
  Campo('descripcion', 'Descripción', ['descripcion', 'producto', 'nombre', 'articulo', 'nombre del producto', 'descripcion del producto'],
      obligatorio: true),
  Campo('tipo', 'Se vende por', ['tipo de venta', 'se vende', 'se vende por', 'vende por', 'tipo', 'unidad', 'tipo venta']),
  Campo('costo', 'Precio de costo', ['precio costo', 'precio de costo', 'costo', 'p costo', 'costo unitario', 'precio compra', 'precio de compra']),
  Campo('precio', 'Precio de venta', ['precio venta', 'precio de venta', 'precio', 'p venta', 'precio publico', 'precio al publico', 'pventa'],
      obligatorio: true),
  Campo('mayoreo', 'Precio de mayoreo', ['precio mayoreo', 'mayoreo', 'precio de mayoreo', 'p mayoreo']),
  Campo('departamento', 'Departamento', ['departamento', 'depto', 'categoria', 'familia', 'linea', 'departamentos']),
  Campo('existencia', 'Existencia', ['existencia', 'existencias', 'inventario', 'cantidad', 'stock', 'hay', 'inventario actual', 'existencia actual']),
  Campo('minimo', 'Mínimo', ['inv minimo', 'inventario minimo', 'minimo', 'min', 'cantidad minima']),
  Campo('maximo', 'Máximo', ['inv maximo', 'inventario maximo', 'maximo', 'max', 'cantidad maxima']),
  Campo('iva', 'IVA', ['iva', 'impuesto', 'impuestos', 'tasa iva']),
];

const camposCliente = <Campo>[
  Campo('nombre', 'Nombre', ['nombre', 'cliente', 'nombre del cliente', 'razon social', 'nombre completo'], obligatorio: true),
  Campo('telefono', 'Teléfono', ['telefono', 'tel', 'celular', 'whatsapp', 'telefonos']),
  Campo('direccion', 'Dirección', ['direccion', 'domicilio', 'calle']),
  Campo('limite', 'Límite de crédito', ['limite de credito', 'limite', 'credito', 'limite credito']),
  Campo('saldo', 'Saldo (lo que debe)', ['saldo', 'saldo actual', 'adeudo', 'debe', 'saldo pendiente', 'deuda']),
];

/// Busca la fila de encabezados (entre las primeras 15) y qué columna es
/// cada campo. Regresa (fila de encabezados, campo -> columna).
(int, Map<String, int>) detectarColumnas(List<List<String>> filas, List<Campo> campos) {
  var mejorFila = 0;
  var mejor = <String, int>{};
  for (var i = 0; i < filas.length && i < 15; i++) {
    final m = _asignar(filas[i], campos);
    if (m.length > mejor.length) {
      mejor = m;
      mejorFila = i;
    }
  }
  return (mejorFila, mejor);
}

Map<String, int> _asignar(List<String> encabezados, List<Campo> campos) {
  final norm = encabezados.map(normalizar).toList();
  // (puntaje, campo, columna)
  final candidatos = <(int, String, int)>[];
  for (var col = 0; col < norm.length; col++) {
    final h = norm[col];
    if (h.isEmpty) continue;
    for (final c in campos) {
      for (final s in c.sinonimos) {
        int puntos;
        if (h == s) {
          puntos = 1000 + s.length;
        } else if (s.length >= 4 && (' $h ').contains(' $s ')) {
          puntos = 100 + s.length;
        } else {
          continue;
        }
        candidatos.add((puntos, c.clave, col));
      }
    }
  }
  candidatos.sort((a, b) => b.$1.compareTo(a.$1));
  final r = <String, int>{};
  final usadas = <int>{};
  for (final (_, clave, col) in candidatos) {
    if (r.containsKey(clave) || usadas.contains(col)) continue;
    r[clave] = col;
    usadas.add(col);
  }
  return r;
}

/// "$1,234.50" -> 123450
int? leerDinero(String s) {
  final limpio = s.replaceAll(RegExp(r'[^0-9.,\-]'), '');
  if (limpio.isEmpty) return null;
  // "1.234,50" (coma decimal) o "1,234.50".
  String n = limpio;
  if (n.contains(',') && n.contains('.')) {
    n = n.lastIndexOf(',') > n.lastIndexOf('.') ? n.replaceAll('.', '').replaceAll(',', '.') : n.replaceAll(',', '');
  } else if (n.contains(',')) {
    final partes = n.split(',');
    n = partes.length == 2 && partes[1].length <= 2 ? n.replaceAll(',', '.') : n.replaceAll(',', '');
  }
  final v = double.tryParse(n);
  return v == null ? null : (v * 100).round();
}

double? leerNumero(String s) {
  final c = leerDinero(s);
  return c == null ? null : c / 100;
}

/// IVA: "16", "16%", "0.16", "Sí" -> 16. "No", "0", "Exento" -> 0.
double leerIva(String s) {
  final n = normalizar(s);
  if (n.isEmpty || n == 'no' || n.contains('exento')) return 0;
  if (n == 'si' || n == 's') return 16;
  final v = leerNumero(s);
  if (v == null) return 0;
  return v > 0 && v < 1 ? (v * 100).roundToDouble() : v;
}

String leerTipo(String s) {
  final n = normalizar(s);
  if (n.startsWith('g') || n.contains('granel') || n == 'kg' || n.contains('kilo')) return 'granel';
  return 'unidad';
}

class ResumenImportacion {
  int nuevos = 0;
  int actualizados = 0;
  int omitidos = 0;
  final errores = <String>[];
}

/// Importa productos. Si el código ya existe, se actualiza (precios y datos);
/// la existencia del archivo reemplaza la actual si [reemplazarExistencia].
Future<ResumenImportacion> importarProductos(
  List<List<String>> filas,
  int filaEncabezado,
  Map<String, int> columnas, {
  bool reemplazarExistencia = true,
  String? cajeroId,
  void Function(int hechos, int total)? progreso,
}) async {
  final r = ResumenImportacion();
  final deps = {for (final d in await repos.productos.departamentos()) normalizar(d.nombre): d.id};
  String v(List<String> f, String campo) {
    final i = columnas[campo];
    return i == null || i >= f.length ? '' : f[i].trim();
  }

  final datos = filas.skip(filaEncabezado + 1).toList();
  for (var i = 0; i < datos.length; i++) {
    final f = datos[i];
    progreso?.call(i, datos.length);
    final desc = v(f, 'descripcion');
    if (desc.isEmpty) {
      r.omitidos++;
      continue;
    }
    try {
      final codigo = v(f, 'codigo');
      final existente = codigo.isEmpty ? null : await repos.productos.porCodigo(codigo);
      final depNombre = v(f, 'departamento');
      String? depId = existente?.departamentoId;
      if (depNombre.isNotEmpty) {
        final k = normalizar(depNombre);
        depId = deps[k] ??= (await repos.productos.guardarDepartamento(nombre: depNombre)).id;
      }
      final precio = leerDinero(v(f, 'precio')) ?? existente?.precioCentavos ?? 0;
      var mayoreo = leerDinero(v(f, 'mayoreo')) ?? existente?.mayoreoCentavos ?? 0;
      if (mayoreo >= precio) mayoreo = 0;
      final p = Producto(
        id: existente?.id ?? nuevoId(),
        codigo: codigo,
        descripcion: desc,
        tipo: columnas.containsKey('tipo') ? leerTipo(v(f, 'tipo')) : (existente?.tipo ?? 'unidad'),
        departamentoId: depId,
        costoCentavos: leerDinero(v(f, 'costo')) ?? existente?.costoCentavos ?? 0,
        precioCentavos: precio,
        mayoreoCentavos: mayoreo,
        mayoreoDesde: existente?.mayoreoDesde ?? 0,
        usaInventario: existente?.usaInventario ?? true,
        minimo: leerNumero(v(f, 'minimo')) ?? existente?.minimo ?? 0,
        maximo: leerNumero(v(f, 'maximo')) ?? existente?.maximo ?? 0,
        iva: columnas.containsKey('iva') ? leerIva(v(f, 'iva')) : (existente?.iva ?? 0),
        ieps: existente?.ieps ?? 0,
        favorito: existente?.favorito ?? false,
      );
      if (p.precioCentavos <= 0) {
        r.errores.add('$desc: sin precio de venta');
        continue;
      }
      final exist = leerNumero(v(f, 'existencia'));
      await repos.productos.guardar(p, existenciaInicial: existente == null ? (exist ?? 0) : 0, cajeroId: cajeroId);
      if (existente != null && exist != null && reemplazarExistencia) {
        await repos.productos.ajustarInventario(p.id, exist, motivo: 'Importación', cajeroId: cajeroId);
      }
      if (existente == null) {
        r.nuevos++;
      } else {
        r.actualizados++;
      }
    } catch (e) {
      r.errores.add('$desc: $e');
    }
  }
  progreso?.call(datos.length, datos.length);
  return r;
}

/// Importa clientes; el saldo del archivo queda como "saldo anterior".
Future<ResumenImportacion> importarClientes(List<List<String>> filas, int filaEncabezado, Map<String, int> columnas) async {
  final r = ResumenImportacion();
  final existentes = {for (final c in await repos.clientes.buscar('')) normalizar(c.nombre): c};
  String v(List<String> f, String campo) {
    final i = columnas[campo];
    return i == null || i >= f.length ? '' : f[i].trim();
  }

  for (final f in filas.skip(filaEncabezado + 1)) {
    final nombre = v(f, 'nombre');
    if (nombre.isEmpty || normalizar(nombre) == 'total' || normalizar(nombre).startsWith('total ')) {
      r.omitidos++;
      continue;
    }
    try {
      final ya = existentes[normalizar(nombre)];
      if (ya != null) {
        r.omitidos++;
        continue;
      }
      final c = await repos.clientes.guardar(Cliente(
        id: nuevoId(),
        nombre: nombre,
        telefono: v(f, 'telefono'),
        direccion: v(f, 'direccion'),
        limiteCentavos: leerDinero(v(f, 'limite')) ?? 0,
      ));
      final saldo = leerDinero(v(f, 'saldo')) ?? 0;
      if (saldo > 0) await repos.clientes.fijarSaldoAnterior(c.id, saldo);
      existentes[normalizar(nombre)] = c;
      r.nuevos++;
    } catch (e) {
      r.errores.add('$nombre: $e');
    }
  }
  return r;
}

/// Borra datos para empezar de cero (conserva cajeros, configuración y el
/// turno abierto). Antes hace un respaldo automático.
Future<void> borrarDatos({
  required bool productos,
  required bool clientes,
  required bool ventas,
  String? turnoActualId,
}) async {
  await respaldoAutomatico(repos.db);
  await repos.db.transaction((tx) async {
    if (ventas) {
      await tx.delete('venta_detalle');
      await tx.delete('devoluciones');
      await tx.delete('abonos');
      await tx.delete('ventas');
      await tx.delete('movimientos_caja');
      await tx.delete('turnos', where: 'id <> ?', whereArgs: [turnoActualId ?? '']);
    }
    if (clientes) {
      await tx.delete('abonos');
      await tx.rawUpdate('UPDATE ventas SET cliente_id = NULL');
      await tx.delete('clientes');
    }
    if (productos) {
      await tx.rawUpdate('UPDATE venta_detalle SET producto_id = NULL');
      await tx.delete('movimientos_inventario');
      await tx.delete('kit_componentes');
      await tx.delete('promociones');
      await tx.delete('productos');
      await tx.delete('departamentos');
    }
  });
}

/// Para mostrar cantidades del archivo en la vista previa.
String muestra(String s) => s.length > 40 ? '${s.substring(0, 40)}…' : s;
