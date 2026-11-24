import 'package:printing/printing.dart';

import '../data/repos.dart';

const claveImpresoraTickets = 'impresora_tickets';

bool _esVirtual(String n) {
  final x = n.toLowerCase();
  return ['pdf', 'xps', 'onenote', 'fax', 'anydesk', 'send to'].any(x.contains);
}

bool _pareceTermica(String n) {
  final x = n.toLowerCase();
  return ['pos', '58', '80', 'ticket', 'thermal', 'termica', 'térmica', 'xp-', 'tm-', 'receipt', 'zjiang', 'gprinter']
      .any(x.contains);
}

/// La impresora de tickets: la elegida en Configuración o, si no hay,
/// la primera que parezca de tickets (y se guarda para la próxima).
Future<Printer?> impresoraTickets() async {
  final lista = await Printing.listPrinters();
  final elegida = repos.ajustes.texto(claveImpresoraTickets);
  if (elegida.isNotEmpty) {
    final p = lista.where((x) => x.name == elegida).firstOrNull;
    if (p != null) return p;
  }
  final reales = lista.where((p) => !_esVirtual(p.name)).toList();
  final p = reales.where((x) => _pareceTermica(x.name)).firstOrNull ??
      (reales.length == 1 ? reales.first : null);
  if (p != null) await repos.ajustes.guardar(claveImpresoraTickets, p.name);
  return p;
}
