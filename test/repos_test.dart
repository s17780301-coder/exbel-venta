import 'package:exbel_venta/core/db.dart';
import 'package:exbel_venta/core/errores.dart';
import 'package:exbel_venta/core/ids.dart';
import 'package:exbel_venta/data/ejemplo.dart';
import 'package:exbel_venta/data/repos.dart';
import 'package:exbel_venta/models/modelos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Cajero admin;
  late Turno turno;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final db = await AppDb.abrirCon(databaseFactoryFfi, inMemoryDatabasePath);
    repos = Repos(db);
    await repos.ajustes.cargar();
    admin = await repos.cajeros.guardar(usuario: 'Admin', nombre: 'Dueño', clave: '1234', administrador: true);
    turno = await repos.caja.abrirTurno(admin.id, 50000);
    await cargarEjemplo(cajeroId: admin.id);
  });

  tearDown(() => repos.db.close());

  test('cajeros: entrar con contraseña y permisos', () async {
    expect(await repos.cajeros.entrar('admin', '1234'), isNotNull);
    expect(await repos.cajeros.entrar('admin', 'mal'), isNull);
    final c = await repos.cajeros.guardar(usuario: 'ana', nombre: 'Ana', clave: '1', permisos: {Permiso.abonos});
    expect(c.puede(Permiso.abonos), isTrue);
    expect(c.puede(Permiso.cancelar), isFalse);
    await expectLater(repos.cajeros.eliminar(admin.id), throwsA(isA<ErrorNegocio>()));
  });

  test('mayoreo automático, promoción y granel', () async {
    final refresco = (await repos.productos.porCodigo('1001'))!;
    final r = Renglon.deProducto(refresco, cantidad: 12);
    expect(r.conMayoreo, isTrue);
    expect(r.importeCentavos, 12 * 1650);
    r.cantidad = 2;
    expect(r.importeCentavos, 3600);
    r.mayoreoManual = true;
    expect(r.importeCentavos, 3300);

    final chicle = (await repos.productos.porCodigo('1054'))!;
    final promo = Promocion(id: nuevoId(), productoId: chicle.id, nombre: '3 por \$5', cantidad: 3, precioCentavos: 500);
    await repos.productos.guardarPromocion(promo);
    final rp = Renglon.deProducto(chicle, cantidad: 7, promocion: await repos.productos.promocionDe(chicle.id));
    expect(rp.importeCentavos, 2 * 500 + 200);

    final frijol = (await repos.productos.porCodigo('1030'))!;
    expect(Renglon.deProducto(frijol, cantidad: 0.250).importeCentavos, 950);
  });

  test('venta en efectivo descuenta inventario y entra al corte', () async {
    final leche = (await repos.productos.porCodigo('1010'))!;
    final v = await repos.ventas.registrar(
      renglones: [Renglon.deProducto(leche, cantidad: 2)],
      pago: Pago(efectivoCentavos: 5800, recibidoCentavos: 10000),
      turnoId: turno.id,
      cajeroId: admin.id,
    );
    expect(v.folio, 1);
    expect((await repos.productos.porId(leche.id))!.existencia, 28);
    final c = await repos.caja.corteTurno(turno.id);
    expect(c.ventasCentavos, 5800);
    expect(c.esperadoCentavos, 50000 + 5800);
    expect(c.gananciaCentavos, 5800 - 2 * 2350);
  });

  test('paquete descuenta sus componentes', () async {
    final combo = (await repos.productos.porCodigo('2001'))!;
    await repos.ventas.registrar(
      renglones: [Renglon.deProducto(combo, cantidad: 2)],
      pago: Pago(tarjetaCentavos: 6600, referencia: '1234'),
      turnoId: turno.id,
      cajeroId: admin.id,
    );
    expect((await repos.productos.porCodigo('1001'))!.existencia, 46);
    expect((await repos.productos.porCodigo('1052'))!.existencia, 38);
  });

  test('crédito, límite, abonos y devolución', () async {
    final cliente = await repos.clientes.guardar(Cliente(id: nuevoId(), nombre: 'Doña Mary', limiteCentavos: 10000));
    final aceite = (await repos.productos.porCodigo('1040'))!;
    final v = await repos.ventas.registrar(
      renglones: [Renglon.deProducto(aceite, cantidad: 2)],
      pago: Pago(creditoCentavos: 8600),
      turnoId: turno.id,
      cajeroId: admin.id,
      cliente: cliente,
    );
    expect((await repos.clientes.porId(cliente.id))!.saldoCentavos, 8600);

    await expectLater(
      repos.ventas.registrar(
        renglones: [Renglon.deProducto(aceite, cantidad: 1)],
        pago: Pago(creditoCentavos: 4300),
        turnoId: turno.id,
        cajeroId: admin.id,
        cliente: cliente,
      ),
      throwsA(isA<ErrorNegocio>()),
    );

    await repos.clientes.abonar(clienteId: cliente.id, montoCentavos: 3000, turnoId: turno.id);
    expect((await repos.clientes.porId(cliente.id))!.saldoCentavos, 5600);

    // Devuelve 1 aceite: se descuenta del crédito.
    final linea = (await repos.ventas.detalle(v.id)).first;
    final efectivo = await repos.ventas.devolver(
        ventaId: v.id, cantidades: {linea.id: 1}, turnoId: turno.id, cajeroId: admin.id);
    expect(efectivo, 0);
    expect((await repos.clientes.porId(cliente.id))!.saldoCentavos, 1300);
    expect((await repos.productos.porId(aceite.id))!.existencia, 23);

    final cuenta = await repos.clientes.estadoDeCuenta(cliente.id);
    expect(cuenta.last.saldoCentavos, 1300);
    await expectLater(repos.clientes.eliminar(cliente.id), throwsA(isA<ErrorNegocio>()));

    final c = await repos.caja.corteTurno(turno.id);
    expect(c.abonosEfectivoCentavos, 3000);
    expect(c.esperadoCentavos, 50000 + 3000);
  });

  test('cancelar venta regresa efectivo e inventario', () async {
    final arroz = (await repos.productos.porCodigo('1031'))!;
    final v = await repos.ventas.registrar(
      renglones: [Renglon.deProducto(arroz, cantidad: 1.5)],
      pago: Pago(efectivoCentavos: 4500, recibidoCentavos: 5000),
      turnoId: turno.id,
      cajeroId: admin.id,
    );
    final ef = await repos.ventas.cancelar(v.id, turnoId: turno.id, cajeroId: admin.id);
    expect(ef, 4500);
    expect((await repos.ventas.porId(v.id))!.cancelada, isTrue);
    expect((await repos.productos.porId(arroz.id))!.existencia, 40);
    final c = await repos.caja.corteTurno(turno.id);
    expect(c.esperadoCentavos, 50000);
    expect(c.gananciaCentavos, 0);
  });

  test('entradas, salidas y cierre de turno con diferencia', () async {
    await repos.caja.registrarMovimiento(turno.id, 'entrada', 20000, 'Cambio');
    await repos.caja.registrarMovimiento(turno.id, 'salida', 15000, 'Pago al de la leche');
    await expectLater(repos.caja.registrarMovimiento(turno.id, 'salida', 999999, 'x'), throwsA(isA<ErrorNegocio>()));
    final dif = await repos.caja.cerrarTurno(turno.id, 54000);
    expect(dif, -1000);
    expect(await repos.caja.turnoAbierto(), isNull);
  });

  test('inventario: entrada con costo promedio y ajuste', () async {
    final cafe = (await repos.productos.porCodigo('1044'))!;
    await repos.productos.agregarInventario(cafe.id, 10, costoCentavos: 7100, costoPromedio: true);
    final p = (await repos.productos.porId(cafe.id))!;
    expect(p.existencia, 20);
    expect(p.costoCentavos, 6600);
    await repos.productos.ajustarInventario(cafe.id, 18, motivo: 'Conteo');
    final movs = await repos.productos.movimientos(productoId: cafe.id);
    expect(movs.first.habia, 20);
    expect(movs.first.hay, 18);
  });

  test('impuestos incluidos se desglosan', () {
    final (iva, ieps) = desgloseImpuestos(11600, 16, 0);
    expect(iva, 1600);
    expect(ieps, 0);
  });

  test('pago mixto con transferencia: corte, folio y artículos', () async {
    final leche = (await repos.productos.porCodigo('1010'))!;
    final v = await repos.ventas.registrar(
      renglones: [Renglon.deProducto(leche, cantidad: 3)],
      pago: Pago(efectivoCentavos: 2700, recibidoCentavos: 5000, transferenciaCentavos: 6000),
      turnoId: turno.id,
      cajeroId: admin.id,
    );
    expect(v.pago.transferenciaCentavos, 6000);
    expect(v.pago.descripcion, 'Mixto (Efectivo, Transferencia)');
    final c = await repos.caja.corteTurno(turno.id);
    expect(c.transferenciaCentavos, 6000);
    expect(c.esperadoCentavos, 50000 + 2700);
    final porFolio = await repos.ventas.listar(texto: '${v.folio}');
    expect(porFolio.single.articulos, 3);
  });

  test('búsqueda inteligente: sin acentos y primero los más vendidos', () async {
    expect((await repos.productos.buscar('azucar')).single.descripcion, 'Azúcar estándar (kg)');
    expect((await repos.productos.buscar('KG AZÚ')).single.codigo, '1032');
    // Vender "Jabón de tocador" lo pone antes que "Jabón de barra".
    final tocador = (await repos.productos.porCodigo('1074'))!;
    await repos.ventas.registrar(
      renglones: [Renglon.deProducto(tocador)],
      pago: Pago(efectivoCentavos: 1900),
      turnoId: turno.id,
      cajeroId: admin.id,
    );
    final r = await repos.productos.buscar('ja', porUso: true);
    expect(r.first.codigo, '1074');
  });

  test('entrega de caja: el fondo que se deja pasa al siguiente turno', () async {
    await repos.caja.cerrarTurno(turno.id, 62000, fondoSiguienteCentavos: 50000);
    final t = (await repos.caja.turnos()).firstWhere((x) => x.id == turno.id);
    expect(t.retiroCentavos, 12000);
    expect(t.fondoSiguienteCentavos, 50000);
    expect(await repos.caja.fondoDejado(), 50000);
    final nuevo = await repos.caja.abrirTurno(admin.id, 50000);
    expect(nuevo.numero, turno.numero + 1);
  });
}
