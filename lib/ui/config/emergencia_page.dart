import 'package:flutter/material.dart';

import '../../core/caja_local.dart';
import '../../core/emergencia.dart';
import '../../core/licencia.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_ui.dart';
import '../sesion.dart';
import '../tema/tema.dart';

/// Configuración → Botón de emergencia.
class SeccionEmergencia extends StatefulWidget {
  const SeccionEmergencia({super.key});

  @override
  State<SeccionEmergencia> createState() => _SeccionEmergenciaState();
}

class _Fila {
  _Fila(ContactoEmergencia c)
      : nombre = TextEditingController(text: c.nombre),
        telefono = TextEditingController(text: c.telefono),
        clave = TextEditingController(text: c.clave);
  final TextEditingController nombre, telefono, clave;
  ContactoEmergencia get contacto => ContactoEmergencia(nombre: nombre.text.trim(), telefono: telefono.text.trim(), clave: clave.text.trim());
}

class _SeccionEmergenciaState extends State<SeccionEmergencia> {
  late final List<_Fila> _filas = [for (final c in contactosEmergencia()) _Fila(c)];
  late final _mensaje = TextEditingController(
      text: repos.ajustes.texto(claveMensajeEmergencia).trim().isEmpty ? mensajeEmergenciaOmision : repos.ajustes.texto(claveMensajeEmergencia));
  bool _probando = false;

  Future<void> _guardar({bool avisar = true}) async {
    await guardarContactosEmergencia([for (final f in _filas) if (f.telefono.text.trim().isNotEmpty) f.contacto]);
    await repos.ajustes.guardar(claveMensajeEmergencia, _mensaje.text.trim());
    if (avisar && mounted) aviso(context, 'Contactos de emergencia guardados.');
  }

  Future<void> _probar() async {
    await _guardar(avisar: false);
    setState(() => _probando = true);
    final (ok, mal) = await enviarAlertaEmergencia(
      tienda: repos.ajustes.texto(Ajuste.nombreNegocio),
      caja: cajaLocal.nombreCaja,
      cajero: sesion.cajero?.nombre ?? '',
      equipo: Licencia.instancia.equipo,
      prueba: true,
    );
    if (!mounted) return;
    setState(() => _probando = false);
    aviso(context, mal == 0 && ok > 0
        ? 'Prueba enviada a $ok contacto${ok == 1 ? '' : 's'}. Revisen su WhatsApp.'
        : 'Se envió a $ok y fallaron $mal. Revisa el teléfono (con lada) y la APIKEY de cada contacto, y que haya internet.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const TituloSeccion('Botón de emergencia', icono: Icons.sos_rounded, tono: Tono.coral, subtitulo: 'Alerta silenciosa por WhatsApp'),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: Tono.coral.fondo, borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Text('Presiona  ', style: TextStyle(fontWeight: FontWeight.w600)),
            Tecla('Ctrl'),
            Text(' + '),
            Tecla('Alt'),
            Text(' + '),
            Tecla('E'),
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      const Text(
          'En cualquier pantalla de exBel venta, esas tres teclas juntas mandan un WhatsApp a todos los contactos de abajo, '
          'sin que aparezca nada en la pantalla. Necesita internet.',
          style: TextStyle(fontSize: 15)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Tono.azul.fondo, borderRadius: BorderRadius.circular(12)),
        child: Text(
            'Cada contacto lo activa UNA vez desde su celular:\n'
            '1. Guarda en sus contactos el número +34 644 45 70 57.\n'
            '2. Le manda por WhatsApp este texto exacto:  I allow callmebot to send me messages\n'
            '3. Le contestan con su APIKEY (un número). Escríbela aquí junto a su teléfono.',
            style: TextStyle(color: Tono.azul.color, height: 1.5)),
      ),
      const SizedBox(height: 16),
      for (var i = 0; i < _filas.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            AvatarColor(_filas[i].nombre.text.isEmpty ? '?' : _filas[i].nombre.text, tamano: 38),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: TextField(controller: _filas[i].nombre, decoration: const InputDecoration(labelText: 'Nombre'))),
            const SizedBox(width: 10),
            Expanded(flex: 3, child: TextField(controller: _filas[i].telefono, decoration: const InputDecoration(labelText: 'WhatsApp (ej. 55 1234 5678)'))),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: TextField(controller: _filas[i].clave, decoration: const InputDecoration(labelText: 'APIKEY'))),
            IconButton(
              tooltip: 'Quitar',
              onPressed: () => setState(() => _filas.removeAt(i)),
              icon: Icon(Icons.delete_outline_rounded, color: Tono.coral.color),
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() => _filas.add(_Fila(ContactoEmergencia(nombre: '', telefono: '', clave: '')))),
          icon: const Icon(Icons.person_add_alt_rounded),
          label: const Text('Agregar contacto'),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _mensaje,
        maxLines: 3,
        decoration: const InputDecoration(
            labelText: 'Mensaje', helperText: 'Se reemplazan solos: {tienda}, {caja}, {cajero} y {hora}'),
      ),
      const SizedBox(height: 16),
      Row(children: [
        FilledButton.icon(onPressed: _guardar, icon: const Icon(Icons.save_rounded), label: const Text('Guardar')),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _probando ? null : _probar,
          icon: _probando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
          label: const Text('Enviar prueba'),
        ),
      ]),
      const SizedBox(height: 10),
      const Text('El servicio gratuito de CallMeBot es para uso personal; para muchas tiendas conviene después un proveedor de pago.',
          style: TextStyle(color: ExColor.texto2, fontSize: 12.5)),
    ]);
  }
}
