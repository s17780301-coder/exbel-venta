import 'package:exbel_venta/core/actualizador.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compara versiones', () {
    expect(compararVersiones('0.10.0', '0.9.3'), 1);
    expect(compararVersiones('0.9.3', '0.9.3'), 0);
    expect(compararVersiones('0.9.2', '0.9.10'), -1);
    expect(compararVersiones('1.0', '0.99.99'), 1);
  });

}
