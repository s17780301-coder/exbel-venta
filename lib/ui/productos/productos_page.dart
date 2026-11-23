import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/ids.dart';
import '../../data/ejemplo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/csv.dart';
import '../comun/dialogos.dart';
import '../comun/ex_widgets.dart';
import '../sesion.dart';
import '../tema/tema.dart';
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

  Future<void> _eliminar() async {
    if (_sel.isEmpty || !await _puede()) return;
    if (!await confirmar(context, 'Eliminar productos', '¿Eliminar ${_sel.length} producto(s) del catálogo? Sus ventas se conservan.',
        si: 'Eliminar', peligro: true)) {
      return;
    }
    for (final id in _sel) {
      await repos.productos.eliminar(id);
    }
    _sel.clear();
    avisarCambio();
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
    final filas = await abrirCsv(context);
    if (filas == null || filas.length < 2 || !mounted) return;
    final enc = filas.first.map((x) => x.trim().toLowerCase()).toList();
    int col(String n) => enc.indexOf(n);
    final iCod = col('codigo'), iDesc = col('descripcion'), iPrecio = col('precio');
    if (iDesc < 0 || iPrecio < 0) {
      return aviso(context, 'El archivo necesita al menos las columnas "descripcion" y "precio".');
    }
    final deps = {for (final d in await repos.productos.departamentos()) d.nombre.toLowerCase(): d.id};
    var nuevos = 0, actualizados = 0, errores = 0;
    String v(List<String> f, int i) => i >= 0 && i < f.length ? f[i].trim() : '';
    for (final f in filas.skip(1)) {
      try {
        final codigo = v(f, iCod);
        final existente = codigo.isEmpty ? null : await repos.productos.porCodigo(codigo);
        final depNombre = v(f, col('departamento'));
        String? depId;
        if (depNombre.isNotEmpty) {
          depId = deps[depNombre.toLowerCase()] ??= (await repos.productos.guardarDepartamento(nombre: depNombre)).id;
        }
        final tipo = v(f, col('tipo'));
        final p = Producto(
          id: existente?.id ?? nuevoId(),
          codigo: codigo,
          descripcion: v(f, iDesc),
          departamentoId: depId ?? existente?.departamentoId,
          tipo: ['unidad', 'granel', 'kit'].contains(tipo) ? tipo : (existente?.tipo ?? 'unidad'),
          costoCentavos: leerPesos(v(f, col('costo'))) ?? existente?.costoCentavos ?? 0,
          precioCentavos: leerPesos(v(f, iPrecio)) ?? 0,
          mayoreoCentavos: leerPesos(v(f, col('mayoreo'))) ?? existente?.mayoreoCentavos ?? 0,
          mayoreoDesde: leerCantidad(v(f, col('mayoreo_desde'))) ?? existente?.mayoreoDesde ?? 0,
          minimo: leerCantidad(v(f, col('minimo'))) ?? existente?.minimo ?? 0,
          maximo: leerCantidad(v(f, col('maximo'))) ?? existente?.maximo ?? 0,
          iva: leerCantidad(v(f, col('iva'))) ?? existente?.iva ?? 0,
          ieps: leerCantidad(v(f, col('ieps'))) ?? existente?.ieps ?? 0,
        );
        final exist = leerCantidad(v(f, col('existencia')));
        await repos.productos.guardar(p, existenciaInicial: existente == null ? (exist ?? 0) : 0, cajeroId: sesion.cajero?.id);
        if (existente != null && exist != null) {
          await repos.productos.ajustarInventario(p.id, exist, motivo: 'Importación', cajeroId: sesion.cajero?.id);
        }
        existente == null ? nuevos++ : actualizados++;
      } catch (_) {
        errores++;
      }
    }
    avisarCambio();
    if (mounted) aviso(context, 'Importados: $nuevos nuevos, $actualizados actualizados${errores > 0 ? ', $errores con error' : ''}.');
  }

  Future<void> _ejemplo() async {
    if (!await _puede()) return;
    if (!await confirmar(context, 'Productos de ejemplo', 'Se agregan departamentos y unos 40 productos típicos de abarrotes.')) return;
    await cargarEjemplo(cajeroId: sesion.cajero?.id);
    avisarCambio();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Productos', style: ExTexto.titulo(28)),
          const SizedBox(width: 12),
          Text('$_total en el catálogo', style: const TextStyle(color: ExColor.texto2)),
          const Spacer(),
          FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Nuevo producto')),
          const SizedBox(width: 8),
          OutlinedButton(
              onPressed: _sel.length == 1 ? () => _editar(_lista.firstWhere((p) => p.id == _sel.first)) : null,
              child: const Text('Modificar')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: _sel.isEmpty ? null : _eliminar, child: const Text('Eliminar')),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (v) => switch (v) {
              'dep' => _departamentos(),
              'promo' => _promociones(),
              'precios' => _cambiarPrecios(),
              'exp' => _exportar(),
              'imp' => _importar(),
              _ => _ejemplo(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dep', child: Text('Departamentos')),
              PopupMenuItem(value: 'promo', child: Text('Promociones (N por \$)')),
              PopupMenuItem(value: 'precios', child: Text('Cambiar precios de los marcados')),
              PopupMenuItem(value: 'exp', child: Text('Exportar a Excel (CSV)')),
              PopupMenuItem(value: 'imp', child: Text('Importar desde Excel (CSV)')),
              PopupMenuItem(value: 'ej', child: Text('Cargar productos de ejemplo')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [Text('Más'), Icon(Icons.arrow_drop_down)]),
            ),
          ),
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
                        onTap: () => setState(() => marcado ? _sel.remove(p.id) : _sel.add(p.id)),
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
