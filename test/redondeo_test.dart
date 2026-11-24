import 'package:exbel_venta/core/formato.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redondeo a 50 centavos, al más cercano', () {
    expect(redondear50(1545), 1550);
    expect(redondear50(1520), 1500);
    expect(redondear50(1580), 1600);
    expect(redondear50(1525), 1550);
    expect(redondear50(1500), 1500);
    expect(redondear50(1550), 1550);
    expect(redondear50(1574), 1550);
    expect(redondear50(1575), 1600);
    expect(redondear50(10), 0);
  });
}
