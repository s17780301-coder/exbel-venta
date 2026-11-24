import 'dart:io';

import 'package:exbel_venta/core/db.dart';
import 'package:exbel_venta/data/ejemplo.dart';
import 'package:exbel_venta/data/importador.dart';
import 'package:exbel_venta/data/repos.dart';
import 'package:exbel_venta/models/modelos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final db = await AppDb.abrirCon(databaseFactoryFfi, inMemoryDatabasePath);
    repos = Repos(db);
    await repos.ajustes.cargar();
  });

  tearDown(() => repos.db.close());

  test('detecta columnas de otro punto de venta aunque haya un título arriba', () {
    final filas = leerCsvTexto('Catálogo de productos\n'
        'Código,Descripción,Precio Costo,Precio Venta,Precio Mayoreo,Departamento,Existencia,Inv. Mínimo,Tipo de Venta\n'
        '7501055300846,Refresco 600 ml,12.50,18.00,16.50,Bebidas,48,12,Unidad\n'
        '1031,Arroz,22,30,,Granos,40.5,10,Granel\n');
    final (fila, cols) = detectarColumnas(filas, camposProducto);
    expect(fila, 1);
    expect(cols['codigo'], 0);
    expect(cols['descripcion'], 1);
    expect(cols['costo'], 2);
    expect(cols['precio'], 3);
    expect(cols['mayoreo'], 4);
    expect(cols['departamento'], 5);
    expect(cols['existencia'], 6);
    expect(cols['minimo'], 7);
    expect(cols['tipo'], 8);
  });

  test('lee dinero, IVA y tipo en varios formatos', () {
    expect(leerDinero('\$1,234.50'), 123450);
    expect(leerDinero('1.234,50'), 123450);
    expect(leerDinero('18'), 1800);
    expect(leerDinero('12,5'), 1250);
    expect(leerDinero(''), isNull);
    expect(leerIva('16%'), 16);
    expect(leerIva('0.16'), 16);
    expect(leerIva('Sí'), 16);
    expect(leerIva('Exento'), 0);
    expect(leerTipo('Granel'), 'granel');
    expect(leerTipo('U'), 'unidad');
  });

  test('importa productos, crea departamentos y actualiza sin duplicar', () async {
    final filas = leerCsvTexto('Código;Descripción;Precio Costo;Precio Venta;Departamento;Existencia\n'
        '7501055300846;Refresco 600 ml;12.50;18.00;Bebidas;48\n'
        '1031;Arroz;22;30;Granos;40.5\n'
        ';;;;;\n');
    final (fila, cols) = detectarColumnas(filas, camposProducto);
    final r = await importarProductos(filas, fila, cols);
    expect(r.nuevos, 2);
    final refresco = (await repos.productos.porCodigo('7501055300846'))!;
    expect(refresco.precioCentavos, 1800);
    expect(refresco.existencia, 48);
    expect(refresco.departamentoNombre, 'Bebidas');

    final filas2 = leerCsvTexto('Código;Descripción;Precio Venta;Existencia\n7501055300846;Refresco 600 ml;19;50\n');
    final (f2, c2) = detectarColumnas(filas2, camposProducto);
    final r2 = await importarProductos(filas2, f2, c2);
    expect(r2.actualizados, 1);
    final otra = (await repos.productos.porCodigo('7501055300846'))!;
    expect(otra.precioCentavos, 1900);
    expect(otra.existencia, 50);
    expect(await repos.productos.contar(), 2);
  });

  test('importa clientes con su saldo anterior', () async {
    final filas = leerCsvTexto('Nombre,Teléfono,Límite de crédito,Saldo actual\n'
        'Doña Mary,2221234567,1000,350.50\n'
        'Don Pepe,,,0\n'
        'TOTAL,,,350.50\n');
    final (fila, cols) = detectarColumnas(filas, camposCliente);
    final r = await importarClientes(filas, fila, cols);
    expect(r.nuevos, 2);
    final mary = (await repos.clientes.buscar('Mary')).first;
    expect(mary.saldoCentavos, 35050);
    expect(mary.limiteCentavos, 100000);
    final cuenta = await repos.clientes.estadoDeCuenta(mary.id);
    expect(cuenta.first.concepto, 'Saldo anterior');
    expect(cuenta.last.saldoCentavos, 35050);
  });

  test('borrar datos deja la tienda limpia y conserva cajeros', () async {
    final admin = await repos.cajeros.guardar(usuario: 'admin', nombre: 'Dueño', clave: '1', administrador: true);
    final turno = await repos.caja.abrirTurno(admin.id, 0);
    await cargarEjemplo(cajeroId: admin.id);
    final leche = (await repos.productos.porCodigo('1010'))!;
    await repos.ventas.registrar(
      renglones: [Renglon.deProducto(leche)],
      pago: Pago(efectivoCentavos: 2900),
      turnoId: turno.id,
      cajeroId: admin.id,
    );
    await borrarDatos(productos: true, clientes: true, ventas: true, turnoActualId: turno.id);
    expect(await repos.productos.contar(), 0);
    expect(await repos.productos.departamentos(), isEmpty);
    expect(await repos.ventas.listar(), isEmpty);
    expect(await repos.cajeros.hayCajeros(), isTrue);
    expect((await repos.caja.turnoAbierto())?.id, turno.id);
  });

  test('lee un Excel FlexCel de otro punto de venta e importa', () async {
    final bytes = File('test/datos/muestra_flexcel.xlsx').readAsBytesSync();
    final filas = leerTabla(bytes, 'inventario.xlsx');
    expect(filas.length, 41);
    expect(filas.first.first, 'Código');
    final (fila, cols) = detectarColumnas(filas, camposProducto);
    expect(fila, 0);
    expect(cols, {
      'codigo': 0, 'descripcion': 1, 'costo': 2, 'precio': 3, 'mayoreo': 4,
      'existencia': 5, 'minimo': 6, 'maximo': 7, 'departamento': 8,
    });
    final r = await importarProductos(filas, fila, cols);
    expect(r.errores, isEmpty);
    expect(r.nuevos, 40);
    final p = (await repos.productos.porCodigo('7500000000001'))!;
    expect(p.descripcion, 'Producto de prueba 1');
    expect(p.precioCentavos, 1214);
    expect(p.existencia, 18);
  });

  test('existencia con decimales se marca como granel', () async {
    final filas = leerCsvTexto('Código,Producto,P. Venta,Existencia\nARROZ,Arroz,\$24.00,20.24\nCOCA,Coca 600,\$18.00,18.00\n');
    final (f, c) = detectarColumnas(filas, camposProducto);
    await importarProductos(filas, f, c, granelSiDecimales: true);
    expect((await repos.productos.porCodigo('ARROZ'))!.tipo, 'granel');
    expect((await repos.productos.porCodigo('COCA'))!.tipo, 'unidad');
  });
}
