import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'ajustes_repo.dart';
import 'caja_repo.dart';
import 'cajeros_repo.dart';
import 'clientes_repo.dart';
import 'productos_repo.dart';
import 'reportes_repo.dart';
import 'ventas_repo.dart';

/// Acceso a todos los datos de la tienda.
class Repos {
  Repos(this.db)
      : ajustes = AjustesRepo(db),
        productos = ProductosRepo(db),
        cajeros = CajerosRepo(db),
        caja = CajaRepo(db),
        clientes = ClientesRepo(db),
        ventas = VentasRepo(db),
        reportes = ReportesRepo(db);

  final Database db;
  final AjustesRepo ajustes;
  final ProductosRepo productos;
  final CajerosRepo cajeros;
  final CajaRepo caja;
  final ClientesRepo clientes;
  final VentasRepo ventas;
  final ReportesRepo reportes;
}

late Repos repos;

/// Cambia cada vez que se guarda algo; las pantallas lo escuchan para
/// refrescarse.
final cambiosDatos = ValueNotifier<int>(0);
void avisarCambio() => cambiosDatos.value++;
