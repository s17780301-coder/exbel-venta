import 'dart:convert';
import 'dart:io';

/// Nube de exBel (Supabase). La clave es la pública de la app: solo puede
/// llamar a las funciones de exBel, no leer ni cambiar datos directamente.
const nubeUrl = 'https://tdsyzimeafaxxocjpndd.supabase.co';
const nubeClave = 'sb_publishable_5bdU0Qwfdi5upipMkrBP0Q_DodPq9KQ';

/// Llama a una función de la nube. Regresa null si no hay internet.
Future<Object?> nubeRpc(String funcion, Map<String, Object?> args, {Duration limite = const Duration(seconds: 6)}) async {
  final cliente = HttpClient()..connectionTimeout = limite;
  try {
    final req = await cliente.postUrl(Uri.parse('$nubeUrl/rest/v1/rpc/$funcion')).timeout(limite);
    req.headers
      ..set('apikey', nubeClave)
      ..contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(args)));
    final res = await req.close().timeout(limite);
    final cuerpo = await utf8.decodeStream(res).timeout(limite);
    if (res.statusCode >= 300) return null;
    return cuerpo.isEmpty ? true : jsonDecode(cuerpo);
  } catch (_) {
    return null;
  } finally {
    cliente.close(force: true);
  }
}

/// GET sencillo (sigue redirecciones). null si falla.
Future<String?> descargarTexto(String url, {Duration limite = const Duration(seconds: 8)}) async {
  final cliente = HttpClient()..connectionTimeout = limite;
  try {
    final req = await cliente.getUrl(Uri.parse(url)).timeout(limite);
    final res = await req.close().timeout(limite);
    if (res.statusCode >= 300) return null;
    return await utf8.decodeStream(res).timeout(limite);
  } catch (_) {
    return null;
  } finally {
    cliente.close(force: true);
  }
}
