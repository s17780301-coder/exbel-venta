import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/licencia.dart';
import '../tema/tema.dart';
import 'ex_widgets.dart';

const _contacto = 'Para comprar exBel venta comunícate con tu distribuidor exBel y dale tu código de equipo.';

/// Cuadro para escribir el código de activación. Regresa true si se activó.
Future<bool> mostrarActivacion(BuildContext context) async =>
    await showDialog<bool>(context: context, builder: (_) => const AlertDialog(title: Text('Activar exBel venta'), content: SizedBox(width: 480, child: PanelActivacion()))) ??
    false;

class PanelActivacion extends StatefulWidget {
  const PanelActivacion({super.key, this.alActivar});
  final VoidCallback? alActivar;

  @override
  State<PanelActivacion> createState() => _PanelActivacionState();
}

class _PanelActivacionState extends State<PanelActivacion> {
  final _codigo = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _activar() async {
    if (await Licencia.instancia.activar(_codigo.text)) {
      if (!mounted) return;
      if (widget.alActivar != null) {
        widget.alActivar!();
      } else {
        Navigator.of(context).pop(true);
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('¡Listo! exBel venta quedó activado. Gracias por tu compra.')));
    } else {
      setState(() => _error = 'El código no es válido para este equipo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final equipo = Licencia.instancia.equipo;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text(_contacto, style: TextStyle(fontSize: 15)),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: ExColor.banda,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: ExColor.borde, width: 1.4),
        ),
        child: Row(children: [
          const Text('Código de equipo:  ', style: TextStyle(fontSize: 16)),
          SelectableText(equipo, style: ExTexto.mono(24, color: ExColor.bandaTexto)),
          const Spacer(),
          IconButton(
            tooltip: 'Copiar',
            onPressed: () => Clipboard.setData(ClipboardData(text: equipo)),
            icon: const Icon(Icons.copy),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _codigo,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        style: ExTexto.mono(20),
        decoration: InputDecoration(labelText: 'Código de activación', hintText: 'XXXX-XXXX-XXXX', errorText: _error),
        onSubmitted: (_) => _activar(),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(onPressed: _activar, icon: const Icon(Icons.verified_outlined), label: const Text('Activar')),
    ]);
  }
}

/// Aviso delgado mientras se usa la versión de prueba.
class AvisoPrueba extends StatefulWidget {
  const AvisoPrueba({super.key});

  @override
  State<AvisoPrueba> createState() => _AvisoPruebaState();
}

class _AvisoPruebaState extends State<AvisoPrueba> {
  @override
  Widget build(BuildContext context) {
    final e = Licencia.instancia.estado;
    if (e == null || e.activada) return const SizedBox.shrink();
    final d = e.diasRestantes;
    return Container(
      width: double.infinity,
      color: const Color(0xFFF6E9D8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(children: [
        const Icon(Icons.hourglass_bottom, size: 18, color: Color(0xFF8A5A2B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Versión de prueba de exBel venta: ${d <= 1 ? 'último día' : 'quedan $d días'}. '
            'Al terminar, el sistema se desactiva hasta confirmar la compra.',
            style: const TextStyle(color: Color(0xFF6B4520), fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(
          onPressed: () async {
            if (await mostrarActivacion(context)) setState(() {});
          },
          child: const Text('Activar'),
        ),
      ]),
    );
  }
}

/// Pantalla cuando terminó la prueba.
class BloqueoPrueba extends StatelessWidget {
  const BloqueoPrueba({super.key, required this.alActivar});
  final VoidCallback alActivar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExColor.barra,
      body: Center(
        child: SizedBox(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Center(child: ExMarca(tamano: 48)),
            const SizedBox(height: 10),
            Text('SISTEMAS PROFESIONALES DE SIMPLIFICACIÓN MERCANTIL',
                textAlign: TextAlign.center, style: ExTexto.marca(13, color: ExColor.bandaTexto, peso: FontWeight.w400).copyWith(letterSpacing: 2.4)),
            const SizedBox(height: 30),
            Text('Terminó el periodo de prueba', textAlign: TextAlign.center, style: ExTexto.titulo(28)),
            const SizedBox(height: 8),
            const Text(
                'Los $diasDePrueba días de prueba de exBel venta terminaron. Tu información está guardada y '
                'vuelve a estar disponible en cuanto actives el sistema.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: ExColor.texto2)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ExColor.blanco,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ExColor.borde, width: 1.4),
              ),
              child: PanelActivacion(alActivar: alActivar),
            ),
          ]),
        ),
      ),
    );
  }
}
