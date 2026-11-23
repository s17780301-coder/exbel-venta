import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../tema/tema.dart';

/// Minimizar, pantalla completa y cerrar (la app corre a pantalla completa
/// y no tiene la barra de Windows).
class BotonesVentana extends StatelessWidget {
  const BotonesVentana({super.key, this.oscuro = false, this.alCerrar});
  final bool oscuro;

  /// Si regresa false, no se cierra.
  final Future<bool> Function()? alCerrar;

  @override
  Widget build(BuildContext context) {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return const SizedBox.shrink();
    final color = oscuro ? ExColor.textoClaro : ExColor.texto2;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _Boton(
        tooltip: 'Minimizar',
        color: color,
        icono: Icons.remove,
        onTap: () => windowManager.minimize(),
      ),
      _Boton(
        tooltip: 'Pantalla completa / ventana',
        color: color,
        icono: Icons.fullscreen,
        onTap: () async => windowManager.setFullScreen(!await windowManager.isFullScreen()),
      ),
      _Boton(
        tooltip: 'Cerrar exBel venta',
        color: color,
        icono: Icons.close,
        peligro: true,
        onTap: () async {
          if (alCerrar != null && !await alCerrar!()) return;
          await windowManager.setFullScreen(false);
          await windowManager.close();
        },
      ),
    ]);
  }
}

class _Boton extends StatelessWidget {
  const _Boton({required this.tooltip, required this.color, required this.icono, required this.onTap, this.peligro = false});
  final String tooltip;
  final Color color;
  final IconData icono;
  final VoidCallback onTap;
  final bool peligro;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        hoverColor: peligro ? ExColor.rojo : ExColor.textoClaro2.withOpacity(0.25),
        child: SizedBox(width: 44, height: 34, child: Icon(icono, size: 18, color: color)),
      ),
    );
  }
}
