import 'dart:convert';
import 'dart:io';

import 'package:ota_update/ota_update.dart';

const versionApp = '1.0.0';
const urlVersionApp = 'https://github.com/s17780301-coder/exbel-venta/releases/download/ultima/alerta-version.json';

int compararVersiones(String a, String b) {
  List<int> v(String s) => s.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  final x = v(a), y = v(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// (versión, url del apk) si hay una más nueva.
Future<(String, String)?> buscarVersionNueva() async {
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final res = await (await cliente.getUrl(Uri.parse(urlVersionApp))).close().timeout(const Duration(seconds: 12));
    if (res.statusCode >= 300) return null;
    final m = jsonDecode(await utf8.decodeStream(res)) as Map;
    final v = '${m['version']}';
    return compararVersiones(v, versionApp) > 0 ? (v, '${m['url']}') : null;
  } catch (_) {
    return null;
  } finally {
    cliente.close(force: true);
  }
}

/// Descarga el APK nuevo y abre el instalador de Android.
Stream<OtaEvent> instalarVersion(String url) => OtaUpdate().execute(url, destinationFilename: 'exbel-alerta.apk');
