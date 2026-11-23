import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formato.dart';
import '../../core/ids.dart';
import '../../data/ejemplo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/csv.dart';
import '../comun/dialogos.dart';
import '../comun/importar_dialogo.dart';
import '../comun/ex_widgets.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../ventas/buscar_producto.dart';
import 'producto_form.dart';

/// F3: catálogo de productos.
class ProductosPage extends StatefulWidget {
  const ProductosPage({super.key});

  @override
  State<ProductosPage> createState() => _ProductosPageState();
}

class _ProductosPageState extends State<ProductosPage> {
  final _buscar = TextEditingController();
  List<Producto> _lista = [];
  List<Departamento> _deps = [];
  String? _dep;
  bool _bajos = false;
  final _sel = <String>{};
  int _total = 0;

  @override
  void initState() {
    super.initState();
    cambiosDatos.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    cambiosDatos.removeListener(_cargar);
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final l = await repos.productos.buscar(_buscar.text, departamentoId: _dep, soloBajos: _bajos, limite: 3000);
    final d = await repos.productos.departamentos();
    final n = await repos.productos.contar();
    if (!mounted) return;
    setState(() {
      _lista = l;
      _deps = d;
      _total = n;
      _sel.retainWhere((id) => l.any((p) => p.id == id));
    });
  }

  Future<bool> _puede() async => await autorizar(context, Permiso.productos) && mounted;

  Future<void> _editar([Producto? p]) async {
    if (!await _puede()) return;
    final ok = await editarProducto(context, p);
    if (ok) avisarCambio();
  }

  /// Elimina el producto seleccionado (o los marcados). Si no hay ninguno,
  /// lo pide por código o nombre, como en Eleventa.
  Future<void> _eliminar() async {
    if (!await _puede()) return;
    var ids = _sel.toList();
    var nombre = ids.length == 1 ? _lista.where((p) => p.id == ids.first).firstOrNull?.descripcion : null;
    if (ids.isEmpty) {
      final p = await buscarProducto(context);
      if (p == null || !mounted) return;
      ids = [p.id];
      nombre = p.descripcion;
    }
    final texto = ids.length == 1
        ? '¿Eliminar "${nombre ?? 'el producto'}" del catálogo? Sus ventas pasadas se conservan.'
        : '¿Eliminar ${ids.length} productos del catálogo? Sus ventas pasadas se conservan.';
    if (!await confirmar(context, 'Eliminar producto', texto, si: 'Eliminar', peligro: true)) return;
    for (final id in ids) {
      await repos.productos.eliminar(id);
    }
    _sel.clear();
    avisarCambio();
    if (mounted) aviso(context, ids.length == 1 ? 'Producto eliminado.' : '${ids.length} productos eliminados.');
  }

  Future<void> _cambiarPrecios() async {
    if (_sel.isEmpty) return aviso(context, 'Marca los productos a los que les cambiarás el precio.');
    if (!await _puede()) return;
    final r = await showDialog<(bool, double)>(context: context, builder: (_) => const _CambioPrecios());
    if (r == null) return;
    final n = await repos.productos.cambiarPrecios(_sel.toList(),
        porcentaje: r.$1 ? r.$2 : null, gananciaSobreCosto: r.$1 ? null : r.$2);
    if (mounted) aviso(context, 'Se actualizaron $n precios.');
    avisarCambio();
  }

  Future<void> _departamentos() async {
    if (!await _puede()) return;
    await showDialog<void>(context: context, builder: (_) => const _Departamentos());
    avisarCambio();
  }

  Future<void> _promociones() async {
    if (!await _puede()) return;
    await showDialog<void>(context: context, builder: (_) => const _Promociones());
    avisarCambio();
  }

  Future<void> _exportar() async {
    final filas = <List<String>>[
      ['codigo', 'descripcion', 'departamento', 'tipo', 'costo', 'precio', 'mayoreo', 'mayoreo_desde', 'existencia', 'minimo', 'maximo', 'iva', 'ieps'],
      for (final p in _lista)
        [
          p.codigo, p.descripcion, p.departamentoNombre ?? '', p.tipo,
          (p.costoCentavos / 100).toStringAsFixed(2), (p.precioCentavos / 100).toStringAsFixed(2),
          (p.mayoreoCentavos / 100).toStringAsFixed(2), formatoCantidad(p.mayoreoDesde),
          formatoCantidad(p.existencia), formatoCantidad(p.minimo), formatoCantidad(p.maximo),
          formatoCantidad(p.iva), formatoCantidad(p.ieps),
        ],
    ];
    await guardarCsv(context, 'productos', filas);
  }

  Future<void> _importar() async {
    if (!await _puede()) return;
    await importarDesdeArchivo(context);
  }

  Widget _boton(IconData i, String t, VoidCallback f, {bool peligro = false}) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          backgroundColor: ExColor.blanco,
          foregroundColor: peligro ? ExColor.rojo : null,
          side: BorderSide(color: peligro ? ExColor.rojo : ExColor.borde, width: 1.4),
        ),
        onPressed: f,
        icon: Icon(i, size: 20, color: peligro ? ExColor.rojo : ExColor.indigo),
        label: Text(t, style: const TextStyle(fontSize: 15)),
      );

  Future<void> _marcarTodos() async {
    setState(() {
      if (_sel.length == _lista.length) {
        _sel.clear();
      } else {
        _sel.addAll(_lista.map((p) => p.id));
      }
    });
  }

  Future<void> _ejemplo() async {
    if (!await _puede()) return;
    if (!await confirmar(context, 'Productos de ejemplo', 'Se agregan departamentos y unos 40 productos típicos de abarrotes.')) return;
    await cargarEjemplo(cajeroId: sesion.cajero?.id);
    avisarCambio();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): () {
          if (_sel.isNotEmpty) _eliminar();
        },
      },
      child: Focus(autofocus: true, child: _contenido(context)),
    );
  }

  Widget _contenido(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Productos', style: ExTexto.titulo(28)),
          const SizedBox(width: 12),
          Text('$_total en el catálogo', style: const TextStyle(color: ExColor.texto2)),
          const Spacer(),
        ]),
        const SizedBox(height: 10),
        // Barra de botones como en Eleventa.
        Wrap(spacing: 6, runSpacing: 6, children: [
          _boton(Icons.add_circle_outline, 'Nuevo', () => _editar()),
          _boton(Icons.edit_outlined, 'Modificar', () async {
            if (_sel.length == 1) return _editar(_lista.firstWhere((p) => p.id == _sel.first));
            final p = await buscarProducto(context);
            if (p != null) await _editar(p);
          }),
          _boton(Icons.delete_outline, 'Eliminar (Supr)', _eliminar, peligro: true),
          _boton(Icons.folder_outlined, 'Departamentos', _departamentos),
          _boton(Icons.local_offer_outlined, 'Promociones', _promociones),
          _boton(Icons.price_change_outlined, 'Cambiar precios', _cambiarPrecios),
          _boton(Icons.file_download_outlined, 'Importar', _importar),
          _boton(Icons.file_upload_outlined, 'Exportar', _exportar),
          _boton(Icons.checklist, 'Marcar todos', _marcarTodos),
          _boton(Icons.science_outlined, 'Productos de ejemplo', _ejemplo),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: ExBuscador(controller: _buscar, hint: 'Buscar por nombre o código', onChanged: (_) => _cargar())),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: _dep,
            hint: const Text('Todos los departamentos'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Todos los departamentos')),
              for (final d in _deps) DropdownMenuItem(value: d.id, child: Text(d.nombre)),
            ],
            onChanged: (v) {
              setState(() => _dep = v);
              _cargar();
            },
          ),
          const SizedBox(width: 12),
          FilterChip(
            label: const Text('Bajos en inventario'),
            selected: _bajos,
            onSelected: (v) {
              setState(() => _bajos = v);
              _cargar();
            },
          ),
        ]),
        const SizedBox(height: 12),
        const EncabezadoTabla([
          ('', 1, false),
          ('Código', 3, false),
          ('Descripción', 8, false),
          ('Departamento', 4, false),
          ('Costo', 3, true),
          ('Precio', 3, true),
          ('Mayoreo', 3, true),
          ('Ganancia', 2, true),
          ('Existencia', 3, true),
        ]),
        Expanded(
          child: Container(
            color: ExColor.blanco,
            child: _lista.isEmpty
                ? const ExVacio('No hay productos con ese filtro')
                : ListView.builder(
                    itemCount: _lista.length,
                    itemExtent: 44,
                    itemBuilder: (_, i) {
                      final p = _lista[i];
                      final marcado = _sel.contains(p.id);
                      return FilaTabla(
                        [
                          (
                            Checkbox(
                              value: marcado,
                              visualDensity: VisualDensity.compact,
                              onChanged: (v) => setState(() => v == true ? _sel.add(p.id) : _sel.remove(p.id)),
                            ),
                            1,
                            false
                          ),
                          (celda(p.codigo, mono: true), 3, false),
                          (
                            Row(children: [
                              if (p.favorito) const Icon(Icons.star, size: 14, color: ExColor.naranja),
                              if (p.favorito) const SizedBox(width: 4),
                              Flexible(child: celda(p.descripcion)),
                              if (p.tipo != 'unidad')
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: ExEtiqueta(p.esGranel ? 'granel' : 'paquete'),
                                ),
                            ]),
                            8,
                            false
                          ),
                          (celda(p.departamentoNombre ?? '—', color: ExColor.texto2), 4, false),
                          (celda(formatoPesos(p.costoCentavos), mono: true), 3, true),
                          (celda(formatoPesos(p.precioCentavos), mono: true, negrita: true), 3, true),
                          (celda(p.tieneMayoreo ? formatoPesos(p.mayoreoCentavos) : '—', mono: true), 3, true),
                          (celda(p.costoCentavos > 0 ? '${(p.margen * 100).round()}%' : '—', mono: true), 2, true),
                          (
                            celda(p.usaInventario ? formatoCantidad(p.existencia) : '—',
                                mono: true, color: p.bajoMinimo ? ExColor.rojo : null, negrita: p.bajoMinimo),
                            3,
                            true
                          ),
                        ],
                        par: i.isOdd,
                        seleccionada: marcado,
                        onTap: () => setState(() {
                          _sel
                            ..clear()
                            ..add(p.id);
                        }),
                        onDoubleTap: () => _editar(p),
                      );
                    },
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('${_lista.length} mostrados · ${_sel.length} marcados · doble clic para modificar',
              style: const TextStyle(color: ExColor.texto2)),
        ),
      ]),
    );
  }
}

class _CambioPrecios extends StatefulWidget {
  const _CambioPrecios();

  @override
  State<_CambioPrecios> createState() => _CambioPreciosState();
}

class _CambioPreciosState extends State<_CambioPrecios> {
  bool _porcentaje = true;
  final _v = TextEditingController();

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar precios'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Subir/bajar %')),
              ButtonSegment(value: false, label: Text('Ganancia sobre costo')),
            ],
            selected: {_porcentaje},
            onSelectionChanged: (s) => setState(() => _porcentaje = s.first),
          ),
          const SizedBox(height: 14),
          CampoNumero(
            controller: _v,
            autofocus: true,
            etiqueta: _porcentaje ? 'Porcentaje (ej. 10 o -5)' : 'Ganancia (%) sobre el costo',
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final v = leerCantidad(_v.text);
            if (v == null) return;
            Navigator.pop(context, (_porcentaje, v));
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _Departamentos extends StatefulWidget {
  const _Departamentos();

  @override
  State<_Departamentos> createState() => _DepartamentosState();
}

class _DepartamentosState extends State<_Departamentos> {
  List<Departamento> _l = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final l = await repos.productos.departamentos();
    if (mounted) setState(() => _l = l);
  }

  Future<void> _editar([Departamento? d]) async {
    final n = await pedirTexto(context, d == null ? 'Nuevo departamento' : 'Renombrar', etiqueta: 'Nombre', inicial: d?.nombre ?? '');
    if (n == null || !mounted) return;
    await intentar(context, () => repos.productos.guardarDepartamento(id: d?.id, nombre: n));
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Departamentos'),
      content: SizedBox(
        width: 480,
        height: 460,
        child: ListView(children: [
          for (final d in _l)
            ListTile(
              title: Text(d.nombre),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => _editar(d), icon: const Icon(Icons.edit_outlined)),
                IconButton(
                  onPressed: () async {
                    if (await confirmar(context, 'Eliminar departamento',
                        '¿Eliminar "${d.nombre}"? Sus productos quedan sin departamento.', si: 'Eliminar', peligro: true)) {
                      await repos.productos.eliminarDepartamento(d.id);
                      _cargar();
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
            ),
        ]),
      ),
      actions: [
        OutlinedButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Nuevo')),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo')),
      ],
    );
  }
}

class _Promociones extends StatefulWidget {
  const _Promociones();

  @override
  State<_Promociones> createState() => _PromocionesState();
}

class _PromocionesState extends State<_Promociones> {
  List<Promocion> _l = [];
  final _nombres = <String, String>{};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final l = await repos.productos.promociones();
    for (final p in l) {
      _nombres[p.productoId] ??= (await repos.productos.porId(p.productoId))?.descripcion ?? '';
    }
    if (mounted) setState(() => _l = l);
  }

  Future<void> _nueva() async {
    final p = await _elegirProducto();
    if (p == null || !mounted) return;
    final cant = await pedirCantidad(context, 'Promoción de ${p.descripcion}', etiqueta: '¿Cuántas piezas? (ej. 3)');
    if (cant == null || !mounted) return;
    final precio = await pedirMonto(context, 'Promoción de ${p.descripcion}', etiqueta: '¿Por cuánto? (\$)');
    if (precio == null || !mounted) return;
    await intentar(
      context,
      () => repos.productos.guardarPromocion(Promocion(
        id: nuevoId(),
        productoId: p.id,
        nombre: '${formatoCantidad(cant)} por ${formatoPesos(precio)}',
        cantidad: cant,
        precioCentavos: precio,
      )),
    );
    _cargar();
  }

  Future<Producto?> _elegirProducto() async {
    final t = await pedirTexto(context, 'Producto', etiqueta: 'Código o nombre');
    if (t == null) return null;
    return await repos.productos.porCodigo(t) ?? (await repos.productos.buscar(t, limite: 1)).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Promociones'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: _l.isEmpty
            ? const ExVacio('Sin promociones. Ej.: 3 refrescos por \$50.')
            : ListView(children: [
                for (final p in _l)
                  SwitchListTile(
                    title: Text(_nombres[p.productoId] ?? ''),
                    subtitle: Text(p.nombre),
                    value: p.activa,
                    onChanged: (v) async {
                      await repos.productos.guardarPromocion(Promocion(
                          id: p.id, productoId: p.productoId, nombre: p.nombre, cantidad: p.cantidad, precioCentavos: p.precioCentavos, activa: v));
                      _cargar();
                    },
                    secondary: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await repos.productos.eliminarPromocion(p.id);
                        _cargar();
                      },
                    ),
                  ),
              ]),
      ),
      actions: [
        OutlinedButton.icon(onPressed: _nueva, icon: const Icon(Icons.add), label: const Text('Nueva promoción')),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Listo')),
      ],
    );
  }
}
