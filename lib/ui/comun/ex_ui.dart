import 'package:flutter/material.dart';

import '../tema/tema.dart';

/// Par de colores pastel (fondo, ícono) para mosaicos y avatares.
class Tono {
  const Tono(this.fondo, this.color);
  final Color fondo;
  final Color color;

  static const lavanda = Tono(Color(0xFFE4E1F7), Color(0xFF4A4789));
  static const coral = Tono(Color(0xFFFBE3DC), Color(0xFFB0573F));
  static const verde = Tono(Color(0xFFDDEEE4), Color(0xFF3D7A55));
  static const ambar = Tono(Color(0xFFFDF0D5), Color(0xFF9A6B15));
  static const azul = Tono(Color(0xFFDCE8F6), Color(0xFF3B6591));
  static const rosa = Tono(Color(0xFFF1E0F0), Color(0xFF8A4A86));
  static const gris = Tono(Color(0xFFE9E8EE), Color(0xFF5A5675));

  static const todos = [lavanda, coral, verde, ambar, azul, rosa];

  /// Siempre el mismo tono para el mismo texto (departamento, cliente…).
  static Tono de(String texto) {
    var h = 0;
    for (final c in texto.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return todos[h % todos.length];
  }
}

/// Medidas y sombras comunes.
abstract final class ExEstilo {
  static const fondo = Color(0xFFF4F3F8);
  static const superficie = Color(0xFFFCFCFD);
  static const tarjeta = Color(0xFFFFFFFF);
  static const linea = Color(0xFFE3E1EE);
  static const lineaFila = Color(0xFFE9E7F2);
  static const suave = Color(0xFFECEAF7);
  static const texto2 = Color(0xFF6B6785);
  static const primario = Color(0xFF4A4789);
  static const primarioOscuro = Color(0xFF34306A);
  static const sombra = [BoxShadow(color: Color(0x142B2845), blurRadius: 3, offset: Offset(0, 1))];
  static const radio = 16.0;
}

/// Cuadro redondeado de color con un ícono.
class Mosaico extends StatelessWidget {
  const Mosaico(this.icono, {super.key, this.tono = Tono.lavanda, this.tamano = 40});
  final IconData icono;
  final Tono tono;
  final double tamano;

  @override
  Widget build(BuildContext context) => Container(
        width: tamano,
        height: tamano,
        decoration: BoxDecoration(color: tono.fondo, borderRadius: BorderRadius.circular(tamano * 0.3)),
        alignment: Alignment.center,
        child: Icon(icono, size: tamano * 0.52, color: tono.color),
      );
}

/// Avatar con iniciales y color fijo según el texto.
class AvatarColor extends StatelessWidget {
  const AvatarColor(this.texto, {super.key, this.tamano = 36, this.redondo = true, this.tono, this.anillo = false});
  final String texto;
  final double tamano;
  final bool redondo;
  final Tono? tono;
  final bool anillo;

  String get _iniciales {
    final p = texto.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty && RegExp(r'[A-Za-zÁÉÍÓÚÑáéíóúñ0-9]').hasMatch(x[0])).toList();
    if (p.isEmpty) return '?';
    if (p.length == 1) return p.first.substring(0, p.first.length >= 2 ? 2 : 1).toUpperCase();
    return (p[0][0] + p[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = tono ?? Tono.de(texto);
    return Container(
      width: tamano,
      height: tamano,
      decoration: BoxDecoration(
        color: t.fondo,
        shape: redondo ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: redondo ? null : BorderRadius.circular(tamano * 0.3),
        boxShadow: anillo
            ? [const BoxShadow(color: ExEstilo.superficie, spreadRadius: 3), BoxShadow(color: t.color.withOpacity(0.35), spreadRadius: 4.5)]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(_iniciales, style: ExTexto.titulo(tamano * 0.36, color: t.color)),
    );
  }
}

/// Botón blanco con mosaico de color, texto y tecla rápida.
class BotonAccion extends StatelessWidget {
  const BotonAccion({super.key, required this.icono, required this.texto, required this.onTap, this.tecla, this.tono = Tono.lavanda, this.peligro = false});
  final IconData icono;
  final String texto;
  final String? tecla;
  final VoidCallback? onTap;
  final Tono tono;
  final bool peligro;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ExEstilo.tarjeta,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: peligro ? const Color(0xFFE9B8A8) : ExEstilo.linea),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Mosaico(icono, tono: peligro ? Tono.coral : tono, tamano: 32),
            const SizedBox(width: 10),
            Flexible(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(texto,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: peligro ? Tono.coral.color : ExColor.tinta, height: 1.2)),
                if (tecla != null) Text(tecla!, style: const TextStyle(fontSize: 11, color: ExEstilo.texto2)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Tecla dibujada como tecla de teclado.
class Tecla extends StatelessWidget {
  const Tecla(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: ExEstilo.tarjeta,
          borderRadius: BorderRadius.circular(5),
          border: const Border(
            top: BorderSide(color: Color(0xFFDCD8EF)),
            left: BorderSide(color: Color(0xFFDCD8EF)),
            right: BorderSide(color: Color(0xFFDCD8EF)),
            bottom: BorderSide(color: Color(0xFFDCD8EF), width: 2),
          ),
        ),
        child: Text(texto, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ExEstilo.primarioOscuro)),
      );
}

/// Atajo del pie: tecla + texto, se puede pulsar.
class Atajo extends StatelessWidget {
  const Atajo(this.tecla, this.texto, this.onTap, {super.key});
  final String tecla;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Tecla(tecla),
            const SizedBox(width: 6),
            Text(texto, style: const TextStyle(fontSize: 12.5, color: ExColor.tinta, fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}

/// Tarjeta blanca redondeada con sombra suave.
class Tarjeta extends StatelessWidget {
  const Tarjeta({super.key, required this.child, this.padding = EdgeInsets.zero, this.color = ExEstilo.tarjeta});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(ExEstilo.radio), boxShadow: ExEstilo.sombra),
        child: child,
      );
}

/// Título de sección: mosaico de color, nombre y (opcional) subtítulo.
class TituloSeccion extends StatelessWidget {
  const TituloSeccion(this.titulo, {super.key, required this.icono, required this.tono, this.subtitulo});
  final String titulo;
  final IconData icono;
  final Tono tono;
  final String? subtitulo;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Mosaico(icono, tono: tono, tamano: 44),
        const SizedBox(width: 14),
        Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: ExTexto.titulo(24, color: ExColor.tinta, peso: FontWeight.w700)),
          if (subtitulo != null) Text(subtitulo!, style: const TextStyle(fontSize: 13, color: ExEstilo.texto2)),
        ]),
      ]);
}
