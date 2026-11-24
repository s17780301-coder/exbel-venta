import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/importador.dart';
import '../../data/repos.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../zoom.dart';
import 'dialogos.dart';

/// Importa productos o clientes desde el Excel que exporta otro sistema (u otro
/// sistema). Detecta las columnas solo y deja corregirlas antes de importar.
Future<void> importarDesdeArchivo(BuildContext context, {bool clientes = false}) async {
  final r = await FilePicker.platform.pickFiles(
    dialogTitle: clientes ? 'Archivo de clientes' : 'Catálogo de productos',
    type: FileType.custom,
    allowedExtensions: ['xlsx', 'xls', 'csv', 'txt'],
  );
  final ruta = r?.files.single.path;
  if (ruta == null || !context.mounted) return;
  if (ruta.toLowerCase().endsWith('.xls')) {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Archivo de Excel antiguo (.xls)'),
        content: const SizedBox(
          width: 460,
          child: Text('Ábrelo en Excel y usa "Guardar como" → "Libro de Excel (.xlsx)". '
              'Después impórtalo aquí.'),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Entendido'))],
      ),
    );
    return;
  }
  List<List<String>> filas;
  try {
    filas = leerTabla(await File(ruta).readAsBytes(), ruta);
  } catch (e) {
    if (context.mounted) aviso(context, 'No se pudo leer el archivo: $e');
    return;
  }
  if (filas.length < 2) {
    if (context.mounted) aviso(context, 'El archivo no tiene datos.');
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _Importar(filas: filas, clientes: clientes, archivo: ruta.split(RegExp(r'[\\/]')).last),
  );
  avisarCambio();
}

class _Importar extends StatefulWidget {
  const _Importar({required this.filas, required this.clientes, required this.archivo});
  final List<List<String>> filas;
  final bool clientes;
  final String archivo;

  @override
  State<_Importar> createState() => _ImportarState();
}

class _ImportarState extends State<_Importar> {
  late final campos = widget.clientes ? camposCliente : camposProducto;
  late int _encabezado;
  late Map<String, int> _cols;
  bool _reemplazar = true;
  bool _granel = true;
  bool _trabajando = false;
  double _avance = 0;
  ResumenImportacion? _resumen;

  @override
  void initState() {
    super.initState();
    final (fila, cols) = detectarColumnas(widget.filas, campos);
    _encabezado = fila;
    _cols = cols;
  }

  List<String> get _titulos => widget.filas[_encabezado];
  int get _datos => widget.filas.length - _encabezado - 1;

  int get _conDecimales {
    final i = _cols['existencia'];
    if (i == null) return 0;
    return widget.filas.skip(_encabezado + 1).where((f) => i < f.length && tieneDecimales(f[i])).length;
  }

  Future<void> _importar() async {
    final faltan = campos.where((c) => c.obligatorio && !_cols.containsKey(c.clave)).map((c) => c.nombre).toList();
    if (faltan.isNotEmpty) return aviso(context, 'Indica qué columna es: ${faltan.join(', ')}.');
    setState(() => _trabajando = true);
    try {
      final r = widget.clientes
          ? await importarClientes(widget.filas, _encabezado, _cols)
          : await importarProductos(
              widget.filas,
              _encabezado,
              _cols,
              reemplazarExistencia: _reemplazar,
              granelSiDecimales: _granel && !_cols.containsKey('tipo'),
              cajeroId: sesion.cajero?.id,
              progreso: (h, t) {
                if (mounted && (h % 25 == 0 || h == t)) setState(() => _avance = t == 0 ? 1 : h / t);
              },
            );
      if (mounted) setState(() => _resumen = r);
    } catch (e) {
      if (mounted) avisoError(context, e);
    } finally {
      if (mounted) setState(() => _trabajando = false);
    }
  }

  String _valor(List<String> f, String campo) {
    final i = _cols[campo];
    return i == null || i >= f.length ? '' : muestra(f[i]);
  }

  @override
  Widget build(BuildContext context) {
    final r = _resumen;
    if (r != null) return _final(r);
    final ejemplos = widget.filas.skip(_encabezado + 1).take(5).toList();
    final usados = campos.where((c) => _cols.containsKey(c.clave)).toList();
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: anchoDialogo(context, 1000),
        height: altoDialogo(context, 700),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: ExColor.banda,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Text(
              widget.clientes ? 'Importar clientes' : 'Importar productos',
              style: ExTexto.titulo(20, color: ExColor.bandaTexto),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('${widget.archivo} · $_datos filas', style: const TextStyle(color: ExColor.texto2)),
                const SizedBox(height: 6),
                const Text('Las columnas se detectaron automáticamente. Verifica que cada dato corresponda a la columna correcta antes de importar.'),
                const SizedBox(height: 14),
                Wrap(spacing: 14, runSpacing: 12, children: [
                  for (final c in campos)
                    SizedBox(
                      width: 290,
                      child: DropdownButtonFormField<int?>(
                        value: _cols[c.clave],
                        isExpanded: true,
                        decoration: InputDecoration(labelText: c.obligatorio ? '${c.nombre} *' : c.nombre),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('— No importar —')),
                          for (var i = 0; i < _titulos.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(_titulos[i].trim().isEmpty ? 'Columna ${i + 1}' : _titulos[i], overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) => setState(() {
                          if (v == null) {
                            _cols.remove(c.clave);
                          } else {
                            _cols.removeWhere((_, col) => col == v);
                            _cols[c.clave] = v;
                          }
                        }),
                      ),
                    ),
                ]),
                const SizedBox(height: 18),
                Text('Así se verán los primeros', style: ExTexto.titulo(16)),
                const SizedBox(height: 8),
                EncabezadoTabla([for (final c in usados) (c.nombre, c.clave == 'descripcion' || c.clave == 'nombre' ? 4 : 2, false)]),
                for (var i = 0; i < ejemplos.length; i++)
                  FilaTabla([for (final c in usados) (celda(_valor(ejemplos[i], c.clave)), c.clave == 'descripcion' || c.clave == 'nombre' ? 4 : 2, false)],
                      par: i.isOdd),
                const SizedBox(height: 14),
                if (!widget.clientes && !_cols.containsKey('tipo') && _cols.containsKey('existencia'))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _granel,
                    onChanged: (v) => setState(() => _granel = v ?? true),
                    title: Text('Marcar como granel (kg) los que tienen existencia con decimales ($_conDecimales productos)'),
                    subtitle: const Text('Muchos sistemas no exportan si un producto es a granel; los decimales (ej. arroz 20.24) lo delatan.'),
                  ),
                if (!widget.clientes)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _reemplazar,
                    onChanged: (v) => setState(() => _reemplazar = v ?? true),
                    title: const Text('Si el producto ya existe, dejar la existencia que trae el archivo'),
                    subtitle: const Text('Los productos con el mismo código se actualizan, no se duplican.'),
                  )
                else
                  const Text('Lo que debe cada cliente queda como "Saldo anterior" en su estado de cuenta. '
                      'Los clientes que ya existen (mismo nombre) se saltan.',
                      style: TextStyle(color: ExColor.texto2)),
              ]),
            ),
          ),
          if (_trabajando) LinearProgressIndicator(value: widget.clientes ? null : _avance),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Spacer(),
              TextButton(onPressed: _trabajando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _trabajando ? null : _importar,
                child: Text(_trabajando ? 'Importando…' : 'Importar $_datos ${widget.clientes ? 'clientes' : 'productos'}'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _final(ResumenImportacion r) {
    return AlertDialog(
      title: const Text('Importación terminada'),
      content: SizedBox(
        width: 520,
        height: r.errores.isEmpty ? null : altoDialogo(context, 420),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nuevos: ${r.nuevos}', style: ExTexto.titulo(18, color: ExColor.verde)),
          if (!widget.clientes) Text('Actualizados: ${r.actualizados}', style: ExTexto.titulo(18)),
          if (r.omitidos > 0) Text('Saltados (vacíos o repetidos): ${r.omitidos}'),
          if (r.errores.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Con problema: ${r.errores.length}', style: const TextStyle(color: ExColor.rojo, fontWeight: FontWeight.w700)),
            Expanded(child: ListView(children: [for (final e in r.errores) Text(e, style: const TextStyle(fontSize: 13))])),
          ],
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo'))],
    );
  }
}
