import 'dart:convert';
import 'dart:io';

import 'package:exbel_venta/core/db.dart';
import 'package:exbel_venta/data/repos.dart';
import 'package:exbel_venta/data/respaldo_fbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Respaldo pequeño hecho a mano con la misma estructura que el real.
const _muestra = 'AAIESEVBREVSAwENREVQQVJUQU1FTlRPUwwGU1lTREJBAAQBAklEAgNET00NBAAAAAAIBAgAAAAKBAQAAAAJBAAAAAALBAAAAAAWBAAAAAAABAEGTk9NQlJFAgNET00NBAAAAAAIBCUAAAAKBP8AAAAJBAAAAAALBAAAAAAWBAAAAAAACQMBCVBST0RVQ1RPUwwGU1lTREJBAAQBAklEAgNET00NBAAAAAAIBAgAAAAKBAQAAAAJBAAAAAALBAAAAAAWBAAAAAAABAEGQ09ESUdPAgNET00NBAAAAAAIBCUAAAAKBBQAAAAJBAAAAAALBAAAAAAWBAAAAAAABAELREVTQ1JJUENJT04CA0RPTQ0EAAAAAAgEJQAAAAoEMgAAAAkEAAAAAAsEAAAAABYEAAAAAAAEAQZQVkVOVEECA0RPTQ0EAAAAAAgEEAAAAAoECAAAAAkEAAAAAAsE/P///xYEAAAAAAAEAQZUVkVOVEECA0RPTQ0EAAAAAAgEDgAAAAoEAQAAAAkEAAAAAAsEAAAAABYEAAAAAA8ECQAAAAUVCAAAAAAATCcECgAAAERFRkFVTFQgMAAjBBQAAABUaXBvIGRlIHZlbnRhOiBVIG8gRAAEAQRERVBUAgNET00NBAAAAAAIBAgAAAAKBAQAAAAJBAAAAAALBAAAAAAWBAAAAAAACQMBBVZBQ0lBDAZTWVNEQkEABAECSUQCA0RPTQ0EAAAAAAgECAAAAAoEBAAAAAkEAAAAAAsEAAAAABYEAAAAAAAEAQZOT01CUkUCA0RPTQ0EAAAAAAgEJQAAAAoE/wAAAAkEAAAAAAsEAAAAABYEAAAAAAAJCAENREVQQVJUQU1FTlRPUwAFAQRQS19YAAYBBBIBAAARBBwAAAAC/QABGP0ACgljcm9xdWV0YXP1AAYBBBIBAAARBBwAAAAC/QABBf0ACglBQkFSUk9URVP1AAkIAQVWQUNJQQAFAQRQS19YAAkIAQlQUk9EVUNUT1MABQEEUEtfWAAGAQQSAAAAEQRcAAAAAv0AAQH9ABIRRE9HIENIT1cgQ0FDSE9SUk/6ABIRRG9nIENob3cgQ2FjaG9ycm/4AAQJJ8BE+gABGOgABgEEEgAAABEEWAAAAAL9AAEC/QAODTc1MDEwNzIyMTAyNjX6ABQTRG9nIENob3cgU29icmUgMTAwZ/oABAGGoFX6AAEY6AAGAQQSAAAAEQRQAAAAAv0AAQP9AAUJNzUwMfsw+gAQD0Fycm96INFhbmT6IDFrZ/oABASnaFX6AAEF6AAJCg==';

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
    expect(f.filas('VACIA').toList(), isEmpty);
    expect(f.campos('PRODUCTOS').length, 6);
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
