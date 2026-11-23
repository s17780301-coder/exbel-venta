import 'dart:math';

final _aleatorio = Random.secure();

/// UUID v4. Se generan en cada caja para que los registros no choquen
/// cuando se sincronicen con la nube.
String nuevoId() {
  final b = List<int>.generate(16, (_) => _aleatorio.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// Fecha local de la operación (para cortes por día).
String ahoraLocal() => DateTime.now().toIso8601String();

/// Marca de tiempo UTC (para saber qué cambió al sincronizar).
String ahoraUtc() => DateTime.now().toUtc().toIso8601String();
