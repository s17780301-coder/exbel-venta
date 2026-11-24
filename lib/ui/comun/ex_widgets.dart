import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tema/ex_icon.dart';
import '../tema/tema.dart';
import 'ex_ui.dart';

/// Etiqueta cuadrada (estado, lista de precios, contador).
class ExEtiqueta extends StatelessWidget {
  const ExEtiqueta(
    this.texto, {
    super.key,
    this.fondo = ExColor.blanco,
    this.color = ExColor.tinta,
    this.borde = true,
    this.negrita = false,
  });

  final String texto;
  final Color fondo;
  final Color color;
  final bool borde;
  final bool negrita;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fondo,
        border: borde ? Border.all(color: ExColor.linea) : null,
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: negrita ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

/// Filtro / pestaña cuadrada.
class ExFiltro extends StatelessWidget {
  const ExFiltro({
    super.key,
    required this.texto,
    required this.seleccionado,
    required this.onTap,
  });

  final String texto;
  final bool seleccionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: seleccionado ? ExColor.tinta : ExColor.blanco,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(
                color: seleccionado ? ExColor.tinta : ExColor.linea),
          ),
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 13,
              fontWeight: seleccionado ? FontWeight.w600 : FontWeight.w500,
              color: seleccionado ? ExColor.concreto : ExColor.tinta,
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra de avance cuadrada (existencia, uso del crédito).
class ExBarra extends StatelessWidget {
  const ExBarra({
    super.key,
    required this.valor,
    this.color = ExColor.tinta,
    this.fondo = ExColor.lineaSuave,
    this.alto = 4,
  });

  /// De 0 a 1.
  final double valor;
  final Color color;
  final Color fondo;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: alto,
      color: fondo,
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: valor.clamp(0.0, 1.0),
        child: Container(color: color),
      ),
    );
  }
}

/// Bloque blanco con borde, para agrupar contenido.
class ExSeccion extends StatelessWidget {
  const ExSeccion({
    super.key,
    required this.child,
    this.titulo,
    this.accion,
    this.oscuro = false,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final String? titulo;
  final Widget? accion;
  final bool oscuro;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFFECEAF7) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x142B2845), blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (titulo != null) ...[
            Row(children: [
              Expanded(
                child: Text(
                  titulo!,
                  style: ExTexto.titulo(17, color: ExColor.tinta),
                ),
              ),
              if (accion != null) accion!,
            ]),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

/// Cifra grande para tableros y cortes.
class ExKpi extends StatelessWidget {
  const ExKpi({
    super.key,
    required this.nombre,
    required this.valor,
    this.nota,
    this.destacado = false,
    this.alerta = false,
    this.onTap,
  });

  final String nombre;
  final String valor;
  final String? nota;
  final bool destacado;
  final bool alerta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fondo = alerta
        ? const Color(0xFFFBE3DC)
        : destacado
            ? const Color(0xFFECEAF7)
            : Colors.white;
    final colorValor = alerta ? const Color(0xFFB0573F) : (destacado ? const Color(0xFF34306A) : ExColor.tinta);
    return Material(
      color: fondo,
      borderRadius: BorderRadius.circular(16),
      shadowColor: const Color(0x332B2845),
      elevation: destacado || alerta ? 0 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: destacado ? Border.all(color: const Color(0xFFDCD8EF)) : (alerta ? Border.all(color: const Color(0xFFF1C9BC)) : null),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(nombre.toUpperCase(),
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Color(0xFF6B6785))),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(valor, style: ExTexto.titulo(28, color: colorValor, peso: FontWeight.w600)),
              ),
              if (nota != null) ...[
                const SizedBox(height: 4),
                Text(nota!, style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B6785))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cuadro con iniciales (cliente, cajero).
class ExAvatar extends StatelessWidget {
  const ExAvatar(this.nombre, {super.key, this.size = 36});

  final String nombre;
  final double size;

  String get _iniciales {
    final partes = nombre
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty && p[0].toUpperCase() != p[0].toLowerCase())
        .toList();
    if (partes.isEmpty) return '?';
    final a = partes.first[0];
    final b = partes.length > 1 ? partes[1][0] : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tono.de(nombre);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: t.fondo, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        _iniciales,
        style: ExTexto.titulo(size * 0.36, color: t.color),
      ),
    );
  }
}

/// Botón cuadrado solo con ícono.
class ExBotonIcono extends StatelessWidget {
  const ExBotonIcono({
    super.key,
    required this.icono,
    required this.tooltip,
    required this.onPressed,
    this.oscuro = false,
    this.size = 44,
  });

  final ExIcono icono;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool oscuro;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: oscuro ? const Color(0xFFECEAF7) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFDCD9EA)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: ExIcon(
                icono,
                color: const Color(0xFF4A4789),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Texto gris para listas vacías.
class ExVacio extends StatelessWidget {
  const ExVacio(this.texto, {super.key, this.accion});

  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Mosaico(Icons.inbox_rounded, tono: Tono.lavanda, tamano: 52),
            const SizedBox(height: 12),
            Text(texto,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ExColor.texto2, fontSize: 15)),
            if (accion != null) ...[const SizedBox(height: 16), accion!],
          ],
        ),
      ),
    );
  }
}

/// Barra de búsqueda redondeada. [grande] para la pantalla de inicio.
class ExBuscador extends StatelessWidget {
  const ExBuscador({
    super.key,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
    this.grande = false,
    this.enabled = true,
    this.atajo,
    this.onFlecha,
  });

  /// Flechas ↑ ↓ (±1) y Re Pág / Av Pág (±10) para moverse en los resultados.
  final ValueChanged<int>? onFlecha;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool grande;
  final bool enabled;
  final String? atajo;

  @override
  Widget build(BuildContext context) {
    final radio = BorderRadius.circular(grande ? 16 : 12);
    final campo = _campo(radio);
    final f = onFlecha;
    if (f == null) return campo;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
        final d = switch (e.logicalKey) {
          LogicalKeyboardKey.arrowDown => 1,
          LogicalKeyboardKey.arrowUp => -1,
          LogicalKeyboardKey.pageDown => 10,
          LogicalKeyboardKey.pageUp => -10,
          _ => 0,
        };
        if (d == 0) return KeyEventResult.ignored;
        f(d);
        return KeyEventResult.handled;
      },
      child: campo,
    );
  }

  Widget _campo(BorderRadius radio) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      style: ExTexto.texto(grande ? 18 : 15, peso: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: ExTexto.texto(grande ? 18 : 15, color: ExColor.texto2),
        contentPadding: EdgeInsets.symmetric(vertical: grande ? 22 : 14, horizontal: 8),
        prefixIcon: Padding(
          padding: EdgeInsets.only(left: grande ? 20 : 14, right: 8),
          child: ExIcon(ExIcono.buscar, size: grande ? 24 : 18, color: const Color(0xFF4A4789)),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: atajo == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 18),
                child: Center(
                  widthFactor: 1,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(color: ExColor.linea),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(atajo!,
                        style: ExTexto.mono(11, color: ExColor.texto2, peso: FontWeight.w500)),
                  ),
                ),
              ),
        border: OutlineInputBorder(borderRadius: radio),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: radio,
          borderSide: BorderSide(color: const Color(0xFFDCD9EA), width: grande ? 1.5 : 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radio,
          borderSide: const BorderSide(color: Color(0xFF4A4789), width: 1.8),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: radio,
          borderSide: const BorderSide(color: ExColor.lineaSuave),
        ),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// Símbolo junto a la marca. Usa ™ mientras el registro está en trámite;
/// cambia a ® cuando el IMPI otorgue el título.
const simboloMarca = '™';

/// Ícono de la marca: cuadro blanco redondeado (como exBel Dental) con una
/// bolsa de mandado índigo, alusiva a la tienda, y el punto coral.
class ExLogo extends StatelessWidget {
  const ExLogo({super.key, this.size = 32, this.conBorde = false});
  final double size;

  /// Sobre fondo claro se marca la orilla del cuadro blanco.
  final bool conBorde;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ExColor.blanco,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: conBorde ? Border.all(color: ExColor.linea) : null,
      ),
      child: CustomPaint(painter: _Bolsa()),
    );
  }
}

class _Bolsa extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final indigo = Paint()..color = ExColor.indigo;
    // Cuerpo de la bolsa (trapecio).
    final cuerpo = Path()
      ..moveTo(s * 0.20, s * 0.40)
      ..lineTo(s * 0.74, s * 0.40)
      ..lineTo(s * 0.70, s * 0.82)
      ..lineTo(s * 0.24, s * 0.82)
      ..close();
    canvas.drawPath(cuerpo, indigo);
    // Asa.
    final asa = Paint()
      ..color = ExColor.indigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075;
    canvas.drawArc(Rect.fromLTRB(s * 0.33, s * 0.22, s * 0.61, s * 0.54), math.pi, math.pi, false, asa);
    canvas.drawCircle(Offset(s * 0.80, s * 0.20), s * 0.095, Paint()..color = ExColor.acento);
  }

  @override
  bool shouldRepaint(_Bolsa oldDelegate) => false;
}

/// Nombre "exBel" como en el logotipo: "ex" delgado y "Bel" grueso.
class ExMarcaTexto extends StatelessWidget {
  const ExMarcaTexto({super.key, this.tamano = 14, this.oscuro = false});
  final double tamano;
  final bool oscuro;

  @override
  Widget build(BuildContext context) {
    return Text.rich(TextSpan(children: [
      TextSpan(
          text: 'ex',
          style: ExTexto.marca(tamano,
              color: oscuro ? ExColor.lavanda : ExColor.indigo, peso: FontWeight.w300)),
      TextSpan(
          text: 'Bel',
          style: ExTexto.marca(tamano, color: oscuro ? ExColor.blanco : ExColor.tinta)),
      TextSpan(
          text: simboloMarca,
          style: ExTexto.texto(tamano * 0.5,
              color: oscuro ? ExColor.textoClaro2 : ExColor.texto2)),
    ]));
  }
}

/// Marca exBel™ en texto, sencilla (como en la muestra B): sin ícono.
class ExMarca extends StatelessWidget {
  const ExMarca({super.key, this.oscuro = false, this.tamano = 16});
  final bool oscuro;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final color = oscuro ? ExColor.textoClaro : ExColor.tinta;
    return Text.rich(TextSpan(children: [
      TextSpan(text: 'exBel', style: ExTexto.marca(tamano, color: color, peso: FontWeight.w600)),
      TextSpan(text: simboloMarca, style: ExTexto.texto(tamano * 0.55, color: color)),
    ]));
  }
}

/// Encima del buscador: logotipo del negocio (si lo hay) y su nombre en
/// grande. Se edita con un toque.
class EncabezadoNegocio extends StatelessWidget {
  const EncabezadoNegocio({
    super.key,
    required this.negocio,
    required this.logo,
    required this.onEditar,
    this.tamano = 40,
  });

  final String negocio;

  /// Ruta de la imagen del negocio; vacía si no tiene.
  final String logo;
  final VoidCallback onEditar;
  final double tamano;

  @override
  Widget build(BuildContext context) {
    final imagen = logo.isEmpty ? null : File(logo);
    return Tooltip(
      message: 'Toca para cambiar el nombre o el logotipo',
      child: InkWell(
        onTap: onEditar,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (imagen != null && imagen.existsSync()) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(tamano * 0.4),
                child: Image.file(
                  imagen,
                  height: tamano * 2.2,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              SizedBox(height: tamano * 0.3),
            ],
            Text(
              negocio.isEmpty ? 'Mi tienda' : negocio,
              textAlign: TextAlign.center,
              style: ExTexto.titulo(tamano),
            ),
          ]),
        ),
      ),
    );
  }
}


/// Para moverse con flechas en una lista de filas del mismo alto: recorre la
/// lista para que la fila [i] quede a la vista.
void seguirFila(ScrollController sc, int i, double alto) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!sc.hasClients || i < 0) return;
    final pos = sc.position;
    final arriba = i * alto, abajo = arriba + alto;
    if (arriba < pos.pixels) {
      sc.jumpTo(arriba.clamp(0, pos.maxScrollExtent));
    } else if (abajo > pos.pixels + pos.viewportDimension) {
      sc.jumpTo((abajo - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    }
  });
}

/// Igual, para filas de alto distinto: la fila elegida lleva la clave [k].
void verFila(GlobalKey k, {required bool bajando}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final c = k.currentContext;
    if (c == null) return;
    Scrollable.ensureVisible(c,
        alignmentPolicy: bajando ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
  });
}
