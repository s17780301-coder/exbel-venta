import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'core/db.dart';
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

  @override
  void initState() {
    super.initState();
    _abrir();
  }

  Future<void> _abrir() async {
    setState(() => _error = null);
    try {
      final db = await AppDb.abrir().timeout(const Duration(seconds: 25));
      repos = Repos(db);
      await repos.ajustes.cargar();
      final simbolo = repos.ajustes.texto(Ajuste.simboloMoneda);
      if (simbolo.trim().isNotEmpty) simboloMoneda = simbolo.trim();
      final z = repos.ajustes.numero(Ajuste.zoom);
      if (z >= 0.8 && z <= 2) zoomPantalla.value = z;
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
      backgroundColor: ExColor.tinta,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ExMarca(oscuro: true, tamano: 34),
          const SizedBox(height: 8),
          Text('venta', style: ExTexto.marca(20, color: ExColor.textoClaro2, peso: FontWeight.w300)),
          const SizedBox(height: 32),
          if (_error == null)
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: ExColor.acento))
          else ...[
            Text('exBel venta no pudo abrir su base de datos',
                style: ExTexto.titulo(20, color: ExColor.concreto)),
            const SizedBox(height: 8),
            SizedBox(
              width: 560,
              child: SelectableText(_error!,
                  textAlign: TextAlign.center, style: const TextStyle(color: ExColor.textoClaro)),
            ),
            const SizedBox(height: 20),
            Row(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: ExColor.acento, foregroundColor: ExColor.tinta),
                onPressed: _abrir,
                child: const Text('Intentar de nuevo'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                    foregroundColor: ExColor.concreto, side: const BorderSide(color: ExColor.textoClaro2)),
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
