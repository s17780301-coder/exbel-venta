import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/actualizador.dart';
import '../config/config_page.dart' show versionExBel;
import '../tema/tema.dart';
import 'dialogos.dart';
import 'ex_ui.dart';

/// true si en Ventas hay productos capturados (lo pone Ventas): mientras
/// haya una venta a medias no se instala nada.
bool Function() ventaEnCurso = () => false;

/// Actualización automática: revisa cada 15 minutos; si hay versión nueva la
/// descarga sola y la instala cuando la caja está libre (sin venta a medias y
/// sin que nadie toque el teclado ni el mouse por 1 minuto), con 15 segundos
/// de aviso para poder posponerla.
class AvisoActualizacion extends StatefulWidget {
  const AvisoActualizacion({super.key});

  @override
  State<AvisoActualizacion> createState() => _AvisoActualizacionState();
}

class _AvisoActualizacionState extends State<AvisoActualizacion> {
  VersionNueva? _nueva;
  File? _archivo;
  bool _bajando = false, _preguntando = false;
  Timer? _revisar, _vigilar;
  DateTime _ultimoUso = DateTime.now();
  DateTime? _pospuesta;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_uso);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_puntero);
    _buscar();
    _revisar = Timer.periodic(const Duration(minutes: 15), (_) => _buscar());
    _vigilar = Timer.periodic(const Duration(seconds: 5), (_) => _quizaInstalar());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_uso);
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_puntero);
    _revisar?.cancel();
    _vigilar?.cancel();
    super.dispose();
  }

  bool _uso(KeyEvent e) {
    _ultimoUso = DateTime.now();
    return false;
  }

  void _puntero(PointerEvent e) {
    if (e is PointerDownEvent || e is PointerScrollEvent) _ultimoUso = DateTime.now();
  }

  Future<void> _buscar() async {
    if (_bajando || _archivo != null) return;
    final v = await buscarActualizacion(versionExBel);
    if (!mounted || v == null) return;
    setState(() {
      _nueva = v;
      _bajando = true;
    });
    try {
      final f = await descargarInstalador(v, (_) {});
      if (mounted) setState(() => _archivo = f);
    } catch (_) {
      // Se vuelve a intentar en la siguiente revisión.
    } finally {
      if (mounted) setState(() => _bajando = false);
    }
  }

  Future<void> _quizaInstalar() async {
    final f = _archivo, v = _nueva;
    if (f == null || v == null || _preguntando || !mounted) return;
    final ahora = DateTime.now();
    if (ahora.difference(_ultimoUso) < const Duration(minutes: 1)) return;
    final p = _pospuesta;
    if (p != null && ahora.difference(p) < const Duration(minutes: 10)) return;
    if (ventaEnCurso() || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    _preguntando = true;
    final instalar = await _cuentaRegresiva(v.version);
    _preguntando = false;
    if (!mounted) return;
    if (!instalar) {
      _pospuesta = DateTime.now();
      return;
    }
    try {
      await instalarYSalir(f);
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo instalar la actualización: ${motivoDescarga(e)}');
      setState(() => _archivo = null);
    }
  }

  /// 15 segundos para posponer. true = instalar.
  Future<bool> _cuentaRegresiva(String version) async {
    final quedan = ValueNotifier<int>(15);
    final t = Timer.periodic(const Duration(seconds: 1), (t) {
      quedan.value--;
      if (quedan.value <= 0) {
        t.cancel();
        if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
      }
    });
    final r = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Actualizando exBel venta a la versión $version'),
        content: ValueListenableBuilder<int>(
          valueListenable: quedan,
          builder: (_, q, __) => Text('Se instala en $q segundos. exBel se cerrará y volverá a abrir solo.\n'
              'Tus ventas y productos se conservan.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(false), child: const Text('Ahora no')),
          FilledButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(true), child: const Text('Instalar ya')),
        ],
      ),
    );
    t.cancel();
    return r ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final v = _nueva;
    if (v == null) return const SizedBox.shrink();
    final lista = _archivo != null;
    return Container(
      width: double.infinity,
      color: Tono.verde.fondo,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Row(children: [
        Icon(Icons.system_update_alt_rounded, size: 18, color: Tono.verde.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              lista
                  ? 'Versión nueva ${v.version} lista. Se instala sola cuando la caja esté libre un minuto.'
                  : 'Descargando la versión nueva ${v.version}…',
              style: TextStyle(color: Tono.verde.color, fontWeight: FontWeight.w600)),
        ),
        if (lista)
          TextButton(
            onPressed: () async {
              if (ventaEnCurso()) return aviso(context, 'Termina o guarda la venta actual primero.');
              await instalarYSalir(_archivo!);
            },
            child: const Text('Instalar ahora'),
          ),
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
      aviso(context, 'No se pudo descargar la actualización: ${motivoDescarga(e)}');
    }
  }
}
