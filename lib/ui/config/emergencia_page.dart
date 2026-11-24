import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/caja_local.dart';
import '../../core/emergencia.dart';
import '../../core/licencia.dart';
import '../comun/dialogos.dart';
import '../comun/ex_ui.dart';
import '../sesion.dart';
import '../tema/tema.dart';

const urlAppAlerta = 'https://github.com/s17780301-coder/exbel-venta/releases/download/ultima/exBel-alerta.apk';

/// Configuración → Botón de emergencia (con la app exBel Alerta).
class SeccionEmergencia extends StatefulWidget {
  const SeccionEmergencia({super.key});

  @override
  State<SeccionEmergencia> createState() => _SeccionEmergenciaState();
}

class _SeccionEmergenciaState extends State<SeccionEmergencia> {
  String? _codigo;
  bool _cargando = false, _probando = false;

  Future<void> _vincular() async {
    setState(() => _cargando = true);
    final c = await codigoVinculo();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _codigo = c;
    });
    if (c == null) aviso(context, 'No hay internet. Conecta la computadora e inténtalo de nuevo.');
  }

  Future<void> _probar() async {
    setState(() => _probando = true);
    final ok = await enviarAlertaEmergencia(
        caja: cajaLocal.nombreCaja, cajero: sesion.cajero?.nombre ?? '', equipo: Licencia.instancia.equipo, prueba: true);
    if (!mounted) return;
    setState(() => _probando = false);
    aviso(context, ok ? 'Prueba enviada: debe sonar en los celulares vinculados en unos segundos.' : 'No hay internet; no se pudo enviar.');
  }

  Widget _paso(int n, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Tono.lavanda.fondo, shape: BoxShape.circle),
            child: Text('$n', style: TextStyle(fontWeight: FontWeight.w700, color: Tono.lavanda.color)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 15, height: 1.4))),
        ]),
      );

  Widget _tarjeta(Widget hijo) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: ExEstilo.sombra),
        child: hijo,
      );

  @override
  Widget build(BuildContext context) {
    final c = _codigo;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const TituloSeccion('Botón de emergencia', icono: Icons.sos_rounded, tono: Tono.coral, subtitulo: 'Alerta silenciosa a la app exBel Alerta'),
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
      const SizedBox(height: 12),
      const Text(
          'En cualquier pantalla de exBel venta esas tres teclas mandan la alerta sin que aparezca nada en la pantalla. '
          'En los celulares vinculados suena una sirena a todo volumen, aunque estén en silencio, hasta que alguien la atiende.',
          style: TextStyle(fontSize: 15)),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('1. Instala la app en el celular', style: ExTexto.titulo(17)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              QrImageView(data: urlAppAlerta, size: 140, backgroundColor: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Escanea el código con la cámara del celular Android y descarga exBel Alerta. '
                    'Si Android pregunta, permite instalar apps de esta fuente.\n\n'
                    'Al abrirla, acepta los permisos de notificaciones y alarmas, y que funcione sin restricción de batería.',
                    style: TextStyle(color: ExColor.texto2)),
              ),
            ]),
          ])),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('2. Vincula el celular con esta tienda', style: ExTexto.titulo(17)),
            const SizedBox(height: 10),
            if (c == null) ...[
              _paso(1, 'Presiona "Generar código".'),
              _paso(2, 'En la app, toca "Vincular caja" y escanea el código QR o escribe los 6 números.'),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: _cargando ? null : _vincular,
                icon: _cargando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.qr_code_2_rounded),
                label: const Text('Generar código'),
              ),
            ] else
              Row(children: [
                QrImageView(data: 'exbel-vinculo:$c', size: 140, backgroundColor: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${c.substring(0, 3)} ${c.substring(3)}', style: ExTexto.titulo(40, color: Tono.lavanda.color).copyWith(letterSpacing: 4)),
                    const Text('Vale 15 minutos y para un solo celular.', style: TextStyle(color: ExColor.texto2)),
                    TextButton(onPressed: _vincular, child: const Text('Otro código (otro celular)')),
                  ]),
                ),
              ]),
          ])),
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        OutlinedButton.icon(
          onPressed: _probando ? null : _probar,
          icon: _probando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.campaign_rounded),
          label: const Text('Enviar alerta de prueba'),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('La dirección y el teléfono que ven en la alerta son los de Ajustes → datos de la tienda (logotipo y ticket).',
              style: TextStyle(color: ExColor.texto2)),
        ),
      ]),
    ]);
  }
}
