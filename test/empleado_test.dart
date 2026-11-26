import 'package:exbel_venta/models/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el empleado no tiene ningún permiso fuera de Ventas', () {
    final e = Cajero(id: '1', usuario: 'ana', nombre: 'Ana', permisos: {Permiso.soloVentas, Permiso.productos});
    expect(e.empleado, isTrue);
    for (final p in Permiso.todos.keys) {
      expect(e.puede(p), isFalse, reason: p);
    }
  });

  test('el administrador puede todo y no es empleado', () {
    final a = Cajero(id: '2', usuario: 'dueno', nombre: 'Dueño', administrador: true, permisos: {Permiso.soloVentas});
    expect(a.empleado, isFalse);
    expect(a.puede(Permiso.configuracion), isTrue);
  });
}
