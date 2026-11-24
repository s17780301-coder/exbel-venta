import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../core/db.dart';
import '../core/ids.dart';
import '../models/modelos.dart';
import 'repos.dart';

/// Lee un archivo de Excel (.xlsx) o CSV y regresa sus filas como texto.
List<List<String>> leerTabla(List<int> bytes, String nombre) {
  if (nombre.toLowerCase().endsWith('.xlsx')) return leerXlsx(bytes);
  String texto;
  try {
    texto = utf8.decode(bytes);
  } catch (_) {
    texto = latin1.decode(bytes);
  }
  return leerCsvTexto(texto);
}

/// Lector propio de .xlsx (es un ZIP con XML): lee el texto de las celdas de
/// la hoja con más filas. Funciona con los Excel que exportan otros puntos de venta.
List<List<String>> leerXlsx(List<int> bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? texto(ArchiveFile? f) => f == null ? null : utf8.decode(f.content as List<int>, allowMalformed: true);
  final compartidos = <String>[];
  final ss = texto(zip.findFile('xl/sharedStrings.xml'));
  if (ss != null) {
    for (final si in XmlDocument.parse(ss).findAllElements('si')) {
      compartidos.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }
  var mejor = <List<String>>[];
  for (final f in zip.files) {
    if (!f.isFile || !RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(f.name)) continue;
    final doc = XmlDocument.parse(texto(f)!);
    final filas = <List<String>>[];
    for (final row in doc.findAllElements('row')) {
      final fila = <String>[];
      for (final c in row.findElements('c')) {
        final col = _columna(c.getAttribute('r') ?? '') ?? fila.length;
        final t = c.getAttribute('t');
        String v;
        if (t == 'inlineStr') {
          v = c.findAllElements('t').map((e) => e.innerText).join();
        } else {
          final crudo = c.getElement('v')?.innerText ?? '';
          if (t == 's') {
            final i = int.tryParse(crudo);
            v = i != null && i >= 0 && i < compartidos.length ? compartidos[i] : '';
          } else if (t == 'b') {
            v = crudo == '1' ? 'si' : 'no';
          } else if (t == 'str' || t == 'e') {
            v = crudo;
          } else {
            v = _numero(crudo);
          }
        }
        while (fila.length <= col) {
          fila.add('');
        }
        fila[col] = v.trim();
      }
      if (fila.any((x) => x.isNotEmpty)) filas.add(fila);
    }
    if (filas.length > mejor.length) mejor = filas;
  }
  return mejor;
}

/// "C12" -> 2
int? _columna(String ref) {
  final letras = RegExp(r'^[A-Z]+').firstMatch(ref.toUpperCase())?.group(0);
  if (letras == null) return null;
  var n = 0;
  for (final u in letras.codeUnits) {
    n = n * 26 + (u - 64);
  }
  return n - 1;
}

/// Los códigos de barras llegan como número (7501055300846 o 7.501055300846E12).
String _numero(String crudo) {
  final d = double.tryParse(crudo);
  if (d == null) return crudo;
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  return crudo;
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
/// otros puntos de venta o un Excel hecho a mano.
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

/// "20.24" sí; "18.00" no. Otros sistemas no exportan si es a granel, pero una
/// existencia con decimales casi siempre lo indica (arroz, aguacate…).
bool tieneDecimales(String s) {
  final n = leerNumero(s);
  return n != null && (n * 1000).round() % 1000 != 0;
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
  bool granelSiDecimales = false,
  Set<String> departamentosGranel = const {},
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
        tipo: columnas.containsKey('tipo')
            ? leerTipo(v(f, 'tipo'))
            : ((granelSiDecimales && tieneDecimales(v(f, 'existencia'))) || departamentosGranel.contains(normalizar(depNombre))
                ? 'granel'
                : (existente?.tipo ?? 'unidad')),
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

/// Palabras de departamentos que normalmente se venden por kilo.
const _pistasGranel = ['granel', 'croqueta', 'semilla', 'grano', 'salchichon', 'carne', 'queso', 'fruta', 'verdura',
  'legumbre', 'chile seco', 'cremeria', 'jamon', 'pollo', 'carniceria', 'cerdo', 'alimento para', 'forraje', 'cereal suelto'];

/// Departamentos del archivo: (nombre, productos, con existencia decimal, sugerido a granel).
List<(String, int, int, bool)> departamentosDelArchivo(List<List<String>> filas, int encabezado, Map<String, int> cols) {
  final iDep = cols['departamento'];
  if (iDep == null) return [];
  final iEx = cols['existencia'];
  final total = <String, int>{};
  final dec = <String, int>{};
  for (final f in filas.skip(encabezado + 1)) {
    final d = iDep < f.length ? f[iDep].trim() : '';
    if (d.isEmpty) continue;
    total[d] = (total[d] ?? 0) + 1;
    if (iEx != null && iEx < f.length && tieneDecimales(f[iEx])) dec[d] = (dec[d] ?? 0) + 1;
  }
  final r = [
    for (final e in total.entries)
      (
        e.key,
        e.value,
        dec[e.key] ?? 0,
        (dec[e.key] ?? 0) * 10 >= e.value * 3 || _pistasGranel.any((p) => normalizar(e.key).contains(p)),
      )
  ]..sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
  return r;
}
