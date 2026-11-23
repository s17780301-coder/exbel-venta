import 'package:exbel_venta/core/bascula.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lee el peso de los formatos comunes de báscula', () {
    expect(leerPesoTexto('  0.250kg'), 0.25);
    expect(leerPesoTexto('ST,GS,+  1.235kg'), 1.235);
    expect(leerPesoTexto('W: 0,500 kg'), 0.5);
    expect(leerPesoTexto(' 00250 '), 0.25); // Toledo, gramos sin punto
    expect(leerPesoTexto('  250.0 g'), 0.25);
    expect(leerPesoTexto('  1.00 lb'), 0.454);
    expect(leerPesoTexto('   '), isNull);
  });
}
