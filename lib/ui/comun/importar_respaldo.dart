import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../data/importador.dart';
import '../../data/repos.dart';
import '../../data/respaldo_fbk.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import 'dialogos.dart';
import 'ex_ui.dart';

/// Importa el respaldo (.fbk) del sistema anterior: productos con su tipo de
/// venta exacto (pieza/granel), existencias, paquetes y clientes con crédito.
Future<void> importarRespaldoFbk(BuildContext context, String ruta) async {
  await showDialog<void>(context: context, barrierDismissible: false, builder: (_) => _ImportarRespaldo(ruta));
  avisarCambio();
}

class _ImportarRespaldo extends StatefulWidget {
  const _ImportarRespaldo(this.ruta);
  final String ruta;

  @override
  State<_ImportarRespaldo> createState() => _ImportarRespaldoState();
}

class _ImportarRespaldoState extends State<_ImportarRespaldo> {
  ContenidoRespaldo? _c;
  String? _error;
  bool _productos = true, _clientes = true, _reemplazar = true, _trabajando = false;
  double _avance = 0;
  (ResumenImportacion, ResumenImportacion)? _r;

  @override
  void initState() {
    super.initState();
    leerRespaldo(widget.ruta).then((c) {
      if (mounted) setState(() => _c = c);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : 'No se pudo leer el respaldo: $e');
    });
  }

  Future<void> _importar() async {
    setState(() => _trabajando = true);
    try {
      final r = await importarRespaldo(_c!,
          productos: _productos,
          clientes: _clientes,
          reemplazarExistencia: _reemplazar,
          cajeroId: sesion.cajero?.id, progreso: (h, t) {
        if (mounted && (h % 25 == 0 || h == t)) setState(() => _avance = t == 0 ? 1 : h / t);
      });
      if (mounted) setState(() => _r = r);
    } catch (e) {
      if (mounted) avisoError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  Widget _dato(IconData i, Tono t, String titulo, String sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Mosaico(i, tono: t, tamano: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(sub, style: const TextStyle(color: ExColor.texto2)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final c = _c, r = _r;
    Widget cuerpo;
    List<Widget> acciones;
    if (_error != null) {
      cuerpo = Text(_error!);
      acciones = [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))];
    } else if (c == null) {
      cuerpo = const Column(mainAxisSize: MainAxisSize.min, children: [
        LinearProgressIndicator(),
        SizedBox(height: 12),
        Text('Leyendo el respaldo… (puede tardar unos segundos)'),
      ]);
      acciones = const [];
    } else if (r != null) {
      final errores = [...r.$1.errores, ...r.$2.errores];
      cuerpo = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_productos) _dato(Icons.inventory_2_rounded, Tono.verde, 'Productos', '${r.$1.nuevos} nuevos · ${r.$1.actualizados} actualizados'),
        if (_clientes) _dato(Icons.people_alt_rounded, Tono.coral, 'Clientes', '${r.$2.nuevos} nuevos · ${r.$2.omitidos} ya estaban'),
        if (errores.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('${errores.length} con detalles:', style: const TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 120, child: ListView(children: [for (final e in errores.take(200)) Text(e, style: const TextStyle(fontSize: 12))])),
        ],
      ]);
      acciones = [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))];
    } else {
      final conSaldo = c.clientes.where((x) => (c.credito[x['ID']]?['SALDO_ACTUAL'] as num? ?? 0) > 0).length;
      final kits = c.productos.where((p) => p['ES_KIT'] == 't').length;
      cuerpo = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Esto trae el respaldo del sistema anterior:', style: TextStyle(color: ExColor.texto2)),
        const SizedBox(height: 6),
        _dato(Icons.inventory_2_rounded, Tono.verde, '${c.productos.length} productos',
            '${c.granel} a granel (por kilo) · ${c.productos.length - c.granel - kits} por pieza${kits > 0 ? ' · $kits paquetes' : ''}'),
        _dato(Icons.warehouse_rounded, Tono.ambar, 'Existencias de ${c.existencias.length} productos', 'Tal como estaban en el sistema anterior'),
        _dato(Icons.people_alt_rounded, Tono.coral, '${c.clientes.length} clientes', '$conSaldo con saldo pendiente · con su límite de crédito'),
        const Divider(height: 22),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _productos,
          onChanged: _trabajando ? null : (v) => setState(() => _productos = v ?? true),
          title: const Text('Importar productos, departamentos y existencias'),
        ),
        if (_productos)
          CheckboxListTile(
            contentPadding: const EdgeInsets.only(left: 24),
            value: _reemplazar,
            onChanged: _trabajando ? null : (v) => setState(() => _reemplazar = v ?? true),
            title: const Text('Si un producto ya existe aquí, poner la existencia del respaldo'),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _clientes,
          onChanged: _trabajando ? null : (v) => setState(() => _clientes = v ?? true),
          title: const Text('Importar clientes con lo que deben y su límite'),
        ),
        if (_trabajando) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: _avance),
          const SizedBox(height: 4),
          Text('Importando… ${formatoCantidad((_avance * 100).roundToDouble())} %', style: const TextStyle(color: ExColor.texto2)),
        ],
      ]);
      acciones = [
        TextButton(onPressed: _trabajando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: _trabajando || (!_productos && !_clientes) ? null : _importar,
          icon: const Icon(Icons.download_rounded),
          label: const Text('Importar'),
        ),
      ];
    }
    return AlertDialog(
      title: const Row(children: [
        Mosaico(Icons.restore_rounded, tono: Tono.azul, tamano: 40),
        SizedBox(width: 12),
        Text('Importar respaldo del sistema anterior'),
      ]),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: cuerpo)),
      actions: acciones,
    );
  }
}
