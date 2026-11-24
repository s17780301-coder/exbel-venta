import 'package:flutter/material.dart';

import '../../core/actualizador.dart';
import '../config/config_page.dart' show versionExBel;
import '../tema/tema.dart';
import 'dialogos.dart';
import 'ex_ui.dart';

/// Franja que aparece cuando hay una versión nueva de exBel venta.
class AvisoActualizacion extends StatefulWidget {
  const AvisoActualizacion({super.key});

  @override
  State<AvisoActualizacion> createState() => _AvisoActualizacionState();
}

class _AvisoActualizacionState extends State<AvisoActualizacion> {
  VersionNueva? _nueva;

  @override
  void initState() {
    super.initState();
    buscarActualizacion(versionExBel).then((v) {
      if (mounted) setState(() => _nueva = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = _nueva;
    if (v == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Tono.verde.fondo,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(children: [
        Icon(Icons.system_update_alt_rounded, size: 18, color: Tono.verde.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Hay una versión nueva de exBel venta (${v.version}). Se instala en un minuto y tus datos se conservan.',
              style: TextStyle(color: Tono.verde.color, fontWeight: FontWeight.w600)),
        ),
        TextButton(onPressed: () => actualizarAhora(context, v), child: const Text('Actualizar ahora')),
      ]),
    );
  }
}

/// Descarga e instala la versión nueva (exBel se cierra y vuelve a abrir solo).
Future<void> actualizarAhora(BuildContext context, VersionNueva v) async {
  if (!await confirmar(context, 'Actualizar exBel venta',
      'Se descargará la versión ${v.version}. exBel venta se cerrará unos segundos y volverá a abrir solo.\n\n'
          'Los tickets en espera, ventas y productos se conservan.',
      si: 'Actualizar')) {
    return;
  }
  if (!context.mounted) return;
  final avance = ValueNotifier<double>(0);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      title: const Text('Descargando la actualización…'),
      content: SizedBox(
        width: 420,
        child: ValueListenableBuilder<double>(
          valueListenable: avance,
          builder: (_, a, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            LinearProgressIndicator(value: a == 0 ? null : a),
            const SizedBox(height: 8),
            Text('${(a * 100).round()} %', style: const TextStyle(color: ExColor.texto2)),
          ]),
        ),
      ),
    ),
  );
  try {
    final archivo = await descargarInstalador(v, (x) => avance.value = x);
    await instalarYSalir(archivo);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      aviso(context, 'No se pudo descargar la actualización. Revisa el internet e inténtalo de nuevo.');
    }
  }
}
