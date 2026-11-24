import 'dart:convert';
import 'dart:io';

import 'package:exbel_venta/core/db.dart';
import 'package:exbel_venta/data/repos.dart';
import 'package:exbel_venta/data/respaldo_fbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Respaldo pequeño hecho a mano con la misma estructura que el real.
const _muestra = 'AAIESEVBREVSAwENREVQQVJUQU1FTlRPUwwGU1lTREJBAAQBAklEAgNET00NBAAAAAAIBAgAAAAKBAQAAAAJBAAAAAALBAAAAAAWBAAAAAAABAEGTk9NQlJFAgNET00NBAAAAAAIBCUAAAAKBP8AAAAJBAAAAAALBAAAAAAWBAAAAAAACQMBCVBST0RVQ1RPUwwGU1lTREJBAAQBAklEAgNET00NBAAAAAAIBAgAAAAKBAQAAAAJBAAAAAALBAAAAAAWBAAAAAAABAEGQ09ESUdPAgNET00NBAAAAAAIBCUAAAAKBBQAAAAJBAAAAAALBAAAAAAWBAAAAAAABAELREVTQ1JJUENJT04CA0RPTQ0EAAAAAAgEJQAAAAoEMgAAAAkEAAAAAAsEAAAAABYEAAAAAAAEAQZQVkVOVEECA0RPTQ0EAAAAAAgEEAAAAAoECAAAAAkEAAAAAAsE/P///xYEAAAAAAAEAQZUVkVOVEECA0RPTQ0EAAAAAAgEDgAAAAoEAQAAAAkEAAAAAAsEAAAAABYEAAAAAAAEAQRERVBUAgNET00NBAAAAAAIBAgAAAAKBAQAAAAJBAAAAAALBAAAAAAWBAAAAAAACQgBDURFUEFSVEFNRU5UT1MABQEEUEtfWAAGAQQcAAAAAv0AARj9AAoJY3JvcXVldGFz9QAGAQQcAAAAAv0AAQX9AAoJQUJBUlJPVEVT9QAJCAEJUFJPRFVDVE9TAAUBBFBLX1gABgEEXAAAAAL9AAEB/QASEURPRyBDSE9XIENBQ0hPUlJP+gASEURvZyBDaG93IENhY2hvcnJv+AAECSfARPoAARjoAAYBBFgAAAAC/QABAv0ADg03NTAxMDcyMjEwMjY1+gAUE0RvZyBDaG93IFNvYnJlIDEwMGf6AAQBhqBV+gABGOgABgEEUAAAAAL9AAED/QAFCTc1MDH7MPoAEA9BcnJveiDRYW5k+iAxa2f6AAQEp2hV+gABBegACQo=';

void main() {
  setUpAll(sqfliteFfiInit);

  test('lee tablas del respaldo (.fbk)', () {
    final f = RespaldoFbk(base64.decode(_muestra));
    expect(f.valido, isTrue);
    final deps = f.filas('DEPARTAMENTOS').toList();
    expect(deps.map((d) => d['NOMBRE']), ['croquetas', 'ABARROTES']);
    final p = f.filas('PRODUCTOS').toList();
    expect(p.length, 3);
    expect(p[0]['DESCRIPCION'], 'Dog Chow Cachorro');
    expect(p[0]['TVENTA'], 'D');
    expect(p[0]['PVENTA'], 60.0);
    expect(p[2]['DESCRIPCION'], 'Arroz Ñandú 1kg');
    expect(p[2]['PVENTA'], 30.5);
    expect(f.filas('NO_EXISTE').toList(), isEmpty);
  });

  test('importa el respaldo con pieza o granel exacto', () async {
    final db = await AppDb.abrirCon(databaseFactoryFfi, inMemoryDatabasePath);
    repos = Repos(db);
    await repos.ajustes.cargar();
    final dir = await Directory.systemTemp.createTemp('fbk');
    final ruta = '${dir.path}/r.fbk';
    await File(ruta).writeAsBytes(base64.decode(_muestra));
    final c = await leerRespaldo(ruta);
    expect(c.productos.length, 3);
    expect(c.granel, 1);
    final (rp, _) = await importarRespaldo(c, clientes: false);
    expect(rp.nuevos, 3);
    final croq = (await repos.productos.porCodigo('DOG CHOW CACHORRO'))!;
    expect(croq.tipo, 'granel');
    expect(croq.departamentoNombre, 'croquetas');
    expect((await repos.productos.porCodigo('7501072210265'))!.tipo, 'unidad');
    expect((await repos.productos.porCodigo('750100000'))!.precioCentavos, 3050);
    await db.close();
  });
}
