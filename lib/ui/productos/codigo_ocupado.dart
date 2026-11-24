import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../data/repos.dart';

/// Anti duplicados: al salir del campo de código (Enter, Tab o clic en otro
/// campo) revisa si ese código ya es de otro producto y lo avisa al momento.
/// Regresa true si el código está libre.
Future<bool> avisarCodigoOcupado(BuildContext context, String codigo, {String? excepto}) async {
  if (codigo.trim().isEmpty) return true;
  final o = await repos.productos.conCodigo(codigo, excepto: excepto);
  if (o == null || !context.mounted) return true;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded, size: 40, color: Color(0xFFB0573F)),
      title: const Text('Este producto ya existe'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('El código ${codigo.trim()} ya es de:', style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 8),
        Text(o.descripcion, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Precio ${formatoPesos(o.precioCentavos)}'
            '${o.usaInventario ? ' · Hay ${formatoCantidad(o.existencia)}' : ''}'),
        const SizedBox(height: 12),
        const Text('Usa otro código, o búscalo en Productos para modificarlo.'),
      ]),
      actions: [FilledButton(autofocus: true, onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
    ),
  );
  return false;
}
