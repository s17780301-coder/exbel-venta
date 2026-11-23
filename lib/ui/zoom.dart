import 'package:flutter/material.dart';

/// Tamaño de toda la pantalla (1.0 = 100 %). Se cambia en Configuración.
final zoomPantalla = ValueNotifier<double>(1.15);

/// Agranda toda la app de forma pareja (letras, botones, tablas y
/// diálogos), como si la pantalla tuviera menos resolución.
class ZoomPantalla extends StatelessWidget {
  const ZoomPantalla({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: zoomPantalla,
      builder: (context, z, _) {
        final mq = MediaQuery.of(context);
        if ((z - 1).abs() < 0.01) return child;
        final tam = mq.size / z;
        return MediaQuery(
          data: mq.copyWith(size: tam),
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(width: tam.width, height: tam.height, child: child),
          ),
        );
      },
    );
  }
}

/// Alto máximo de un diálogo para que quepa en pantallas chicas.
double altoDialogo(BuildContext context, double ideal) =>
    (MediaQuery.of(context).size.height - 64).clamp(320.0, ideal);

double anchoDialogo(BuildContext context, double ideal) =>
    (MediaQuery.of(context).size.width - 64).clamp(360.0, ideal);
