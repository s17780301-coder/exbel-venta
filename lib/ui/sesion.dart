import 'package:flutter/foundation.dart';

import '../models/modelos.dart';

/// Quién está en la caja y el turno abierto.
class Sesion extends ChangeNotifier {
  Cajero? cajero;
  Turno? turno;

  bool get activa => cajero != null && turno != null;

  void entrar(Cajero c, Turno t) {
    cajero = c;
    turno = t;
    notifyListeners();
  }

  void cambiarTurno(Turno? t) {
    turno = t;
    notifyListeners();
  }

  void salir() {
    cajero = null;
    turno = null;
    notifyListeners();
  }

  bool puede(String permiso) => cajero?.puede(permiso) ?? false;
}

final sesion = Sesion();
