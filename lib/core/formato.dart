/// Utilidades de formato. El dinero se maneja SIEMPRE en centavos (int)
/// para evitar errores de redondeo con decimales.
library;

/// 123450 -> "$1,234.50"
String formatoPesos(int centavos) {
  final negativo = centavos < 0;
  final abs = centavos.abs();
  final pesos = (abs ~/ 100).toString();
  final cent = (abs % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < pesos.length; i++) {
    if (i > 0 && (pesos.length - i) % 3 == 0) buf.write(',');
    buf.write(pesos[i]);
  }
  return '${negativo ? '-' : ''}\$${buf.toString()}.$cent';
}

/// "1,234.5" o "$1234.50" -> 123450. Regresa null si no es un número.
int? leerPesos(String texto) {
  final limpio = texto.replaceAll(',', '').replaceAll('\$', '').trim();
  if (limpio.isEmpty) return null;
  final v = double.tryParse(limpio);
  if (v == null) return null;
  return (v * 100).round();
}

/// Cantidades: acepta coma o punto como decimal ("2,5" o "2.5").
double? leerCantidad(String texto) {
  final limpio = texto.trim().replaceAll(',', '.');
  if (limpio.isEmpty) return null;
  return double.tryParse(limpio);
}

/// 3.0 -> "3", 2.5 -> "2.5", 0.125 -> "0.125"
String formatoCantidad(double cantidad) {
  if (cantidad == cantidad.roundToDouble()) return cantidad.toInt().toString();
  var s = cantidad.toStringAsFixed(3);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

/// Importe de un renglón: cantidad × precio, redondeado al centavo.
int calcularImporte(double cantidad, int precioCentavos) =>
    (cantidad * precioCentavos).round();

String _dos(int n) => n.toString().padLeft(2, '0');

/// "21/11/2026 17:58"
String formatoFechaHora(DateTime f) =>
    '${_dos(f.day)}/${_dos(f.month)}/${f.year} ${_dos(f.hour)}:${_dos(f.minute)}';

/// "21/11/2026"
String formatoFecha(DateTime f) => '${_dos(f.day)}/${_dos(f.month)}/${f.year}';
