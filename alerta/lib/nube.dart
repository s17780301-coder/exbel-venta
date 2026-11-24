import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

const nubeUrl = 'https://tdsyzimeafaxxocjpndd.supabase.co';
const nubeClave = 'sb_publishable_5bdU0Qwfdi5upipMkrBP0Q_DodPq9KQ';

class ErrorNube implements Exception {
  ErrorNube(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}

/// Llama a una función de la nube de exBel. Lanza ErrorNube con el mensaje
/// del servidor; null si no hay internet.
Future<Object?> rpc(String funcion, Map<String, Object?> args) async {
  final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await cliente.postUrl(Uri.parse('$nubeUrl/rest/v1/rpc/$funcion'));
    req.headers
      ..set('apikey', nubeClave)
      ..contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode(args)));
    final res = await req.close().timeout(const Duration(seconds: 12));
    final cuerpo = await utf8.decodeStream(res);
    if (res.statusCode >= 300) {
      String m = 'Error del servidor';
      try {
        m = '${(jsonDecode(cuerpo) as Map)['message'] ?? m}';
      } catch (_) {}
      throw ErrorNube(m);
    }
    return cuerpo.isEmpty ? true : jsonDecode(cuerpo);
  } on ErrorNube {
    rethrow;
  } catch (_) {
    return null;
  } finally {
    cliente.close(force: true);
  }
}

/// Tienda vinculada a este celular.
class Vinculo {
  Vinculo(this.token, this.tienda);
  final String token;
  final String tienda;
  Map<String, String> aMapa() => {'token': token, 'tienda': tienda};
}

Future<List<Vinculo>> vinculos() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  final t = p.getString('vinculos');
  if (t == null) return [];
  return [for (final m in jsonDecode(t) as List) Vinculo('${m['token']}', '${m['tienda']}')];
}

Future<void> guardarVinculos(List<Vinculo> l) async {
  final p = await SharedPreferences.getInstance();
  await p.setString('vinculos', jsonEncode([for (final v in l) v.aMapa()]));
}

Future<String> miNombre() async {
  final p = await SharedPreferences.getInstance();
  return p.getString('nombre') ?? '';
}

Future<void> vincular(String codigo, String nombre, String rol) async {
  final r = await rpc('exbel_vincular', {'p_codigo': codigo, 'p_nombre': nombre, 'p_rol': rol});
  if (r == null) throw ErrorNube('No hay internet');
  final m = r as Map;
  final l = await vinculos();
  l.add(Vinculo('${m['token']}', '${m['tienda']}'));
  await guardarVinculos(l);
  final p = await SharedPreferences.getInstance();
  await p.setString('nombre', nombre);
}
