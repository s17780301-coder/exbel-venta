import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/caja_local.dart';
import '../../core/red/db_remota.dart';
import '../../core/red/servidor.dart';
import '../../data/repos.dart';
import '../../main.dart' show iniciarServidorSiToca;
import '../tema/tema.dart';
import 'dialogos.dart';

/// Cierra exBel venta para que al abrirlo tome la nueva configuración.
Future<void> reiniciarPrograma(BuildContext context, String mensaje) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text('Listo'),
      content: Text('$mensaje\n\nexBel venta se cerrará. Vuelve a abrirlo.'),
      actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Cerrar exBel venta'))],
    ),
  );
  try {
    await windowManager.setFullScreen(false);
    await windowManager.close();
  } catch (_) {}
  exit(0);
}

/// Convierte esta computadora en caja adicional conectada a la principal.
Future<void> conectarACajaPrincipal(BuildContext context) async {
  final r = await showDialog<(String, String, String)>(context: context, builder: (_) => const _Conectar());
  if (r == null || !context.mounted) return;
  await cajaLocal.cambiar(modo: 'secundaria', servidor: r.$1, clave: r.$2, nombreCaja: r.$3);
  if (context.mounted) await reiniciarPrograma(context, 'Esta computadora quedó como "${r.$3}", conectada a la caja principal (${r.$1}).');
}

class _Conectar extends StatefulWidget {
  const _Conectar();

  @override
  State<_Conectar> createState() => _ConectarState();
}

class _ConectarState extends State<_Conectar> {
  late final _ip = TextEditingController(text: cajaLocal.servidor);
  late final _clave = TextEditingController(text: cajaLocal.esSecundaria ? cajaLocal.clave : '');
  late final _nombre = TextEditingController(text: cajaLocal.esSecundaria ? cajaLocal.nombreCaja : 'Caja 2');
  List<(String, String)> _encontradas = [];
  bool _buscando = false;
  String? _estado;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _ip.dispose();
    _clave.dispose();
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    setState(() => _buscando = true);
    final r = await buscarCajaPrincipal();
    if (!mounted) return;
    setState(() {
      _encontradas = r;
      _buscando = false;
      if (r.length == 1 && _ip.text.isEmpty) _ip.text = r.first.$1;
    });
  }

  Future<void> _probar() async {
    setState(() {
      _estado = 'Probando…';
      _ok = false;
    });
    try {
      final r = await DatabaseRemota(_ip.text.trim(), _clave.text.trim()).ping();
      if (mounted) {
        setState(() {
          _estado = 'Conectado con: ${r['tienda']}';
          _ok = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _estado = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Conectar a la caja principal'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Las dos computadoras deben estar en la misma red (mismo módem o WiFi) y exBel venta abierto en la '
                'caja principal con la multicaja activada.'),
            const SizedBox(height: 12),
            Row(children: [
              Text('Cajas encontradas en la red', style: ExTexto.titulo(15)),
              const Spacer(),
              TextButton.icon(
                  onPressed: _buscando ? null : _buscar, icon: const Icon(Icons.refresh, size: 18), label: const Text('Buscar')),
            ]),
            if (_buscando) const LinearProgressIndicator(),
            if (!_buscando && _encontradas.isEmpty)
              const Text('No se encontró automáticamente. Escribe la dirección que aparece en la caja principal.',
                  style: TextStyle(color: ExColor.texto2)),
            for (final c in _encontradas)
              ListTile(
                dense: true,
                leading: const Icon(Icons.point_of_sale),
                title: Text(c.$2),
                subtitle: Text(c.$1),
                selected: _ip.text == c.$1,
                onTap: () => setState(() => _ip.text = c.$1),
              ),
            const SizedBox(height: 10),
            TextField(controller: _ip, decoration: const InputDecoration(labelText: 'Dirección de la caja principal', hintText: '192.168.1.10')),
            const SizedBox(height: 10),
            TextField(controller: _clave, decoration: const InputDecoration(labelText: 'Clave de red (6 números)')),
            const SizedBox(height: 10),
            TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre de esta caja', hintText: 'Caja 2')),
            const SizedBox(height: 12),
            Row(children: [
              OutlinedButton(onPressed: _probar, child: const Text('Probar conexión')),
              const SizedBox(width: 12),
              if (_estado != null)
                Expanded(child: Text(_estado!, style: TextStyle(color: _ok ? ExColor.verde : ExColor.rojo, fontWeight: FontWeight.w600))),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: !_ok
              ? null
              : () => Navigator.pop(context, (_ip.text.trim(), _clave.text.trim(), _nombre.text.trim().isEmpty ? 'Caja 2' : _nombre.text.trim())),
          child: const Text('Conectar'),
        ),
      ],
    );
  }
}

/// Sección de Configuración → Multicaja.
class SeccionMulticaja extends StatefulWidget {
  const SeccionMulticaja({super.key});

  @override
  State<SeccionMulticaja> createState() => _SeccionMulticajaState();
}

class _SeccionMulticajaState extends State<SeccionMulticaja> {
  List<String> _ips = [];

  @override
  void initState() {
    super.initState();
    _cargarIps();
  }

  Future<void> _cargarIps() async {
    try {
      final l = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final ips = [for (final i in l) for (final a in i.addresses) if (!a.isLoopback) a.address];
      if (mounted) setState(() => _ips = ips);
    } catch (_) {}
  }

  Future<void> _activar(bool v) async {
    await cajaLocal.cambiar(red: v);
    if (v) {
      await iniciarServidorSiToca();
    } else {
      await servidorCaja?.detener();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final secundaria = cajaLocal.esSecundaria;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('Multicaja (red local)', style: ExTexto.titulo(24)),
      ),
      ExSeccionSimple(
        child: Row(children: [
          Icon(secundaria ? Icons.lan_outlined : Icons.dns_outlined, size: 40, color: ExColor.indigo),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(cajaLocal.nombreCaja, style: ExTexto.titulo(22)),
              Text(secundaria
                  ? 'Caja adicional conectada a la caja principal (${cajaLocal.servidor})'
                  : 'Caja principal: aquí se guarda toda la información de la tienda'),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      if (!secundaria) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: cajaLocal.redActiva,
          onChanged: _activar,
          title: const Text('Permitir que otras cajas se conecten a esta', style: TextStyle(fontSize: 17)),
          subtitle: Text(servidorCaja?.activo ?? false ? 'Activo: esperando conexiones' : 'Apagado'),
        ),
        if (cajaLocal.redActiva) ...[
          const SizedBox(height: 8),
          Text('Para conectar otra caja, en ella entra a Configuración → Multicaja → "Conectar a la caja principal" y usa:',
              style: ExTexto.texto(15)),
          const SizedBox(height: 8),
          ExSeccionSimple(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Dirección: ${_ips.isEmpty ? '(revisa que la computadora esté conectada a la red)' : _ips.join('  ó  ')}',
                  style: ExTexto.mono(18)),
              const SizedBox(height: 6),
              Text('Clave de red: ${cajaLocal.clave}', style: ExTexto.mono(22, color: ExColor.indigo)),
            ]),
          ),
          const SizedBox(height: 10),
          const Text('La primera vez, Windows preguntará si permites que exBel venta use la red: marca "Redes privadas" y dale Permitir.',
              style: TextStyle(color: ExColor.texto2)),
          const Text('Esta computadora debe estar prendida y con exBel venta abierto para que las otras cajas vendan.',
              style: TextStyle(color: ExColor.texto2)),
        ],
        const Divider(height: 32),
        Text('¿Esta computadora es una caja adicional?', style: ExTexto.titulo(16)),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => conectarACajaPrincipal(context),
            icon: const Icon(Icons.lan_outlined),
            label: const Text('Conectar a la caja principal'),
          ),
        ),
      ] else ...[
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(
            onPressed: () => conectarACajaPrincipal(context),
            icon: const Icon(Icons.settings_ethernet),
            label: const Text('Cambiar conexión'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              if (!await confirmar(context, 'Usar esta computadora sola',
                  'Dejará de usar la información de la caja principal y trabajará con su propia información.')) {
                return;
              }
              await cajaLocal.cambiar(modo: 'principal');
              if (context.mounted) await reiniciarPrograma(context, 'Esta computadora trabajará sola.');
            },
            icon: const Icon(Icons.link_off),
            label: const Text('Desconectar (trabajar sola)'),
          ),
        ]),
        const SizedBox(height: 12),
        const Text('Productos, clientes, ventas e inventario se comparten con la caja principal. La impresora, el cajón, '
            'la báscula, el tamaño de pantalla y los tickets en espera son de cada caja.', style: TextStyle(color: ExColor.texto2)),
      ],
    ]);
  }
}

/// Recuadro sencillo.
class ExSeccionSimple extends StatelessWidget {
  const ExSeccionSimple({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ExColor.blanco,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ExColor.borde, width: 1.4),
        ),
        child: child,
      );
}

/// ¿Esta caja está conectada a otra?
bool get esCajaConectada => repos.db is DatabaseRemota;
