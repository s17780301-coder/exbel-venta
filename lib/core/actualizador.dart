import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'nube.dart';

const urlVersion = 'https://github.com/s17780301-coder/exbel-venta/releases/download/ultima/version.json';

class VersionNueva {
  VersionNueva(this.version, this.url);
  final String version;
  final String url;
}

/// 0.9.10 > 0.9.9
int compararVersiones(String a, String b) {
  List<int> v(String s) => s.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  final x = v(a), y = v(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Último motivo por el que no se pudo revisar (para mostrarlo).
String? errorActualizacion;

/// ¿Hay una versión más nueva que [actual]? null si no o si no hay internet.
/// Pregunta a GitHub y, si no responde, a la nube de exBel (Supabase).
Future<VersionNueva?> buscarActualizacion(String actual) async {
  errorActualizacion = null;
  Map? m;
  final t = await descargarTexto(urlVersion, limite: const Duration(seconds: 15));
  if (t != null) {
    try {
      m = jsonDecode(t) as Map;
    } catch (_) {}
  }
  if (m == null) {
    final r = await nubeRpc('exbel_version', {});
    if (r is Map) m = r;
  }
  if (m == null) {
    errorActualizacion = 'No se pudo consultar si hay versión nueva. Revisa el internet.';
    return null;
  }
  final v = '${m['version']}';
  if (compararVersiones(v, actual) <= 0) return null;
  return VersionNueva(v, '${m['url']}');
}

/// Descarga el instalador. [avance] de 0 a 1. Reintenta 3 veces y, si falla,
/// el error dice el motivo real (internet, antivirus, disco…).
Future<File> descargarInstalador(VersionNueva v, void Function(double) avance) async {
  // Varias fuentes: la del aviso, el espejo de la nube de exBel (por si la
  // red no llega a GitHub) y GitHub directo.
  final fuentes = <String>{
    v.url,
    '$nubeUrl/functions/v1/exbel-descarga?v=${v.version}',
    'https://github.com/s17780301-coder/exbel-venta/releases/download/ultima/exBel-venta-${v.version}-instalador.exe',
  };
  final errores = <String>[];
  for (final url in fuentes) {
    for (var intento = 1; intento <= 2; intento++) {
      try {
        return await _descargar(v, url, avance);
      } catch (e) {
        errores.add(motivoDescarga(e));
        avance(0);
        await Future<void>.delayed(Duration(seconds: 2 * intento));
      }
    }
  }
  throw Exception(errores.toSet().join(' / '));
}

Future<File> _descargar(VersionNueva v, String url, void Function(double) avance) async {
  final carpeta = Directory(p.join(Directory.systemTemp.path, 'exbel-actualizacion'));
  await carpeta.create(recursive: true);
  final destino = File(p.join(carpeta.path, 'exBel-venta-${v.version}.exe'));
  final parcial = File('${destino.path}.descarga');
  final cliente = HttpClient()
    ..connectionTimeout = const Duration(seconds: 30)
    ..idleTimeout = const Duration(seconds: 30)
    ..userAgent = 'exBel-venta';
  try {
    final req = await cliente.getUrl(Uri.parse(url));
    req.followRedirects = true;
    req.maxRedirects = 10;
    final res = await req.close().timeout(const Duration(seconds: 60));
    if (res.statusCode >= 300) throw Exception('el servidor respondió ${res.statusCode}');
    final total = res.contentLength;
    final sink = parcial.openWrite();
    var recibidos = 0;
    try {
      await for (final parte in res.timeout(const Duration(seconds: 60))) {
        sink.add(parte);
        recibidos += parte.length;
        if (total > 0) avance(recibidos / total);
      }
    } finally {
      await sink.close();
    }
    final n = await parcial.length();
    if (n < 1000000 || (total > 0 && n != total)) throw Exception('la descarga quedó incompleta ($n de $total bytes)');
    if (await destino.exists()) await destino.delete();
    await parcial.rename(destino.path);
    if (!await destino.exists()) throw Exception('el antivirus borró el instalador');
    return destino;
  } finally {
    cliente.close(force: true);
  }
}

/// Motivo legible de un error de descarga.
String motivoDescarga(Object e) {
  if (e is SocketException || e is HandshakeException || e is TimeoutException) {
    return 'sin conexión con el servidor de descargas ($e)';
  }
  if (e is FileSystemException) return 'Windows no dejó guardar el archivo (${e.message} ${e.osError?.message ?? ''})';
  return '$e'.replaceFirst('Exception: ', '');
}

/// Abre el instalador en modo silencioso; al terminar vuelve a abrir exBel.
Future<void> instalarYSalir(File instalador) async {
  await Process.start(instalador.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
  exit(0);
}
