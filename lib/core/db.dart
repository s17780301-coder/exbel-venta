import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'ids.dart';

/// Base de datos local de la tienda (SQLite). Todas las tablas llevan
/// `actualizado` y `sincronizado` para la futura MultiCaja y la nube.
class AppDb {
  AppDb._();

  static const version = 3;

  /// Carpeta de datos de exBel venta (base, respaldos, logotipo).
  static Future<Directory> carpeta() async {
    final base = await getApplicationSupportDirectory();
    await base.create(recursive: true);
    return base;
  }

  static Future<String> rutaBase() async => p.join((await carpeta()).path, 'exbel-venta.db');

  static Future<Database> abrir() async {
    sqfliteFfiInit();
    return abrirCon(databaseFactoryFfi, await rutaBase());
  }

  static Future<Database> abrirCon(DatabaseFactory fabrica, String ruta) {
    return fabrica.openDatabase(
      ruta,
      options: OpenDatabaseOptions(
        version: version,
        singleInstance: ruta != inMemoryDatabasePath,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          final b = db.batch();
          for (final sql in [...esquema, ...migracionV2, ...migracionV3]) {
            b.execute(sql);
          }
          await b.commit(noResult: true);
        },
        onUpgrade: (db, antes, _) async {
          if (antes < 2) {
            for (final sql in migracionV2) {
              await db.execute(sql);
            }
          }
          if (antes < 3) {
            for (final sql in migracionV3) {
              await db.execute(sql);
            }
          }
        },
      ),
    );
  }
}

const _sync = 'actualizado TEXT NOT NULL, sincronizado INTEGER NOT NULL DEFAULT 0';

/// Dinero en centavos (INTEGER). Cantidades en REAL (granel: 0.250 kg).
/// Los precios de venta incluyen impuestos; la tasa se guarda para desglosar.
const esquema = <String>[
  'CREATE TABLE ajustes (clave TEXT PRIMARY KEY, valor TEXT NOT NULL)',
  'CREATE TABLE departamentos (id TEXT PRIMARY KEY, nombre TEXT NOT NULL, $_sync)',
  '''
  CREATE TABLE productos (
    id TEXT PRIMARY KEY,
    codigo TEXT NOT NULL DEFAULT '',
    descripcion TEXT NOT NULL,
    tipo TEXT NOT NULL DEFAULT 'unidad' CHECK (tipo IN ('unidad', 'granel', 'kit')),
    departamento_id TEXT REFERENCES departamentos(id),
    costo_centavos INTEGER NOT NULL DEFAULT 0,
    precio_centavos INTEGER NOT NULL DEFAULT 0,
    mayoreo_centavos INTEGER NOT NULL DEFAULT 0,
    mayoreo_desde REAL NOT NULL DEFAULT 0,
    usa_inventario INTEGER NOT NULL DEFAULT 1,
    existencia REAL NOT NULL DEFAULT 0,
    minimo REAL NOT NULL DEFAULT 0,
    maximo REAL NOT NULL DEFAULT 0,
    iva REAL NOT NULL DEFAULT 16,
    ieps REAL NOT NULL DEFAULT 0,
    favorito INTEGER NOT NULL DEFAULT 0,
    kit_descuenta_componentes INTEGER NOT NULL DEFAULT 1,
    activo INTEGER NOT NULL DEFAULT 1,
    $_sync
  )''',
  'CREATE INDEX idx_productos_codigo ON productos(codigo)',
  'CREATE INDEX idx_productos_descripcion ON productos(descripcion)',
  '''
  CREATE TABLE kit_componentes (
    kit_id TEXT NOT NULL REFERENCES productos(id),
    producto_id TEXT NOT NULL REFERENCES productos(id),
    cantidad REAL NOT NULL,
    PRIMARY KEY (kit_id, producto_id)
  )''',
  // Promoción "N por $X" (ej. 3 por $20).
  '''
  CREATE TABLE promociones (
    id TEXT PRIMARY KEY,
    producto_id TEXT NOT NULL REFERENCES productos(id),
    nombre TEXT NOT NULL,
    cantidad REAL NOT NULL,
    precio_centavos INTEGER NOT NULL,
    activa INTEGER NOT NULL DEFAULT 1,
    $_sync
  )''',
  '''
  CREATE TABLE cajeros (
    id TEXT PRIMARY KEY,
    usuario TEXT NOT NULL,
    nombre TEXT NOT NULL,
    clave_hash TEXT NOT NULL,
    administrador INTEGER NOT NULL DEFAULT 0,
    permisos TEXT NOT NULL DEFAULT '',
    activo INTEGER NOT NULL DEFAULT 1,
    $_sync
  )''',
  '''
  CREATE TABLE turnos (
    id TEXT PRIMARY KEY,
    numero INTEGER NOT NULL,
    cajero_id TEXT NOT NULL REFERENCES cajeros(id),
    abierto TEXT NOT NULL,
    cerrado TEXT,
    fondo_centavos INTEGER NOT NULL DEFAULT 0,
    contado_centavos INTEGER,
    esperado_centavos INTEGER,
    estado TEXT NOT NULL DEFAULT 'abierto',
    $_sync
  )''',
  '''
  CREATE TABLE movimientos_caja (
    id TEXT PRIMARY KEY,
    turno_id TEXT NOT NULL REFERENCES turnos(id),
    fecha TEXT NOT NULL,
    tipo TEXT NOT NULL CHECK (tipo IN ('entrada', 'salida')),
    monto_centavos INTEGER NOT NULL,
    concepto TEXT NOT NULL DEFAULT '',
    cancelado INTEGER NOT NULL DEFAULT 0,
    $_sync
  )''',
  '''
  CREATE TABLE clientes (
    id TEXT PRIMARY KEY,
    numero INTEGER NOT NULL,
    nombre TEXT NOT NULL,
    direccion TEXT NOT NULL DEFAULT '',
    telefono TEXT NOT NULL DEFAULT '',
    limite_centavos INTEGER NOT NULL DEFAULT 0,
    saldo_centavos INTEGER NOT NULL DEFAULT 0,
    activo INTEGER NOT NULL DEFAULT 1,
    $_sync
  )''',
  '''
  CREATE TABLE ventas (
    id TEXT PRIMARY KEY,
    folio INTEGER NOT NULL,
    fecha TEXT NOT NULL,
    turno_id TEXT NOT NULL REFERENCES turnos(id),
    cajero_id TEXT NOT NULL REFERENCES cajeros(id),
    cliente_id TEXT REFERENCES clientes(id),
    total_centavos INTEGER NOT NULL,
    efectivo_centavos INTEGER NOT NULL DEFAULT 0,
    tarjeta_centavos INTEGER NOT NULL DEFAULT 0,
    vales_centavos INTEGER NOT NULL DEFAULT 0,
    dolares_centavos INTEGER NOT NULL DEFAULT 0,
    credito_centavos INTEGER NOT NULL DEFAULT 0,
    recibido_centavos INTEGER NOT NULL DEFAULT 0,
    referencia TEXT NOT NULL DEFAULT '',
    notas TEXT NOT NULL DEFAULT '',
    estado TEXT NOT NULL DEFAULT 'activa',
    $_sync
  )''',
  'CREATE INDEX idx_ventas_fecha ON ventas(fecha)',
  'CREATE INDEX idx_ventas_turno ON ventas(turno_id)',
  'CREATE INDEX idx_ventas_cliente ON ventas(cliente_id)',
  '''
  CREATE TABLE venta_detalle (
    id TEXT PRIMARY KEY,
    venta_id TEXT NOT NULL REFERENCES ventas(id),
    producto_id TEXT REFERENCES productos(id),
    codigo TEXT NOT NULL DEFAULT '',
    descripcion TEXT NOT NULL,
    departamento_id TEXT,
    cantidad REAL NOT NULL,
    precio_centavos INTEGER NOT NULL,
    costo_centavos INTEGER NOT NULL DEFAULT 0,
    importe_centavos INTEGER NOT NULL,
    iva REAL NOT NULL DEFAULT 0,
    ieps REAL NOT NULL DEFAULT 0,
    mayoreo INTEGER NOT NULL DEFAULT 0,
    devuelto REAL NOT NULL DEFAULT 0,
    $_sync
  )''',
  'CREATE INDEX idx_detalle_venta ON venta_detalle(venta_id)',
  '''
  CREATE TABLE devoluciones (
    id TEXT PRIMARY KEY,
    venta_id TEXT NOT NULL REFERENCES ventas(id),
    turno_id TEXT NOT NULL REFERENCES turnos(id),
    fecha TEXT NOT NULL,
    total_centavos INTEGER NOT NULL,
    efectivo_centavos INTEGER NOT NULL DEFAULT 0,
    credito_centavos INTEGER NOT NULL DEFAULT 0,
    descripcion TEXT NOT NULL DEFAULT '',
    $_sync
  )''',
  '''
  CREATE TABLE abonos (
    id TEXT PRIMARY KEY,
    cliente_id TEXT NOT NULL REFERENCES clientes(id),
    turno_id TEXT NOT NULL REFERENCES turnos(id),
    venta_id TEXT REFERENCES ventas(id),
    fecha TEXT NOT NULL,
    monto_centavos INTEGER NOT NULL,
    forma_pago TEXT NOT NULL DEFAULT 'efectivo',
    cancelado INTEGER NOT NULL DEFAULT 0,
    $_sync
  )''',
  '''
  CREATE TABLE movimientos_inventario (
    id TEXT PRIMARY KEY,
    producto_id TEXT NOT NULL REFERENCES productos(id),
    fecha TEXT NOT NULL,
    tipo TEXT NOT NULL,
    habia REAL NOT NULL,
    cantidad REAL NOT NULL,
    hay REAL NOT NULL,
    costo_centavos INTEGER NOT NULL DEFAULT 0,
    descripcion TEXT NOT NULL DEFAULT '',
    origen TEXT NOT NULL DEFAULT '',
    cajero_id TEXT,
    referencia_id TEXT,
    $_sync
  )''',
  'CREATE INDEX idx_movinv_producto ON movimientos_inventario(producto_id, fecha)',
  'CREATE INDEX idx_movinv_fecha ON movimientos_inventario(fecha)',
];

/// v2: saldo anterior de clientes migrados de otro sistema.
const migracionV2 = <String>[
  'ALTER TABLE clientes ADD COLUMN saldo_anterior_centavos INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE clientes ADD COLUMN saldo_anterior_fecha TEXT',
];

/// v3: pago con transferencia.
const migracionV3 = <String>[
  'ALTER TABLE ventas ADD COLUMN transferencia_centavos INTEGER NOT NULL DEFAULT 0',
];

/// Actualiza la fila si existe; si no, la inserta.
Future<void> guardarFila(DatabaseExecutor ex, String tabla, Map<String, Object?> valores) async {
  final fila = {...valores, 'actualizado': ahoraUtc(), 'sincronizado': 0};
  final n = await ex.update(tabla, fila, where: 'id = ?', whereArgs: [fila['id']]);
  if (n == 0) await ex.insert(tabla, fila);
}

Future<int> siguienteNumero(DatabaseExecutor ex, String tabla, String columna) async {
  final r = await ex.rawQuery('SELECT MAX($columna) AS m FROM $tabla');
  return ((r.first['m'] as int?) ?? 0) + 1;
}

/// Mueve la existencia de un producto y deja el registro (había / hay).
/// No hace nada si el producto no usa inventario.
Future<void> moverInventario(
  DatabaseExecutor ex, {
  required String productoId,
  required double cantidad,
  required String tipo,
  String descripcion = '',
  String origen = '',
  int costoCentavos = 0,
  String? cajeroId,
  String? referenciaId,
}) async {
  final f = await ex.query('productos',
      columns: ['existencia', 'usa_inventario'], where: 'id = ?', whereArgs: [productoId]);
  if (f.isEmpty || f.first['usa_inventario'] != 1 || cantidad == 0) return;
  final habia = (f.first['existencia'] as num).toDouble();
  final hay = habia + cantidad;
  final ahora = ahoraUtc();
  await ex.insert('movimientos_inventario', {
    'id': nuevoId(),
    'producto_id': productoId,
    'fecha': ahoraLocal(),
    'tipo': tipo,
    'habia': habia,
    'cantidad': cantidad,
    'hay': hay,
    'costo_centavos': costoCentavos,
    'descripcion': descripcion,
    'origen': origen,
    'cajero_id': cajeroId,
    'referencia_id': referenciaId,
    'actualizado': ahora,
    'sincronizado': 0,
  });
  await ex.update('productos', {'existencia': hay, 'actualizado': ahora, 'sincronizado': 0},
      where: 'id = ?', whereArgs: [productoId]);
}

/// Copia completa y consistente de la base (aunque esté en uso).
Future<String> respaldarBase(Database db, String carpetaDestino) async {
  final f = DateTime.now();
  String d(int n) => n.toString().padLeft(2, '0');
  final nombre = 'exbel-venta-respaldo-${f.year}${d(f.month)}${d(f.day)}-${d(f.hour)}${d(f.minute)}${d(f.second)}.db';
  final ruta = p.join(carpetaDestino, nombre);
  await Directory(carpetaDestino).create(recursive: true);
  await db.execute("VACUUM INTO '${ruta.replaceAll("'", "''")}'");
  return ruta;
}

/// Respaldo automático en la carpeta de la app; conserva los últimos 10.
Future<void> respaldoAutomatico(Database db) async {
  try {
    final carpeta = p.join((await AppDb.carpeta()).path, 'respaldos');
    await respaldarBase(db, carpeta);
    final archivos = Directory(carpeta).listSync().whereType<File>().where((f) => f.path.endsWith('.db')).toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final f in archivos.skip(10)) {
      await f.delete();
    }
  } catch (_) {}
}
