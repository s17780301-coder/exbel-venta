import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/ids.dart';
import '../models/modelos.dart';
import 'importador.dart';
import 'repos.dart';

/// Lector de respaldos .fbk (gbak de Firebird, formato transportable) del
/// sistema anterior. Lee las tablas tal cual, sin instalar nada.
class RespaldoFbk {
  RespaldoFbk(this.d) : _bd = ByteData.sublistView(d);
  final Uint8List d;
  final ByteData _bd;

  static Future<RespaldoFbk> abrir(String ruta) async => RespaldoFbk(await File(ruta).readAsBytes());

  /// ¿Parece un respaldo de Firebird?
  bool get valido => d.length > 64 && _buscar(latin1.encode('PRODUCTOS')) > 0;

  int _buscar(List<int> p, [int desde = 0, int? hasta]) {
    final fin = (hasta ?? d.length) - p.length;
    final p0 = p[0];
    for (var i = desde; i <= fin; i++) {
      if (d[i] != p0) continue;
      var ok = true;
      for (var k = 1; k < p.length; k++) {
        if (d[i + k] != p[k]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  int _i32le(int o) => _bd.getInt32(o, Endian.little);

  /// Atributos con texto largo: después del tipo van 4 bytes con el largo.
  static const _largos = {0x0f, 0x23, 0x27};

  /// Lee atributos (tipo, largo, valor) hasta el 0 final.
  (Map<int, Uint8List>, int) _atributos(int i) {
    final a = <int, Uint8List>{};
    while (i < d.length) {
      final t = d[i++];
      if (t == 0) break;
      final n = d[i];
      if (_largos.contains(t) && n == 4) {
        final l = _i32le(i + 1);
        a.putIfAbsent(t, () => Uint8List.sublistView(d, i + 5, i + 5 + l));
        i += 5 + l;
      } else {
        a.putIfAbsent(t, () => Uint8List.sublistView(d, i + 1, i + 1 + n));
        i += 1 + n;
      }
    }
    return (a, i);
  }

  List<_Campo> campos(String tabla) {
    final nb = latin1.encode(tabla);
    final inicio = _buscar([3, 1, nb.length, ...nb]);
    if (inicio < 0) return const [];
    var (_, i) = _atributos(inicio + 1);
    final fs = <_Campo>[];
    while (i < d.length && d[i] == 4) {
      final (a, sig) = _atributos(i + 1);
      i = sig;
      int? g(int t) => a[t] != null && a[t]!.length == 4 ? ByteData.sublistView(a[t]!).getInt32(0, Endian.little) : null;
      if (a[1] != null && a[8] != null) fs.add(_Campo(latin1.decode(a[1]!), g(8)!, g(10) ?? 0, g(11) ?? 0));
    }
    return fs;
  }

  bool _letraNombre(int c) => (c >= 0x41 && c <= 0x5a) || (c >= 0x30 && c <= 0x39) || c == 0x5f || c == 0x24;

  /// Dónde empiezan los datos de la siguiente tabla (fin de los de ésta).
  int _siguienteTabla(int desde) {
    for (var k = desde; k < d.length - 4; k++) {
      if (d[k] != 8 || d[k + 1] != 1) continue;
      final l = d[k + 2];
      if (l < 1 || l > 0x40 || k + 3 + l >= d.length || d[k + 3 + l] != 0) continue;
      var ok = true;
      for (var j = 0; j < l; j++) {
        if (!_letraNombre(d[k + 3 + j])) {
          ok = false;
          break;
        }
      }
      if (ok) return k;
    }
    return d.length;
  }

  /// Filas de una tabla como mapas campo → valor.
  Iterable<Map<String, Object?>> filas(String tabla) sync* {
    final fs = campos(tabla);
    if (fs.isEmpty) return;
    final nb = latin1.encode(tabla);
    var i = _buscar([8, 1, nb.length, ...nb, 0]);
    if (i < 0) return;
    final limite = _siguienteTabla(i + nb.length + 4);
    i = _buscar([6, 1, 4], i + nb.length + 4, limite);
    if (i < 0) return;
    Map<String, Object?>? prev;
    while (i < d.length && (d[i] == 6 || d[i] == 7)) {
      if (d[i] == 7) {
        i = _saltarBlob(i);
        continue;
      }
      if (prev != null) yield prev;
      i++;
      final a = <int, int>{};
      while (d[i] != 2) {
        final n = d[i + 1];
        a[d[i]] = n == 4 ? _i32le(i + 2) : 0;
        i += 2 + n;
      }
      i++;
      // 17 = largo real del registro (formato portátil); 1 = largo en la base.
      final util = a[17] ?? a[1]!;
      final total = util;
      final m = Uint8List(total);
      var o = 0;
      while (o < util) {
        var c = d[i++];
        if (c > 127) c -= 256;
        if (c >= 0) {
          final n = (o + c > total) ? total - o : c;
          m.setRange(o, o + n, d, i);
          o += c;
          i += c;
        } else {
          final b = d[i++];
          final n = (o - c > total) ? total - o : -c;
          m.fillRange(o, o + n, b);
          o += -c;
        }
      }
      prev = _xdr(m, fs);
    }
    if (prev != null) yield prev;
  }

  int _saltarBlob(int i) {
    i++;
    var nseg = 1;
    while (true) {
      final t = d[i++];
      if (t == 0) return i;
      if (t == 7) {
        for (var s = 0; s < nseg; s++) {
          final n = _bd.getUint16(i, Endian.little);
          i += 2 + n;
        }
        return i;
      }
      final n = d[i];
      if (t == 5 && n == 4) nseg = _i32le(i + 1);
      i += 1 + n;
    }
  }

  Map<String, Object?> _xdr(Uint8List m, List<_Campo> fs) {
    final b = ByteData.sublistView(m);
    int p4(int n) => (n + 3) ~/ 4 * 4;
    var o = 0;
    final vals = <Object?>[];
    num escala(num v, int s) => s == 0 ? v : v * _pot10(s);
    for (final f in fs) {
      Object? v;
      if (o + 4 > m.length) {
        vals.add(null);
        continue;
      }
      try {
      switch (f.tipo) {
        case 37:
          final n = b.getUint32(o);
          final ini = (o + 4).clamp(0, m.length);
          final fin = (o + 4 + n).clamp(ini, m.length);
          v = latin1.decode(m.sublist(ini, fin));
          o += 4 + p4(n);
        case 14:
          v = latin1.decode(m.sublist(o, (o + f.largo).clamp(o, m.length))).trimRight();
          o += p4(f.largo);
        case 7 || 8:
          v = escala(b.getInt32(o), f.escala);
          o += 4;
        case 16:
          v = escala(b.getInt64(o), f.escala);
          o += 8;
        case 27:
          v = b.getFloat64(o);
          o += 8;
        case 10:
          v = (b.getFloat32(o) * 1000).round() / 1000;
          o += 4;
        case 12 || 13:
          v = b.getInt32(o);
          o += 4;
        case 35 || 261:
          v = f.tipo == 261 ? '<blob>' : b.getInt32(o);
          o += 8;
        default:
          o += p4(f.largo);
      }
      } on RangeError {
        v = null;
        o = m.length;
      }
      vals.add(v);
    }
    final r = <String, Object?>{};
    for (var k = 0; k < fs.length; k++) {
      final nulo = o + 4 <= m.length ? b.getInt32(o) != 0 : false;
      o += 4;
      r[fs[k].nombre] = nulo ? null : vals[k];
    }
    return r;
  }

  static double _pot10(int s) {
    var r = 1.0;
    for (var k = 0; k < s.abs(); k++) {
      r *= 10;
    }
    return s < 0 ? 1 / r : r;
  }
}

class _Campo {
  _Campo(this.nombre, this.tipo, this.largo, this.escala);
  final String nombre;
  final int tipo;
  final int largo;
  final int escala;
}

int _centavos(Object? v) => v is num ? (v * 100).round() : 0;
double _num(Object? v) => v is num ? v.toDouble() : 0;
String _txt(Object? v) => (v as String?)?.trim() ?? '';

/// Lo que trae el respaldo, para mostrarlo antes de importar.
class ContenidoRespaldo {
  ContenidoRespaldo(this.productos, this.departamentos, this.existencias, this.clientes, this.credito, this.componentes);
  final List<Map<String, Object?>> productos;
  final Map<int, String> departamentos;
  final Map<int, double> existencias;
  final List<Map<String, Object?>> clientes;
  final Map<int, Map<String, Object?>> credito;
  final Map<int, List<(int, double)>> componentes;

  int get granel => productos.where((p) => p['TVENTA'] == 'D').length;
}

/// Lee lo necesario del respaldo en segundo plano (tarda unos segundos con
/// archivos grandes; la pantalla no se congela).
Future<ContenidoRespaldo> leerRespaldo(String ruta) => Isolate.run(() => _leer(ruta));

Future<ContenidoRespaldo> _leer(String ruta) async {
  final f = await RespaldoFbk.abrir(ruta);
  if (!f.valido) throw const FormatException('El archivo no es un respaldo del sistema anterior (.fbk).');
  final deps = {for (final r in f.filas('DEPARTAMENTOS')) r['ID'] as int: _txt(r['NOMBRE'])};
  final ex = <int, double>{};
  for (final r in f.filas('INVENTARIO_BALANCES')) {
    final id = r['PRODUCTO_ID'] as int?;
    if (id != null) ex[id] = (ex[id] ?? 0) + _num(r['CANTIDAD_ACTUAL']);
  }
  final prods = [for (final r in f.filas('PRODUCTOS')) if (r['ELIMINADO_EN'] == null && _txt(r['DESCRIPCION']).isNotEmpty) r];
  final comp = <int, List<(int, double)>>{};
  for (final r in f.filas('PRODUCTO_COMPONENTES')) {
    final padre = r['PRODUCTO_PADRE_ID'] as int?, hijo = r['PRODUCTO_HIJO_ID'] as int?;
    if (padre != null && hijo != null) (comp[padre] ??= []).add((hijo, _num(r['CANTIDAD'])));
  }
  final clientes = [for (final r in f.filas('CLIENTESV2')) if (r['DE_SISTEMA'] != 1 && r['ACTIVO'] != 0) r];
  final credito = {for (final r in f.filas('CLIENTESV2_CREDITO')) if (r['ELIMINADO_EN'] == null) r['CLIENTESV2_ID'] as int: r};
  return ContenidoRespaldo(prods, deps, ex, clientes, credito, comp);
}

/// Importa productos (con pieza/granel exacto y existencias) y clientes (con
/// saldo y límite de crédito) del respaldo.
Future<(ResumenImportacion, ResumenImportacion)> importarRespaldo(
  ContenidoRespaldo c, {
  bool productos = true,
  bool clientes = true,
  bool reemplazarExistencia = true,
  String? cajeroId,
  void Function(int hechos, int total)? progreso,
}) async {
  final rp = ResumenImportacion(), rc = ResumenImportacion();
  final total = (productos ? c.productos.length : 0) + (clientes ? c.clientes.length : 0);
  var hechos = 0;
  if (productos) {
    final deps = {for (final d in await repos.productos.departamentos()) normalizar(d.nombre): d.id};
    final idNuevo = <int, String>{};
    for (final r in c.productos) {
      progreso?.call(hechos++, total);
      final desc = _txt(r['DESCRIPCION']);
      try {
        final codigo = _txt(r['CODIGO']);
        final existente = codigo.isEmpty ? null : await repos.productos.porCodigo(codigo);
        final depNombre = c.departamentos[r['DEPT']] ?? '';
        String? depId = existente?.departamentoId;
        if (depNombre.isNotEmpty && depNombre != '- Sin Departamento -') {
          depId = deps[normalizar(depNombre)] ??= (await repos.productos.guardarDepartamento(nombre: depNombre)).id;
        }
        final esKit = r['ES_KIT'] == 't' && (c.componentes[r['ID']]?.isNotEmpty ?? false);
        final precio = _centavos(r['PVENTA']);
        var mayoreo = _centavos(r['MAYOREO']);
        if (mayoreo >= precio) mayoreo = 0;
        final p = Producto(
          id: existente?.id ?? nuevoId(),
          codigo: codigo,
          descripcion: desc,
          tipo: esKit ? 'kit' : (r['TVENTA'] == 'D' ? 'granel' : 'unidad'),
          departamentoId: depId,
          costoCentavos: _centavos(r['PCOSTO']),
          precioCentavos: precio,
          mayoreoCentavos: mayoreo,
          mayoreoDesde: existente?.mayoreoDesde ?? 0,
          usaInventario: !esKit && r['USA_INVENTARIO'] != 'f',
          minimo: _num(r['DINVMINIMO']),
          maximo: _num(r['DINVMAXIMO']),
          iva: existente?.iva ?? 0,
          ieps: existente?.ieps ?? 0,
          favorito: existente?.favorito ?? false,
        );
        if (p.precioCentavos <= 0 && !esKit) {
          rp.errores.add('$desc: sin precio de venta');
          continue;
        }
        final ex = c.existencias[r['ID']];
        await repos.productos.guardar(p, existenciaInicial: existente == null ? (ex ?? 0) : 0, cajeroId: cajeroId);
        if (existente != null && ex != null && reemplazarExistencia && p.usaInventario) {
          await repos.productos.ajustarInventario(p.id, ex, motivo: 'Importación del respaldo', cajeroId: cajeroId);
        }
        idNuevo[r['ID'] as int] = p.id;
        if (existente == null) {
          rp.nuevos++;
        } else {
          rp.actualizados++;
        }
      } catch (e) {
        rp.errores.add('$desc: $e');
      }
    }
    // Paquetes: sus componentes, ya con los productos importados.
    for (final r in c.productos.where((r) => r['ES_KIT'] == 't')) {
      final kit = idNuevo[r['ID']];
      final lista = c.componentes[r['ID']];
      if (kit == null || lista == null || lista.isEmpty) continue;
      try {
        final comps = <Componente>[];
        for (final (hijo, cant) in lista) {
          final id = idNuevo[hijo];
          if (id == null) continue;
          final hp = await repos.productos.porId(id);
          if (hp != null) comps.add(Componente(productoId: id, descripcion: hp.descripcion, cantidad: cant, precioCentavos: hp.precioCentavos));
        }
        if (comps.isNotEmpty) await repos.productos.guardarComponentes(kit, comps);
      } catch (e) {
        rp.errores.add('${_txt(r['DESCRIPCION'])} (paquete): $e');
      }
    }
  }
  if (clientes) {
    final existentes = {for (final x in await repos.clientes.buscar('')) normalizar(x.nombre): x};
    for (final r in c.clientes) {
      progreso?.call(hechos++, total);
      final nombre = '${_txt(r['NOMBRES'])} ${_txt(r['APELLIDOS'])}'.trim();
      if (nombre.isEmpty) {
        rc.omitidos++;
        continue;
      }
      try {
        if (existentes.containsKey(normalizar(nombre))) {
          rc.omitidos++;
          continue;
        }
        final cr = c.credito[r['ID']];
        final dir = [_txt(r['DOMICILIO1']), _txt(r['DOMICILIO2']), _txt(r['COLONIA']), _txt(r['MUNICIPIO'])].where((x) => x.isNotEmpty).join(', ');
        final cli = await repos.clientes.guardar(Cliente(
          id: nuevoId(),
          nombre: nombre,
          telefono: _txt(r['TELEFONO']),
          direccion: dir,
          limiteCentavos: cr == null ? 0 : _centavos(cr['LIMITE_CREDITO']),
        ));
        final saldo = cr == null ? 0 : _centavos(cr['SALDO_ACTUAL']);
        if (saldo > 0) await repos.clientes.fijarSaldoAnterior(cli.id, saldo);
        existentes[normalizar(nombre)] = cli;
        rc.nuevos++;
      } catch (e) {
        rc.errores.add('$nombre: $e');
      }
    }
  }
  progreso?.call(total, total);
  return (rp, rc);
}
