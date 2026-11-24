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

/// Descarga el instalador. [avance] de 0 a 1.
Future<File> descargarInstalador(VersionNueva v, void Function(double) avance) async {
  final destino = File(p.join(Directory.systemTemp.path, 'exBel-venta-${v.version}.exe'));
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final res = await (await cliente.getUrl(Uri.parse(v.url))).close();
    if (res.statusCode >= 300) throw HttpException('Código ${res.statusCode}');
    final total = res.contentLength;
    final sink = destino.openWrite();
    var recibidos = 0;
    await for (final parte in res) {
      sink.add(parte);
      recibidos += parte.length;
      if (total > 0) avance(recibidos / total);
    }
    await sink.close();
    if (await destino.length() < 1000000) throw const FileSystemException('La descarga quedó incompleta');
    return destino;
  } finally {
    cliente.close(force: true);
  }
}

/// Abre el instalador en modo silencioso; al terminar vuelve a abrir exBel.
Future<void> instalarYSalir(File instalador) async {
  await Process.start(instalador.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
  exit(0);
}
