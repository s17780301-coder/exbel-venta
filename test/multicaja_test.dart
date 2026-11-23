import 'package:exbel_venta/core/db.dart';
import 'package:exbel_venta/core/errores.dart';
import 'package:exbel_venta/core/red/db_remota.dart';
import 'package:exbel_venta/core/red/servidor.dart';
import 'package:exbel_venta/data/ejemplo.dart';
import 'package:exbel_venta/data/repos.dart';
import 'package:exbel_venta/models/modelos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('caja 2 vende por la red local en la base de la caja 1', () async {
    final db = await AppDb.abrirCon(databaseFactoryFfi, inMemoryDatabasePath);
    final principal = Repos(db);
    repos = principal;
    await principal.ajustes.cargar();
    final admin = await principal.cajeros.guardar(usuario: 'Admin', nombre: 'Dueño', clave: '1234', administrador: true);
    await cargarEjemplo(cajeroId: admin.id);
    final t1 = await principal.caja.abrirTurno(admin.id, 50000, caja: 'Caja 1');

    final servidor = ServidorCaja(db, clave: '123456', descripcion: () => 'Prueba | Caja 1', puerto: 0, puertoUdp: 0);
    await servidor.iniciar();

    // Clave equivocada: no deja entrar.
    await expectLater(DatabaseRemota('127.0.0.1', '000000', puerto: servidor.puertoReal).ping(), throwsA(isA<ErrorNegocio>()));

    final remota = DatabaseRemota('127.0.0.1', '123456', puerto: servidor.puertoReal);
    expect((await remota.ping())['tienda'], 'Prueba | Caja 1');
    final caja2 = Repos(remota);
    await caja2.ajustes.cargar();

    // Cada caja tiene su turno.
    expect(await caja2.caja.turnoAbierto(caja: 'Caja 2'), isNull);
    final t2 = await caja2.caja.abrirTurno(admin.id, 30000, caja: 'Caja 2');
    expect(t2.caja, 'Caja 2');
    expect((await principal.caja.turnoAbierto(caja: 'Caja 1'))!.id, t1.id);

    // Venta en la caja 2: el inventario baja en la base de la caja 1.
    final leche = (await caja2.productos.porCodigo('1010'))!;
    final antes = leche.existencia;
    final v = await caja2.ventas.registrar(
      renglones: [Renglon.deProducto(leche, cantidad: 2)],
      pago: Pago(efectivoCentavos: 5800, recibidoCentavos: 10000),
      turnoId: t2.id,
      cajeroId: admin.id,
    );
    expect(v.folio, 1);
    expect((await principal.productos.porId(leche.id))!.existencia, antes - 2);

    // Venta en la caja 1: folio consecutivo compartido.
    final v1 = await principal.ventas.registrar(
      renglones: [Renglon.deProducto(leche, cantidad: 1)],
      pago: Pago(efectivoCentavos: 2900, recibidoCentavos: 2900),
      turnoId: t1.id,
      cajeroId: admin.id,
    );
    expect(v1.folio, 2);

    // Cortes separados por caja.
    expect((await caja2.caja.corteTurno(t2.id)).ventasCentavos, 5800);
    expect((await principal.caja.corteTurno(t1.id)).ventasCentavos, 2900);

    // Una transacción que falla se deshace completa.
    await expectLater(
      remota.transaction((tx) async {
        await tx.rawUpdate('UPDATE productos SET existencia = 0 WHERE id = ?', [leche.id]);
        throw const ErrorNegocio('falla a propósito');
      }),
      throwsA(isA<ErrorNegocio>()),
    );
    expect((await principal.productos.porId(leche.id))!.existencia, antes - 3);

    await servidor.detener();
    await expectLater(remota.ping(), throwsA(isA<ErrorNegocio>()));
    await remota.close();
    await db.close();
  });
}
