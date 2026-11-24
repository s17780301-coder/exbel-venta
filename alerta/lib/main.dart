import 'dart:async';
import 'dart:convert';

import 'package:alarm/alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:ota_update/ota_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'actualizar.dart';
import 'nube.dart';
import 'nube.dart' as nube;
import 'push.dart';
import 'servicio.dart';

// Colores de exBel.
const cFondo = Color(0xFFF4F3F8);
const cTinta = Color(0xFF2B2845);
const cTexto2 = Color(0xFF6B6785);
const cIndigo = Color(0xFF4A4789);
const cLavanda = Color(0xFFE4E1F7);
const cVerde = Color(0xFF3D7A55);
const cVerdeFondo = Color(0xFFDDEEE4);
const cRojo = Color(0xFF9E3A2B);
const cCoralFondo = Color(0xFFFBE3DC);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  configurarServicio();
  await Alarm.init();
  await iniciarPush();
  runApp(const AppAlerta());
}

class AppAlerta extends StatelessWidget {
  const AppAlerta({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'exBel Alerta',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cFondo,
        colorScheme: ColorScheme.fromSeed(seedColor: cIndigo, primary: cIndigo, surface: Colors.white),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: cIndigo,
            minimumSize: const Size(0, 54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: const WithForegroundTask(child: Inicio()),
    );
  }
}

BoxDecoration tarjeta([Color c = Colors.white]) => BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [BoxShadow(color: Color(0x142B2845), blurRadius: 3, offset: Offset(0, 1))],
    );

Text etiqueta(String t) =>
    Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1, color: cTexto2));

// ---------------- Inicio ----------------

class Inicio extends StatefulWidget {
  const Inicio({super.key});

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> with WidgetsBindingObserver {
  List<Vinculo> _vinculos = [];
  final Map<String, Map> _estado = {};
  Timer? _reloj;
  bool _mostrandoAlerta = false;
  (String, String)? _nueva;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _arrancar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _refrescar();
  }

  Future<void> _arrancar() async {
    await _permisos();
    await _refrescar();
    if (_vinculos.isNotEmpty) await arrancarServicio();
    _reloj = Timer.periodic(const Duration(seconds: 3), (_) => _refrescar());
    final n = await buscarVersionNueva();
    if (mounted) setState(() => _nueva = n);
  }

  Future<void> _permisos() async {
    try {
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      if (!await FlutterForegroundTask.canScheduleExactAlarms) {
        await FlutterForegroundTask.openAlarmsAndRemindersSettings();
      }
    } catch (_) {}
  }

  Future<void> _refrescar() async {
    final l = await vinculos();
    final p = await SharedPreferences.getInstance();
    await p.reload();
    for (final v in l) {
      final t = p.getString('estado_${v.token}');
      if (t != null) _estado[v.token] = jsonDecode(t) as Map;
    }
    if (!mounted) return;
    setState(() => _vinculos = l);
    final a = await alertaActiva();
    if (a != null && !_mostrandoAlerta && mounted) {
      _mostrandoAlerta = true;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaAlerta(a)));
      _mostrandoAlerta = false;
      _refrescar();
    }
  }

  Future<void> _actualizar() async {
    final n = _nueva;
    if (n == null) return;
    final progreso = ValueNotifier<String>('Descargando…');
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text('Actualizando a ${n.$1}'),
        content: ValueListenableBuilder<String>(valueListenable: progreso, builder: (_, t, __) => Text(t)),
      ),
    );
    instalarVersion(n.$2).listen((e) {
      if (e.status == OtaStatus.DOWNLOADING) progreso.value = 'Descargando… ${e.value ?? ''} %';
      if (e.status == OtaStatus.INSTALLING) {
        progreso.value = 'Toca "Instalar" en la ventana de Android.';
        if (mounted) Navigator.of(context).pop();
      }
      if (e.status.name.contains('ERROR')) {
        if (mounted) Navigator.of(context).pop();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo descargar la actualización.')));
      }
    });
  }

  String _hace(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return 'Sin datos';
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 8) return 'En línea';
    if (m < 60) return 'Hace $m min';
    if (m < 60 * 24) return 'Hace ${m ~/ 60} h';
    return 'Hace ${m ~/ (60 * 24)} d';
  }

  @override
  Widget build(BuildContext context) {
    final cajas = <(String, Map)>[
      for (final v in _vinculos)
        for (final c in ((_estado[v.token]?['cajas'] as List?) ?? []).cast<Map>()) (v.tienda, c),
    ];
    final hayVinculos = _vinculos.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 16, 20, 20), children: [
          Row(children: [
            const Text.rich(TextSpan(children: [
              TextSpan(text: 'exBel', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cTinta)),
              TextSpan(text: '™ ', style: TextStyle(fontSize: 10, color: cTinta)),
              TextSpan(text: 'Alerta', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: cTexto2)),
            ])),
            const Spacer(),
            IconButton.filledTonal(
              tooltip: 'Historial y ajustes',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => Historial(_vinculos, _estado))),
              icon: const Icon(Icons.settings_rounded, color: cIndigo),
            ),
          ]),
          if (_nueva != null) ...[
            const SizedBox(height: 10),
            Container(
              decoration: tarjeta(cLavanda),
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(children: [
                Expanded(child: Text('Hay una versión nueva (${_nueva!.$1})', style: const TextStyle(fontWeight: FontWeight.w600))),
                TextButton(onPressed: _actualizar, child: const Text('Actualizar')),
              ]),
            ),
          ],
          const SizedBox(height: 16),
          Container(
            decoration: tarjeta(hayVinculos ? cVerdeFondo : cLavanda),
            padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
            child: Column(children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(hayVinculos ? Icons.verified_user_rounded : Icons.link_rounded, size: 44, color: hayVinculos ? cVerde : cIndigo),
              ),
              const SizedBox(height: 12),
              Text(hayVinculos ? 'Todo en orden' : 'Vincula tu primera caja',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: hayVinculos ? const Color(0xFF2F5E42) : cIndigo)),
              const SizedBox(height: 4),
              Text(hayVinculos ? 'Vigilando ${cajas.isEmpty ? _vinculos.length : cajas.length} caja${cajas.length == 1 ? '' : 's'}' : 'Así te avisamos si hay una emergencia',
                  style: TextStyle(color: hayVinculos ? cVerde : cTexto2)),
            ]),
          ),
          const SizedBox(height: 18),
          if (cajas.isNotEmpty) ...[
            etiqueta('CAJAS VINCULADAS'),
            const SizedBox(height: 8),
            for (final (tienda, c) in cajas)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: tarjeta(),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: cLavanda, borderRadius: BorderRadius.circular(13)),
                    child: Text(tienda.isEmpty ? '?' : tienda.trim().split(' ').take(2).map((x) => x.isEmpty ? '' : x[0]).join().toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.w800, color: cIndigo)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tienda, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      Text('${c['caja'] ?? ''} · ${(c['cajero'] ?? '').toString().isEmpty ? 'Sin turno' : c['cajero']}',
                          style: const TextStyle(color: cTexto2, fontSize: 12.5)),
                    ]),
                  ),
                  Text(_hace(c['ultimo'] as String?),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _hace(c['ultimo'] as String?) == 'En línea' ? cVerde : const Color(0xFF9A6B15))),
                ]),
              ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: tarjeta(),
            child: const Row(children: [
              Icon(Icons.notifications_active_rounded, color: Color(0xFFB0573F)),
              SizedBox(width: 12),
              Expanded(
                  child: Text('En la caja se activa poniendo la mano sobre el teclado (varias teclas a la vez). La alerta suena a todo volumen aunque el celular esté en silencio.',
                      style: TextStyle(color: cTexto2))),
            ]),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Vincular()));
                  await _refrescar();
                  if (_vinculos.isNotEmpty) await arrancarServicio();
                },
                child: const Text('Vincular caja', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => sonarSirena(AlertaActiva(
                    id: 0, token: '', tienda: 'Prueba en este celular', caja: 'Caja', cajero: '', creado: DateTime.now(), prueba: true)),
                child: const Text('Probar alarma'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ---------------- Alerta ----------------

class PantallaAlerta extends StatelessWidget {
  const PantallaAlerta(this.a, {super.key});
  final AlertaActiva a;

  Future<void> _atender(BuildContext context) async {
    await limpiarAlerta();
    if (a.token.isNotEmpty) {
      try {
        await rpc('exbel_atender', {'p_token': a.token, 'p_alerta': a.id, 'p_nombre': await miNombre()});
      } catch (_) {}
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hora = '${a.creado.hour.toString().padLeft(2, '0')}:${a.creado.minute.toString().padLeft(2, '0')}';
    Widget dato(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text(k, style: const TextStyle(color: Color(0xFFF6D3C9), fontSize: 15)),
            const SizedBox(width: 12),
            Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
          ]),
        );
    Widget boton(String t, VoidCallback f, {bool blanco = false}) => SizedBox(
          height: blanco ? 64 : 54,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: blanco ? Colors.white : Colors.white.withValues(alpha: 0.16),
              foregroundColor: blanco ? cRojo : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: f,
            child: Text(t, style: TextStyle(fontSize: blanco ? 19 : 15, fontWeight: FontWeight.w800)),
          ),
        );
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: cRojo,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(a.prueba ? 'PRUEBA DE ALERTA' : 'ALERTA DE EMERGENCIA',
                  style: const TextStyle(color: Color(0xFFF6D3C9), fontWeight: FontWeight.w700, letterSpacing: 1.5)),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  width: 132,
                  height: 132,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.12),
                    boxShadow: [BoxShadow(color: Colors.white.withValues(alpha: 0.07), spreadRadius: 16)],
                  ),
                  child: const Icon(Icons.warning_amber_rounded, size: 70, color: Colors.white),
                ),
              ),
              const SizedBox(height: 18),
              Text('${a.tienda}\npide ayuda',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1.1)),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(18)),
                child: Column(children: [
                  dato('Caja', a.caja),
                  dato('Cajero', a.cajero.isEmpty ? 'Sin turno' : a.cajero),
                  dato('Hora', hora),
                  if (a.direccion.isNotEmpty) dato('Dirección', a.direccion),
                ]),
              ),
              const Spacer(),
              boton('Llamar al 911', () => launchUrl(Uri.parse('tel:911')), blanco: true),
              const SizedBox(height: 10),
              Row(children: [
                if (a.telefono.isNotEmpty) ...[
                  Expanded(child: boton('Llamar a la tienda', () => launchUrl(Uri.parse('tel:${a.telefono}')))),
                  const SizedBox(width: 10),
                ],
                if (a.direccion.isNotEmpty)
                  Expanded(
                      child: boton('Cómo llegar',
                          () => launchUrl(Uri.parse('geo:0,0?q=${Uri.encodeComponent(a.direccion)}'), mode: LaunchMode.externalApplication))),
              ]),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 52),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.45), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () => _atender(context),
                child: const Text('Ya está atendida · silenciar', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------- Vincular ----------------

class Vincular extends StatefulWidget {
  const Vincular({super.key});

  @override
  State<Vincular> createState() => _VincularState();
}

class _VincularState extends State<Vincular> {
  final _codigo = TextEditingController();
  final _nombre = TextEditingController();
  String _rol = 'Dueño';
  bool _trabajando = false;
  bool _camara = true;

  @override
  void initState() {
    super.initState();
    miNombre().then((n) => _nombre.text = n);
  }

  Future<void> _vincular() async {
    final c = _codigo.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (c.length != 6) return _aviso('Escribe los 6 números del código.');
    if (_nombre.text.trim().isEmpty) return _aviso('Escribe tu nombre.');
    setState(() => _trabajando = true);
    try {
      await vincular(c, _nombre.text.trim(), _rol);
      await registrarPush();
      await arrancarServicio();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _aviso('$e');
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  void _aviso(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: cFondo, title: const Text('Vincular una caja', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: tarjeta(),
          child: const Text('En la computadora de la tienda abre exBel venta → Ajustes → Botón de emergencia → "Generar código". '
              'Escanea el QR o escribe los 6 números.', style: TextStyle(height: 1.45)),
        ),
        const SizedBox(height: 14),
        if (_camara)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 240,
              child: MobileScanner(
                onDetect: (captura) {
                  for (final b in captura.barcodes) {
                    final v = b.rawValue ?? '';
                    final m = RegExp(r'exbel-vinculo:(\d{6})').firstMatch(v);
                    if (m != null) {
                      setState(() {
                        _codigo.text = m.group(1)!;
                        _camara = false;
                      });
                      return;
                    }
                  }
                },
              ),
            ),
          ),
        const SizedBox(height: 14),
        etiqueta('CÓDIGO DE 6 NÚMEROS'),
        const SizedBox(height: 6),
        TextField(
          controller: _codigo,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 10),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 14),
        etiqueta('TU NOMBRE'),
        const SizedBox(height: 6),
        TextField(
          controller: _nombre,
          decoration: InputDecoration(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
        const SizedBox(height: 14),
        etiqueta('¿QUIÉN ERES PARA LA TIENDA?'),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final r in ['Dueño', 'Familiar', 'Encargado'])
            ChoiceChip(label: Text(r), selected: _rol == r, onSelected: (_) => setState(() => _rol = r)),
        ]),
        const SizedBox(height: 22),
        FilledButton(onPressed: _trabajando ? null : _vincular, child: Text(_trabajando ? 'Vinculando…' : 'Vincular')),
      ]),
    );
  }
}

// ---------------- Historial ----------------

class Historial extends StatelessWidget {
  const Historial(this.vinculos, this.estado, {super.key});
  final List<Vinculo> vinculos;
  final Map<String, Map> estado;

  @override
  Widget build(BuildContext context) {
    final items = <Map>[
      for (final v in vinculos)
        for (final h in ((estado[v.token]?['historial'] as List?) ?? []).cast<Map>()) {...h, 'tienda': v.tienda},
    ]..sort((a, b) => '${b['creado']}'.compareTo('${a['creado']}'));
    String fecha(String? iso) {
      final t = DateTime.tryParse(iso ?? '')?.toLocal();
      if (t == null) return '';
      return '${t.day}/${t.month} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(backgroundColor: cFondo, title: const Text('Historial y ajustes', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
        etiqueta('ALERTAS RECIENTES'),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Container(padding: const EdgeInsets.all(16), decoration: tarjeta(), child: const Text('Sin alertas.', style: TextStyle(color: cTexto2))),
        for (final h in items.take(30))
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: tarjeta(),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: h['prueba'] == true ? cLavanda : cCoralFondo, borderRadius: BorderRadius.circular(12)),
                child: Text(h['prueba'] == true ? 'P' : '!',
                    style: TextStyle(fontWeight: FontWeight.w800, color: h['prueba'] == true ? cIndigo : const Color(0xFFB0573F))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${h['prueba'] == true ? 'Prueba' : 'Emergencia'} · ${h['caja'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${h['tienda']} · ${h['atendida_por'] == null ? 'sin atender' : 'atendida por ${h['atendida_por']}'}',
                      style: const TextStyle(color: cTexto2, fontSize: 12.5)),
                ]),
              ),
              Text(fecha(h['creado'] as String?), style: const TextStyle(color: cTexto2, fontSize: 12)),
            ]),
          ),
        const SizedBox(height: 14),
        etiqueta('TIENDAS VINCULADAS'),
        const SizedBox(height: 8),
        for (final v in vinculos)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: tarjeta(),
            child: Row(children: [
              const Icon(Icons.storefront_rounded, color: cIndigo),
              const SizedBox(width: 12),
              Expanded(child: Text(v.tienda, style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(
                onPressed: () async {
                  final l = await nube.vinculos();
                  l.removeWhere((x) => x.token == v.token);
                  await guardarVinculos(l);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Quitar'),
              ),
            ]),
          ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: tarjeta(),
          child: const Text(
              'La alarma suena a todo volumen y en bucle aunque el celular esté en silencio, hasta que alguien toca "Ya está atendida". '
              'Para que funcione siempre, deja exBel Alerta sin restricción de batería.',
              style: TextStyle(color: cTexto2)),
        ),
        const SizedBox(height: 10),
        Text('exBel Alerta $versionApp', textAlign: TextAlign.center, style: const TextStyle(color: cTexto2, fontSize: 12)),
      ]),
    );
  }
}
