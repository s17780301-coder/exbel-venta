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
  test('manotazo con teclado que solo reporta 2 juntas activa', () {
    final d = DetectorPanico();
    var r = false;
    for (var i = 0; i < 8; i++) {
      r = d.alPresionar(i.isEven ? 1 : 2, t0.add(Duration(milliseconds: i * 40)), tecla: i) || r;
    }
    expect(r, isTrue);
  });
  test('lector de códigos rápido (sin teclas encimadas) no activa', () {
    final d = DetectorPanico();
    for (var i = 0; i < 13; i++) {
      expect(d.alPresionar(1, t0.add(Duration(milliseconds: i * 8)), tecla: i % 10), isFalse);
    }
  });
  test('escribir normal no activa', () {
    final d = DetectorPanico();
    // ~6 teclas por segundo con alguna encimada.
    for (var i = 0; i < 20; i++) {
      expect(d.alPresionar(i % 4 == 0 ? 2 : 1, t0.add(Duration(milliseconds: i * 160)), tecla: i % 7), isFalse);
    }
  });
}
