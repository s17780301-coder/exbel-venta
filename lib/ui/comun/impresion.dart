import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/escpos.dart';
import '../../core/impresion_cruda.dart';
import '../../core/impresora.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../zoom.dart';
import '../tema/tema.dart';
import 'dialogos.dart';

const _claveImpresora = claveImpresoraTickets;

/// Imprime en la impresora de tickets elegida en Configuración, sin
/// preguntar. Si no hay una elegida, abre el diálogo de Windows.
Future<void> imprimir(BuildContext context, Uint8List pdf, {String nombre = 'ticket'}) async {
  try {
    final p = await impresoraTickets();
    if (p != null) {
      // Directo en ESC/POS: a todo el ancho del papel y sin que Windows lo encoja.
      if (Platform.isWindows) {
        try {
          final datos = await escposDesdePdf(pdf, anchoMm: repos.ajustes.entero(Ajuste.ticketAncho));
          if (imprimirCrudo(p.name, datos, documento: nombre) == null) return;
        } catch (_) {}
      }
      await Printing.directPrintPdf(printer: p, onLayout: (_) async => pdf, name: nombre);
      return;
    }
    await Printing.layoutPdf(onLayout: (_) async => pdf, name: nombre);
  } catch (e) {
    if (context.mounted) aviso(context, 'No se pudo imprimir: $e');
  }
}

/// Elige la impresora de tickets.
Future<void> elegirImpresora(BuildContext context) async {
  List<Printer> lista;
  try {
    lista = await Printing.listPrinters();
  } catch (e) {
    if (context.mounted) aviso(context, 'No se pudieron leer las impresoras: $e');
    return;
  }
  if (!context.mounted) return;
  final actual = repos.ajustes.texto(_claveImpresora);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('Impresora de tickets'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, ''),
          child: Text('Automática (la de tickets)${actual.isEmpty ? '  ✓' : ''}'),
        ),
        for (final p in lista)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, p.name),
            child: Text('${p.name}${p.name == actual ? '  ✓' : ''}${p.isDefault ? '  (predeterminada)' : ''}'),
          ),
      ],
    ),
  );
  if (r == null) return;
  await repos.ajustes.guardar(_claveImpresora, r);
  avisarCambio();
}

String impresoraElegida() {
  final n = repos.ajustes.texto(_claveImpresora);
  return n.isEmpty ? 'Automática' : n;
}

/// Vista previa del ticket con botón de imprimir.
Future<void> vistaPrevia(BuildContext context, Uint8List pdf, {String titulo = 'Ticket'}) {
  return showDialog<void>(
    context: context,
    builder: (c) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 460,
        height: altoDialogo(context, 760),
        child: Column(children: [
          Container(
            color: ExColor.banda,
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
            child: Row(children: [
              Expanded(child: Text(titulo, style: ExTexto.titulo(18, color: ExColor.bandaTexto))),
              IconButton(
                onPressed: () => Navigator.pop(c),
                icon: const Icon(Icons.close, color: ExColor.bandaTexto),
              ),
            ]),
          ),
          Expanded(
            child: Container(
              color: ExColor.concreto,
              child: PdfPreview(
                build: (_) async => pdf,
                useActions: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                padding: const EdgeInsets.all(16),
                previewPageMargin: const EdgeInsets.all(8),
                scrollViewDecoration: const BoxDecoration(color: ExColor.concreto),
                pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white, boxShadow: [
                  BoxShadow(color: Color(0x22000000), blurRadius: 8),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  autofocus: true,
                  onPressed: () async {
                    await imprimir(context, pdf, nombre: titulo);
                    if (c.mounted) Navigator.pop(c);
                  },
                  child: const Text('Imprimir'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ),
  );
}
