import 'package:flutter/material.dart';

/// Íconos propios de exBel: trazos rectos, puntas cuadradas y esquinas
/// en ángulo. Se dibujan sobre una cuadrícula de 24 × 24.
enum ExIcono {
  vender,
  cotizar,
  apartado,
  clientes,
  inventario,
  flete,
  compras,
  reportes,
  corte,
  factura,
  buscar,
  escanear,
  mas,
  menos,
  cerrar,
  ajustes,
  alerta,
  check,
  flecha,
  editar,
  mensaje,
  imprimir,
  sincronizar,
  calendario,
  basura,
  pausa,
  devolver,
  efectivo,
  tarjeta,
  transferencia,
  credito,
  chispa,
  entrada,
  conteo,
}

class ExIcon extends StatelessWidget {
  const ExIcon(this.icono, {super.key, this.size = 20, this.color, this.grosor = 2});

  final ExIcono icono;
  final double size;
  final Color? color;
  final double grosor;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF0E1013);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _Pintor(icono, c, grosor)),
    );
  }
}

class _Pintor extends CustomPainter {
  _Pintor(this.icono, this.color, this.grosor);

  final ExIcono icono;
  final Color color;
  final double grosor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;

    // La lupa y las personas son redondas: así se reconocen al instante.
    final redondo = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = grosor
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void persona(double cx, double cabeza, double hombros, double ancho) {
      canvas.drawCircle(Offset(cx, cabeza), 3.6, redondo);
      final m = ancho / 2;
      canvas.drawPath(
        Path()
          ..moveTo(cx - m, 21)
          ..lineTo(cx - m, hombros + 4)
          ..quadraticBezierTo(cx - m, hombros, cx - m + 4, hombros)
          ..lineTo(cx + m - 4, hombros)
          ..quadraticBezierTo(cx + m, hombros, cx + m, hombros + 4)
          ..lineTo(cx + m, 21),
        redondo,
      );
    }

    void r(double x, double y, double w, double h) =>
        canvas.drawRect(Rect.fromLTWH(x, y, w, h), p);
    void l(List<double> pts) {
      final path = Path()..moveTo(pts[0], pts[1]);
      for (var i = 2; i < pts.length; i += 2) {
        path.lineTo(pts[i], pts[i + 1]);
      }
      canvas.drawPath(path, p);
    }

    switch (icono) {
      case ExIcono.vender:
        r(3, 4, 18, 12);
        l([8, 20, 16, 20]);
        l([12, 16, 12, 20]);
      case ExIcono.cotizar:
        r(5, 3, 14, 18);
        l([9, 8, 15, 8]);
        l([9, 12, 15, 12]);
        l([9, 16, 12, 16]);
      case ExIcono.apartado:
        r(4, 4, 16, 16);
        l([4, 10, 20, 10]);
        l([10, 10, 10, 20]);
      case ExIcono.clientes:
        persona(12, 7.5, 14, 14);
      case ExIcono.inventario:
        l([3, 7, 12, 3, 21, 7, 21, 17, 12, 21, 3, 17, 3, 7]);
        l([3, 7, 12, 11, 21, 7]);
        l([12, 11, 12, 21]);
      case ExIcono.flete:
        r(2, 7, 12, 10);
        l([14, 10, 19, 10, 22, 13, 22, 17, 14, 17]);
        r(5, 17, 3, 3);
        r(16, 17, 3, 3);
      case ExIcono.compras:
        l([3, 3, 6, 3, 8, 15, 20, 15, 22, 7, 7, 7]);
        r(8, 18, 3, 3);
        r(17, 18, 3, 3);
      case ExIcono.reportes:
        l([3, 21, 21, 21]);
        r(5, 11, 3, 7);
        r(11, 6, 3, 12);
        r(17, 14, 3, 4);
      case ExIcono.corte:
        r(3, 6, 18, 12);
        r(10, 10, 4, 4);
      case ExIcono.factura:
        r(3, 3, 18, 18);
        l([3, 9, 21, 9]);
        l([9, 3, 9, 21]);
      case ExIcono.buscar:
        canvas.drawCircle(const Offset(10.5, 10.5), 6.5, redondo);
        canvas.drawLine(const Offset(15.5, 15.5), const Offset(20.5, 20.5), redondo);
      case ExIcono.escanear:
        l([3, 8, 3, 3, 8, 3]);
        l([16, 3, 21, 3, 21, 8]);
        l([21, 16, 21, 21, 16, 21]);
        l([8, 21, 3, 21, 3, 16]);
        l([7, 12, 17, 12]);
      case ExIcono.mas:
        l([12, 5, 12, 19]);
        l([5, 12, 19, 12]);
      case ExIcono.menos:
        l([5, 12, 19, 12]);
      case ExIcono.cerrar:
        l([5, 5, 19, 19]);
        l([19, 5, 5, 19]);
      case ExIcono.ajustes:
        r(4, 4, 16, 16);
        r(9, 9, 6, 6);
        l([12, 1, 12, 4]);
        l([12, 20, 12, 23]);
      case ExIcono.alerta:
        l([12, 3, 22, 21, 2, 21, 12, 3]);
        l([12, 10, 12, 14]);
        l([12, 17, 12, 17.5]);
      case ExIcono.check:
        l([4, 12, 10, 18, 20, 6]);
      case ExIcono.flecha:
        l([5, 12, 19, 12]);
        l([13, 6, 19, 12, 13, 18]);
      case ExIcono.editar:
        l([4, 20, 4, 16, 16, 4, 20, 8, 8, 20, 4, 20]);
      case ExIcono.mensaje:
        l([3, 4, 21, 4, 21, 16, 9, 16, 4, 20, 4, 16, 3, 16, 3, 4]);
      case ExIcono.imprimir:
        r(6, 3, 12, 5);
        r(3, 8, 18, 9);
        r(7, 14, 10, 7);
      case ExIcono.sincronizar:
        l([4, 12, 4, 6, 17, 6]);
        l([14, 3, 17, 6, 14, 9]);
        l([20, 12, 20, 18, 7, 18]);
        l([10, 21, 7, 18, 10, 15]);
      case ExIcono.calendario:
        r(3, 5, 18, 16);
        l([3, 10, 21, 10]);
        l([8, 3, 8, 7]);
        l([16, 3, 16, 7]);
      case ExIcono.basura:
        l([4, 6, 20, 6]);
        r(6, 6, 12, 15);
        l([9, 3, 15, 3]);
        l([10, 10, 10, 17]);
        l([14, 10, 14, 17]);
      case ExIcono.pausa:
        r(6, 5, 4, 14);
        r(14, 5, 4, 14);
      case ExIcono.devolver:
        l([9, 5, 4, 10, 9, 15]);
        l([4, 10, 20, 10, 20, 20]);
      case ExIcono.efectivo:
        r(2, 6, 20, 12);
        r(9, 9, 6, 6);
      case ExIcono.tarjeta:
        r(2, 5, 20, 14);
        l([2, 10, 22, 10]);
        l([6, 15, 10, 15]);
      case ExIcono.transferencia:
        l([4, 8, 18, 8]);
        l([14, 4, 18, 8, 14, 12]);
        l([20, 16, 6, 16]);
        l([10, 12, 6, 16, 10, 20]);
      case ExIcono.credito:
        r(3, 7, 18, 13);
        l([8, 7, 8, 3, 16, 3, 16, 7]);
        l([3, 12, 21, 12]);
      case ExIcono.chispa:
        l([12, 3, 12, 7]);
        l([12, 17, 12, 21]);
        l([3, 12, 7, 12]);
        l([17, 12, 21, 12]);
        l([6, 6, 8, 8]);
        l([16, 16, 18, 18]);
        l([6, 18, 8, 16]);
        l([16, 8, 18, 6]);
      case ExIcono.entrada:
        l([12, 3, 12, 15]);
        l([7, 10, 12, 15, 17, 10]);
        l([3, 15, 3, 21, 21, 21, 21, 15]);
      case ExIcono.conteo:
        r(4, 3, 16, 18);
        l([8, 8, 10, 10, 13, 7]);
        l([8, 15, 16, 15]);
    }
  }

  @override
  bool shouldRepaint(_Pintor old) =>
      old.icono != icono || old.color != color || old.grosor != grosor;
}
