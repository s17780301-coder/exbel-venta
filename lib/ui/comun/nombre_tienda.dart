import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Nombre de la tienda con diseño: la primera palabra chica y espaciada
/// ("MISCELÁNEA") y el resto grande ("Karina") con una línea coral.
class NombreTienda extends StatelessWidget {
  const NombreTienda(this.nombre, {super.key, this.tamano = 26, this.oscuro = true, this.centrado = false});
  final String nombre;
  final double tamano;
  final bool oscuro;
  final bool centrado;

  @override
  Widget build(BuildContext context) {
    final palabras = nombre.trim().split(RegExp(r'\s+'));
    final principal = oscuro ? ExColor.blanco : ExColor.tinta;
    final secundario = oscuro ? ExColor.lavanda : ExColor.indigo;
    final alineado = centrado ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    if (palabras.length < 2) {
      return Text(nombre, overflow: TextOverflow.ellipsis, style: ExTexto.marca(tamano, color: principal));
    }
    final arriba = palabras.first.toUpperCase();
    final abajo = palabras.skip(1).join(' ');
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: alineado, children: [
      Text(arriba,
          style: ExTexto.texto(tamano * 0.38, color: secundario, peso: FontWeight.w600).copyWith(letterSpacing: tamano * 0.16, height: 1)),
      SizedBox(height: tamano * 0.06),
      Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Flexible(
          child: Text(abajo,
              overflow: TextOverflow.ellipsis,
              style: ExTexto.marca(tamano, color: principal, peso: FontWeight.w700).copyWith(height: 1.05)),
        ),
        Container(
          width: tamano * 0.22,
          height: tamano * 0.22,
          margin: EdgeInsets.only(left: tamano * 0.08, bottom: tamano * 0.16),
          decoration: const BoxDecoration(color: ExColor.acento, shape: BoxShape.circle),
        ),
      ]),
    ]);
  }
}
