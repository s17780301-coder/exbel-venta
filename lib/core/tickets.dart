import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/ajustes_repo.dart';
import '../data/repos.dart';
import '../models/modelos.dart';
import 'formato.dart';

/// Las letras estándar del PDF solo traen el alfabeto latino básico.
String t(String s) {
  const cambios = {
    '″': '"', '′': "'", '“': '"', '”': '"', '‘': "'", '’': "'",
    '–': '-', '—': '-', '…': '...', '·': '-', '™': '(TM)', '¡': '!', '¿': '?',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final c = String.fromCharCode(r);
    if (cambios.containsKey(c)) {
      b.write(cambios[c]);
    } else if (r < 256) {
      b.write(c);
    } else {
      b.write('?');
    }
  }
  return b.toString();
}

PdfPageFormat formatoTicket() {
  // Ancho que de verdad imprime la impresora (58 mm → 48 mm, 80 mm → 72 mm).
  final ancho = repos.ajustes.entero(Ajuste.ticketAncho) == 80 ? 72.0 : 48.0;
  return PdfPageFormat(ancho * PdfPageFormat.mm, double.infinity, marginAll: 1 * PdfPageFormat.mm);
}

pw.Widget _fila(String a, String b, {bool negrita = false, double tamano = 9}) => pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
            child: pw.Text(t(a), style: pw.TextStyle(fontSize: tamano, fontWeight: negrita ? pw.FontWeight.bold : null))),
        pw.Text(t(b), style: pw.TextStyle(fontSize: tamano, fontWeight: negrita ? pw.FontWeight.bold : null)),
      ],
    );

pw.Widget _linea() => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Container(height: 0.5, color: PdfColors.grey700),
    );

List<pw.Widget> _encabezado() {
  final a = repos.ajustes;
  final logo = a.texto(Ajuste.logoNegocio);
  final f = logo.isEmpty ? null : File(logo);
  return [
    if (f != null && f.existsSync())
      pw.Center(child: pw.Image(pw.MemoryImage(f.readAsBytesSync()), height: 40, fit: pw.BoxFit.contain)),
    pw.Text(t(a.texto(Ajuste.nombreNegocio).toUpperCase()),
        textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
    for (final x in [a.texto(Ajuste.direccion), a.texto(Ajuste.telefono), a.texto(Ajuste.rfc), a.texto(Ajuste.ticketEncabezado)])
      if (x.trim().isNotEmpty) pw.Text(t(x), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
  ];
}

/// Ticket de venta.
Future<Uint8List> ticketVenta(Venta v, List<LineaVendida> lineas, {bool copia = false}) async {
  final a = repos.ajustes;
  final doc = pw.Document();
  var iva = 0, ieps = 0;
  if (a.si(Ajuste.ticketDesglosarImpuestos)) {
    final f = await repos.db.query('venta_detalle', columns: ['importe_centavos', 'iva', 'ieps'],
        where: 'venta_id = ?', whereArgs: [v.id]);
    for (final m in f) {
      final (i1, i2) = desgloseImpuestos(m['importe_centavos'] as int, (m['iva'] as num).toDouble(), (m['ieps'] as num).toDouble());
      iva += i1;
      ieps += i2;
    }
  }
  final pago = v.pago;
  final piezas = lineas.fold<double>(0, (s, l) => s + l.cantidad);
  doc.addPage(pw.Page(
    pageFormat: formatoTicket(),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      ..._encabezado(),
      _linea(),
      if (copia) pw.Text('*** COPIA ***', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      if (v.cancelada) pw.Text('*** CANCELADA ***', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      _fila('Folio ${v.folio}', formatoFechaHora(v.fecha)),
      _fila('Cajero: ${v.cajeroNombre ?? ''}', ''),
      if (v.clienteNombre != null) _fila('Cliente: ${v.clienteNombre}', ''),
      _linea(),
      for (final l in lineas) ...[
        pw.Text(t(l.descripcion), style: const pw.TextStyle(fontSize: 9)),
        _fila('  ${formatoCantidad(l.cantidad)} x ${formatoPesos(l.precioCentavos)}', formatoPesos(l.importeCentavos)),
      ],
      _linea(),
      _fila('Artículos: ${formatoCantidad(piezas)}', ''),
      if (iva > 0) _fila('IVA incluido', formatoPesos(iva)),
      if (ieps > 0) _fila('IEPS incluido', formatoPesos(ieps)),
      _fila('TOTAL', formatoPesos(v.totalCentavos), negrita: true, tamano: 11),
      pw.SizedBox(height: 3),
      if (pago.efectivoCentavos > 0) ...[
        _fila('Efectivo', formatoPesos(pago.recibidoCentavos > 0 ? pago.recibidoCentavos : pago.efectivoCentavos)),
        if (pago.recibidoCentavos > pago.efectivoCentavos)
          _fila('Cambio', formatoPesos(pago.recibidoCentavos - pago.efectivoCentavos), negrita: true),
      ],
      if (pago.tarjetaCentavos > 0) _fila('Tarjeta${pago.referencia.isEmpty ? '' : ' (${pago.referencia})'}', formatoPesos(pago.tarjetaCentavos)),
      if (pago.transferenciaCentavos > 0) _fila('Transferencia', formatoPesos(pago.transferenciaCentavos)),
      if (pago.valesCentavos > 0) _fila('Vales', formatoPesos(pago.valesCentavos)),
      if (pago.dolaresCentavos > 0) _fila('Dólares (en pesos)', formatoPesos(pago.dolaresCentavos)),
      if (pago.creditoCentavos > 0) _fila('A crédito', formatoPesos(pago.creditoCentavos), negrita: true),
      if (v.notas.isNotEmpty) ...[_linea(), pw.Text(t(v.notas), style: const pw.TextStyle(fontSize: 8.5))],
      _linea(),
      pw.Text(t(a.texto(Ajuste.ticketPie)), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 4),
      pw.Text('exBel venta', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
    ]),
  ));
  return doc.save();
}

/// Comprobante de corte.
Future<Uint8List> ticketCorte(Corte c, {int? contadoCentavos, int? fondoSiguienteCentavos}) async {
  final doc = pw.Document();
  final ahora = DateTime.now();
  doc.addPage(pw.Page(
    pageFormat: formatoTicket(),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      ..._encabezado(),
      _linea(),
      pw.Text(t(c.titulo.toUpperCase()), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      _fila('Impreso', formatoFechaHora(ahora)),
      if (c.turno != null) _fila('Abierto', formatoFechaHora(c.turno!.abierto)),
      _linea(),
      _fila('Ventas (${c.numeroVentas})', formatoPesos(c.ventasCentavos), negrita: true),
      _fila('Ganancia', formatoPesos(c.gananciaCentavos)),
      _linea(),
      pw.Text('DINERO EN CAJA', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      _fila('Fondo de caja', formatoPesos(c.fondoCentavos)),
      _fila('+ Ventas en efectivo', formatoPesos(c.efectivoCentavos)),
      _fila('+ Abonos en efectivo', formatoPesos(c.abonosEfectivoCentavos)),
      _fila('+ Entradas', formatoPesos(c.entradasCentavos)),
      _fila('- Salidas', formatoPesos(c.salidasCentavos)),
      _fila('- Devoluciones en efectivo', formatoPesos(c.devolucionesEfectivoCentavos)),
      _fila('= Efectivo esperado', formatoPesos(c.esperadoCentavos), negrita: true),
      if (contadoCentavos != null) ...[
        _fila('Contado', formatoPesos(contadoCentavos)),
        _fila(contadoCentavos >= c.esperadoCentavos ? 'Sobrante' : 'Faltante',
            formatoPesos((contadoCentavos - c.esperadoCentavos).abs()), negrita: true),
        if (fondoSiguienteCentavos != null) ...[
          _linea(),
          _fila('ENTREGA DE CAJA', ''),
          _fila('Se deja de fondo', formatoPesos(fondoSiguienteCentavos), negrita: true),
          _fila('Se retira', formatoPesos(contadoCentavos - fondoSiguienteCentavos), negrita: true),
          pw.SizedBox(height: 22),
          _fila('Entregó ____________', ''),
          pw.SizedBox(height: 16),
          _fila('Recibió ____________', ''),
        ],
      ],
      _linea(),
      pw.Text('VENTAS POR FORMA DE PAGO', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      _fila('Efectivo', formatoPesos(c.efectivoCentavos)),
      _fila('Tarjeta', formatoPesos(c.tarjetaCentavos)),
      _fila('Transferencia', formatoPesos(c.transferenciaCentavos)),
      _fila('Vales', formatoPesos(c.valesCentavos)),
      _fila('Dólares', formatoPesos(c.dolaresCentavos)),
      _fila('Crédito', formatoPesos(c.creditoCentavos)),
      _fila('Abonos con tarjeta/otros', formatoPesos(c.abonosOtrosCentavos)),
      _fila('Devoluciones', formatoPesos(c.devolucionesCentavos)),
      _linea(),
      pw.Text('POR DEPARTAMENTO', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      for (final d in c.porDepartamento) _fila(d.$1, formatoPesos(d.$2)),
      if (c.ivaCentavos > 0 || c.iepsCentavos > 0) ...[
        _linea(),
        _fila('IVA', formatoPesos(c.ivaCentavos)),
        _fila('IEPS', formatoPesos(c.iepsCentavos)),
      ],
    ]),
  ));
  return doc.save();
}

/// Comprobante de abono.
Future<Uint8List> ticketAbono(Cliente c, int montoCentavos, int saldoCentavos) async {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: formatoTicket(),
    build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      ..._encabezado(),
      _linea(),
      pw.Text('COMPROBANTE DE ABONO', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      _fila('Fecha', formatoFechaHora(DateTime.now())),
      _fila('Cliente', c.nombre),
      _linea(),
      _fila('Abono', formatoPesos(montoCentavos), negrita: true, tamano: 10),
      _fila('Saldo pendiente', formatoPesos(saldoCentavos)),
    ]),
  ));
  return doc.save();
}
