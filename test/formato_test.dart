import 'package:flutter_test/flutter_test.dart';
import 'package:exbel_venta/core/formato.dart';

void main() {
  test('formatoPesos', () {
    expect(formatoPesos(0), r'$0.00');
    expect(formatoPesos(5), r'$0.05');
    expect(formatoPesos(123450), r'$1,234.50');
    expect(formatoPesos(100000000), r'$1,000,000.00');
    expect(formatoPesos(-2550), r'-$25.50');
  });

  test('leerPesos', () {
    expect(leerPesos('1,234.5'), 123450);
    expect(leerPesos(r'$250'), 25000);
    expect(leerPesos(''), isNull);
    expect(leerPesos('abc'), isNull);
  });

  test('leerCantidad acepta coma o punto', () {
    expect(leerCantidad('2,5'), 2.5);
    expect(leerCantidad('2.5'), 2.5);
    expect(leerCantidad('x'), isNull);
  });

  test('formatoCantidad', () {
    expect(formatoCantidad(3), '3');
    expect(formatoCantidad(2.5), '2.5');
    expect(formatoCantidad(0.125), '0.125');
  });

  test('calcularImporte redondea al centavo', () {
    // 2.5 m de cable a $18.33 = $45.825 -> $45.83
    expect(calcularImporte(2.5, 1833), 4583);
  });
}
