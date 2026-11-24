import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Convierte el PDF del ticket en una imagen y la manda en ESC/POS
/// (GS v 0), como lo hacen los puntos de venta: sale a todo el ancho del
/// papel, nítido, sin que Windows lo encoja.
Future<Uint8List> escposDesdePdf(Uint8List pdf, {required int anchoMm}) async {
  final puntos = anchoMm >= 80 ? 576 : 384; // 72 mm u 48 mm imprimibles a 203 ppp
  final anchoImprimibleMm = anchoMm >= 80 ? 72.0 : 48.0;
  final dpi = puntos / (anchoImprimibleMm / 25.4);
  final b = BytesBuilder();
  b.add(const [0x1B, 0x40]); // ESC @: inicia
  await for (final pagina in Printing.raster(pdf, dpi: dpi)) {
    final px = pagina.pixels; // RGBA
    final w = pagina.width, h = pagina.height;
    final bytesFila = puntos ~/ 8;
    // Quita el blanco de abajo para no gastar papel.
    var ultima = h - 1;
    bool filaBlanca(int y) {
      for (var x = 0; x < w && x < puntos; x++) {
        final i = (y * w + x) * 4;
        if (_negro(px, i)) return false;
      }
      return true;
    }

    while (ultima > 0 && filaBlanca(ultima)) {
      ultima--;
    }
    final alto = ultima + 1;
    for (var y0 = 0; y0 < alto; y0 += 256) {
      final filas = (alto - y0) < 256 ? (alto - y0) : 256;
      b.add([0x1D, 0x76, 0x30, 0x00, bytesFila & 0xFF, bytesFila >> 8, filas & 0xFF, filas >> 8]);
      final banda = Uint8List(bytesFila * filas);
      for (var y = 0; y < filas; y++) {
        for (var x = 0; x < puntos && x < w; x++) {
          final i = ((y0 + y) * w + x) * 4;
          if (_negro(px, i)) banda[y * bytesFila + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
      b.add(banda);
    }
  }
  b.add(const [0x1B, 0x64, 0x04]); // avanza 4 renglones
  b.add(const [0x1D, 0x56, 0x42, 0x00]); // corta (si la impresora tiene cortador)
  return b.toBytes();
}

bool _negro(Uint8List px, int i) {
  if (px[i + 3] < 128) return false; // transparente = blanco
  final lum = (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) ~/ 1000;
  return lum < 150;
}
