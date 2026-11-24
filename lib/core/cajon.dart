import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/ajustes_repo.dart';
import 'impresion_cruda.dart';
import 'impresora.dart';
import '../data/repos.dart';

/// Abre el cajón de dinero conectado a la impresora de tickets (cable RJ11).
/// Manda el comando ESC/POS "ESC p 0" a la impresora compartida de Windows
/// (\\localhost\NOMBRE), como lo hacen la mayoría de los puntos de venta.
/// Regresa null si salió bien o el mensaje de error.
Future<String?> abrirCajon({String? impresora}) async {
  if (!Platform.isWindows) return 'Solo funciona en Windows.';
  const orden = [27, 112, 0, 25, 250, 27, 112, 1, 25, 250];
  // 1) Directo a la impresora de tickets, sin compartir nada.
  String? error;
  try {
    final p = await impresoraTickets();
    if (p != null) {
      error = imprimirCrudo(p.name, orden, documento: 'Abrir cajón');
      if (error == null) return null;
    } else {
      error = 'Elige tu impresora de tickets en Configuración → Impresora de Tickets.';
    }
  } catch (e) {
    error = 'No se pudo abrir el cajón: $e';
  }
  // 2) Respaldo: impresora compartida (si se escribió un nombre).
  final nombre = (impresora ?? repos.ajustes.texto(Ajuste.cajonImpresora)).trim();
  if (nombre.isEmpty) return error;
  try {
    final archivo = File(p.join(Directory.systemTemp.path, 'exbel_cajon.bin'));
    await archivo.writeAsBytes(orden);
    final destino = nombre.startsWith(r'\\') ? nombre : '\\\\localhost\\$nombre';
    final r = await Process.run('cmd', ['/c', 'copy', '/b', archivo.path, destino], runInShell: false);
    if (r.exitCode != 0) {
      return 'Windows no pudo mandar la orden a "$destino". Revisa que la impresora esté compartida con ese nombre.';
    }
    return null;
  } catch (e) {
    return 'No se pudo abrir el cajón: $e';
  }
}

/// Al cobrar: abre el cajón si está activado y la venta movió efectivo.
Future<void> abrirCajonAlCobrar({required bool conEfectivo}) async {
  if (!repos.ajustes.si(Ajuste.cajonAbrir) || !conEfectivo) return;
  await abrirCajon();
}
