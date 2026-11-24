import 'package:exbel_venta/core/emergencia.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 12);
  test('una tecla a la vez (lector de códigos) no activa', () {
    final d = DetectorPanico();
    for (var i = 0; i < 30; i++) {
      expect(d.alPresionar(1, t0.add(Duration(milliseconds: i * 5))), isFalse);
    }
  });
  test('dos teclas juntas no activa', () {
    expect(DetectorPanico().alPresionar(2, t0), isFalse);
  });
  test('cuatro teclas juntas activa una vez', () {
    final d = DetectorPanico();
    expect(d.alPresionar(4, t0), isTrue);
    expect(d.alPresionar(5, t0.add(const Duration(seconds: 1))), isFalse);
    expect(d.alPresionar(4, t0.add(const Duration(seconds: 25))), isTrue);
  });
  test('tres teclas dos veces seguidas activa', () {
    final d = DetectorPanico();
    expect(d.alPresionar(3, t0), isFalse);
    expect(d.alPresionar(3, t0.add(const Duration(milliseconds: 600))), isTrue);
  });
  test('tres teclas separadas por mucho tiempo no activa', () {
    final d = DetectorPanico();
    expect(d.alPresionar(3, t0), isFalse);
    expect(d.alPresionar(3, t0.add(const Duration(seconds: 5))), isFalse);
  });
}
