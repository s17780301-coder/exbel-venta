import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'core/caja_local.dart';
import 'core/db.dart';
import 'core/red/db_remota.dart';
import 'core/red/servidor.dart';
import 'core/formato.dart';
import 'data/repos.dart';
import 'ui/acceso/acceso_page.dart';
import 'ui/comun/ex_widgets.dart';
import 'ui/tema/tema.dart';
import 'ui/zoom.dart';
import 'data/ajustes_repo.dart';

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await windowManager.ensureInitialized();
        await windowManager.waitUntilReadyToShow(
          const WindowOptions(title: 'exBel venta', minimumSize: Size(1100, 700), center: true),
          () async {
            await windowManager.show();
            await windowManager.setFullScreen(true);
            await windowManager.focus();
          },
        );
      } catch (_) {}
    }
    runApp(const ExBelVenta());
  }, (e, s) => _registrarError('$e\n$s'));
}

Future<void> _registrarError(String texto) async {
  try {
    final dir = await AppDb.carpeta();
    await File(p.join(dir.path, 'exbel-error.txt'))
        .writeAsString('${DateTime.now()}\n$texto\n\n', mode: FileMode.append);
  } catch (_) {}
}

class ExBelVenta extends StatelessWidget {
  const ExBelVenta({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'exBel venta',
      debugShowCheckedModeBanner: false,
      theme: temaExBel(),
      locale: const Locale('es', 'MX'),
      supportedLocales: const [Locale('es', 'MX'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => ZoomPantalla(child: child ?? const SizedBox.shrink()),
      home: const _Arranque(),
    );
  }
}

class _Arranque extends StatefulWidget {
  const _Arranque();

  @override
  State<_Arranque> createState() => _ArranqueState();
}

class _ArranqueState extends State<_Arranque> {
  String? _error;
  bool _listo = false;

  /// La presentación se ve al menos este tiempo.
  late final Future<void> _presentacion = Future<void>.delayed(const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  Future<void> _abrir() async {
    setState(() => _error = null);
    try {
      await cajaLocal.cargar(await AppDb.carpeta());
      if (cajaLocal.esSecundaria) {
        // Caja adicional: usa la base de datos de la caja principal.
        final remota = DatabaseRemota(cajaLocal.servidor, cajaLocal.clave);
        await remota.ping();
        repos = Repos(remota);
      } else {
        final db = await AppDb.abrir().timeout(const Duration(seconds: 25));
        repos = Repos(db);
      }
      await repos.ajustes.cargar();
      await iniciarServidorSiToca();
      // Versión personalizada: si se quedó el nombre genérico, se pone el de la tienda.
      if (repos.ajustes.texto(Ajuste.nombreNegocio) == 'Mi tienda') {
        await repos.ajustes.guardar(Ajuste.nombreNegocio, tiendaPersonalizada);
      }
      final simbolo = repos.ajustes.texto(Ajuste.simboloMoneda);
      if (simbolo.trim().isNotEmpty) simboloMoneda = simbolo.trim();
      final z = repos.ajustes.numero(Ajuste.zoom);
      if (z >= 0.8 && z <= 2) zoomPantalla.value = z;
      await _presentacion;
      if (mounted) setState(() => _listo = true);
    } catch (e, s) {
      await _registrarError('$e\n$s');
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_listo) return const AccesoPage();
    return Scaffold(
      backgroundColor: ExColor.barra,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Presentación de la marca.
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (_, v, hijo) => Opacity(
              opacity: v,
              child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: hijo),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const ExMarca(oscuro: false, tamano: 72),
              const SizedBox(height: 18),
              Container(width: 90, height: 5, decoration: BoxDecoration(color: ExColor.acento, borderRadius: BorderRadius.circular(3))),
              const SizedBox(height: 18),
              Text('SISTEMAS PROFESIONALES DE SIMPLIFICACIÓN MERCANTIL',
                  textAlign: TextAlign.center,
                  style: ExTexto.marca(17, color: ExColor.bandaTexto, peso: FontWeight.w400).copyWith(letterSpacing: 3.2)),
            ]),
          ),
          const SizedBox(height: 48),
          if (_error == null)
            const SizedBox(width: 160, child: LinearProgressIndicator(color: ExColor.acento, backgroundColor: ExColor.banda, minHeight: 3))
          else ...[
            Text(cajaLocal.esSecundaria ? 'No se pudo conectar con la caja principal' : 'exBel venta no pudo abrir su base de datos',
                style: ExTexto.titulo(20, color: ExColor.bandaTexto)),
            const SizedBox(height: 8),
            SizedBox(
              width: 560,
              child: SelectableText(_error!,
                  textAlign: TextAlign.center, style: const TextStyle(color: ExColor.texto2)),
            ),
            const SizedBox(height: 20),
            Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: ExColor.acento, foregroundColor: ExColor.tinta),
                onPressed: _abrir,
                child: const Text('Intentar de nuevo'),
              ),
              if (cajaLocal.esSecundaria) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: ExColor.bandaTexto, side: const BorderSide(color: ExColor.borde)),
                  onPressed: () async {
                    await cajaLocal.cambiar(modo: 'principal');
                    _abrir();
                  },
                  child: const Text('Usar esta computadora sola (caja principal)'),
                ),
              ],
              const SizedBox(width: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: ExColor.bandaTexto, side: const BorderSide(color: ExColor.borde)),
                onPressed: () => Clipboard.setData(ClipboardData(text: _error!)),
                child: const Text('Copiar el error'),
              ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// En la caja principal con la red activada, abre el servidor para las
/// demás cajas.
Future<void> iniciarServidorSiToca() async {
  if (cajaLocal.esSecundaria || !cajaLocal.redActiva) return;
  if (repos.db is DatabaseRemota) return;
  final clave = await cajaLocal.claveDeRed();
  servidorCaja ??= ServidorCaja(
    repos.db,
    clave: clave,
    descripcion: () => '${repos.ajustes.texto(Ajuste.nombreNegocio)} | ${cajaLocal.nombreCaja}',
  );
  try {
    await servidorCaja!.iniciar();
  } catch (_) {
    // Si el puerto está ocupado, la caja sigue funcionando sola.
  }
}
