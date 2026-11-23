import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/ids.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../ventas/buscar_producto.dart';

/// Alta o modificación de un producto. Regresa true si se guardó.
Future<bool> editarProducto(BuildContext context, Producto? p) async {
  final r = await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _Form(p));
  return r ?? false;
}

class _Form extends StatefulWidget {
  const _Form(this.p);
  final Producto? p;

  @override
  State<_Form> createState() => _FormState();
}

String _pesos(int c) => c == 0 ? '' : (c / 100).toStringAsFixed(2);
String _cant(double c) => c == 0 ? '' : formatoCantidad(c);

class _FormState extends State<_Form> {
  late final Producto? p = widget.p;
  late final _codigo = TextEditingController(text: p?.codigo ?? '');
  late final _desc = TextEditingController(text: p?.descripcion ?? '');
  late final _costo = TextEditingController(text: _pesos(p?.costoCentavos ?? 0));
  late final _ganancia = TextEditingController(
      text: p == null ? repos.ajustes.texto(Ajuste.gananciaSugerida) : (p!.costoCentavos > 0 && p!.precioCentavos > 0
          ? ((p!.precioCentavos / p!.costoCentavos - 1) * 100).toStringAsFixed(1)
          : ''));
  late final _precio = TextEditingController(text: _pesos(p?.precioCentavos ?? 0));
  late final _mayoreo = TextEditingController(text: _pesos(p?.mayoreoCentavos ?? 0));
  late final _desde = TextEditingController(text: _cant(p?.mayoreoDesde ?? 0));
  late final _existencia = TextEditingController();
  late final _minimo = TextEditingController(text: _cant(p?.minimo ?? 0));
  late final _maximo = TextEditingController(text: _cant(p?.maximo ?? 0));
  late final _ieps = TextEditingController(text: _cant(p?.ieps ?? 0));
  late String _tipo = p?.tipo ?? 'unidad';
  late String? _dep = p?.departamentoId;
  late bool _usaInv = p?.usaInventario ?? repos.ajustes.si(Ajuste.usarInventario);
  late double _iva = p?.iva ?? repos.ajustes.numero(Ajuste.ivaPorOmision);
  late bool _favorito = p?.favorito ?? false;
  late bool _kitDescuenta = p?.kitDescuentaComponentes ?? true;
  List<Departamento> _deps = [];
  List<Componente> _componentes = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final d = await repos.productos.departamentos();
    final c = p != null && p!.esKit ? await repos.productos.componentes(p!.id) : <Componente>[];
    if (mounted) {
      setState(() {
        _deps = d;
        _componentes = c;
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_codigo, _desc, _costo, _ganancia, _precio, _mayoreo, _desde, _existencia, _minimo, _maximo, _ieps]) {
      c.dispose();
    }
    super.dispose();
  }

  void _desdeGanancia(String _) {
    final costo = leerPesos(_costo.text);
    final g = leerCantidad(_ganancia.text);
    if (costo == null || costo <= 0 || g == null) return;
    _precio.text = (costo * (1 + g / 100) / 100).toStringAsFixed(2);
  }

  void _desdePrecio(String _) {
    final costo = leerPesos(_costo.text);
    final precio = leerPesos(_precio.text);
    if (costo == null || costo <= 0 || precio == null) return;
    _ganancia.text = ((precio / costo - 1) * 100).toStringAsFixed(1);
  }

  Future<void> _nuevoDepartamento() async {
    final n = await pedirTexto(context, 'Nuevo departamento', etiqueta: 'Nombre');
    if (n == null || !mounted) return;
    await intentar(context, () async {
      final d = await repos.productos.guardarDepartamento(nombre: n);
      await _cargar();
      setState(() => _dep = d.id);
    });
  }

  Future<void> _agregarComponente() async {
    final prod = await buscarProducto(context);
    if (prod == null || !mounted) return;
    if (prod.esKit) return aviso(context, 'Un paquete no puede llevar otro paquete.');
    final c = await pedirCantidad(context, prod.descripcion, etiqueta: '¿Cuántos lleva el paquete?', inicial: 1);
    if (c == null || c <= 0) return;
    setState(() {
      _componentes.removeWhere((x) => x.productoId == prod.id);
      _componentes.add(Componente(productoId: prod.id, descripcion: prod.descripcion, cantidad: c, precioCentavos: prod.precioCentavos));
    });
  }

  Future<void> _eliminar() async {
    final prod = p;
    if (prod == null) return;
    if (!await confirmar(context, 'Eliminar producto',
        '¿Eliminar "${prod.descripcion}" del catálogo? Sus ventas pasadas se conservan.',
        si: 'Eliminar', peligro: true)) {
      return;
    }
    await repos.productos.eliminar(prod.id);
    avisarCambio();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _guardar() async {
    if (_tipo == 'kit' && _componentes.isEmpty) return aviso(context, 'Agrega los productos que lleva el paquete.');
    final nuevo = Producto(
      id: p?.id ?? nuevoId(),
      codigo: _codigo.text.trim(),
      descripcion: _desc.text.trim(),
      tipo: _tipo,
      departamentoId: _dep,
      costoCentavos: leerPesos(_costo.text) ?? 0,
      precioCentavos: leerPesos(_precio.text) ?? 0,
      mayoreoCentavos: leerPesos(_mayoreo.text) ?? 0,
      mayoreoDesde: leerCantidad(_desde.text) ?? 0,
      usaInventario: _tipo == 'kit' ? false : _usaInv,
      existencia: p?.existencia ?? 0,
      minimo: leerCantidad(_minimo.text) ?? 0,
      maximo: leerCantidad(_maximo.text) ?? 0,
      iva: _iva,
      ieps: leerCantidad(_ieps.text) ?? 0,
      favorito: _favorito,
      kitDescuentaComponentes: _kitDescuenta,
    );
    final ok = await intentar(context, () async {
      await repos.productos.guardar(nuevo,
          existenciaInicial: p == null ? (leerCantidad(_existencia.text) ?? 0) : 0, cajeroId: sesion.cajero?.id);
      if (_tipo == 'kit') await repos.productos.guardarComponentes(nuevo.id, _componentes);
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  Widget _fila(List<Widget> hijos) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < hijos.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: hijos[i])],
        ]),
      );

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Text(t, style: ExTexto.titulo(15, color: ExColor.indigo)),
      );

  @override
  Widget build(BuildContext context) {
    final sumaKit = _componentes.fold<int>(0, (s, c) => s + calcularImporte(c.cantidad, c.precioCentavos));
    return AlertDialog(
      title: Text(p == null ? 'Nuevo producto' : 'Modificar producto'),
      content: SizedBox(
        width: 780,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _fila([
              TextField(
                controller: _codigo,
                autofocus: p == null,
                style: ExTexto.mono(15, peso: FontWeight.w500),
                decoration: const InputDecoration(labelText: 'Código de barras', helperText: 'Escanéalo o inventa uno corto'),
              ),
              TextField(
                controller: _desc,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
            ]),
            Row(children: [
              const Text('Se vende por:  '),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'unidad', label: Text('Unidad / pieza')),
                  ButtonSegment(value: 'granel', label: Text('Granel (kg, l)')),
                  ButtonSegment(value: 'kit', label: Text('Paquete')),
                ],
                selected: {_tipo},
                onSelectionChanged: (s) => setState(() => _tipo = s.first),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _deps.any((d) => d.id == _dep) ? _dep : null,
                  decoration: const InputDecoration(labelText: 'Departamento'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sin departamento')),
                    for (final d in _deps) DropdownMenuItem(value: d.id, child: Text(d.nombre)),
                  ],
                  onChanged: (v) => setState(() => _dep = v),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(onPressed: _nuevoDepartamento, icon: const Icon(Icons.add), label: const Text('Nuevo')),
              const SizedBox(width: 12),
              FilterChip(
                avatar: const Icon(Icons.star, size: 16),
                label: const Text('Favorito (botón rápido en Ventas)'),
                selected: _favorito,
                onSelected: (v) => setState(() => _favorito = v),
              ),
            ]),
            const SizedBox(height: 8),
            _titulo('Precios'),
            _fila([
              CampoNumero(controller: _costo, etiqueta: 'Precio de costo', onChanged: _desdeGanancia),
              CampoNumero(controller: _ganancia, etiqueta: 'Ganancia (%)', onChanged: _desdeGanancia),
              CampoNumero(
                  controller: _precio,
                  etiqueta: _tipo == 'granel' ? 'Precio venta por kg' : 'Precio de venta',
                  ayuda: 'Con impuestos incluidos',
                  onChanged: _desdePrecio),
            ]),
            _fila([
              CampoNumero(controller: _mayoreo, etiqueta: 'Precio de mayoreo', ayuda: 'Vacío = no tiene'),
              CampoNumero(controller: _desde, etiqueta: 'Mayoreo automático desde', ayuda: 'Piezas. Vacío = solo con F11'),
              const SizedBox.shrink(),
            ]),
            _titulo('Impuestos'),
            Row(children: [
              const Text('IVA:  '),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('0% / exento')),
                  ButtonSegment(value: 8, label: Text('8% frontera')),
                  ButtonSegment(value: 16, label: Text('16%')),
                ],
                selected: {_iva},
                onSelectionChanged: (s) => setState(() => _iva = s.first),
              ),
              const SizedBox(width: 16),
              SizedBox(width: 160, child: CampoNumero(controller: _ieps, etiqueta: 'IEPS (%)')),
            ]),
            const SizedBox(height: 8),
            if (_tipo == 'kit') ...[
              _titulo('Contenido del paquete'),
              for (final c in _componentes)
                ListTile(
                  dense: true,
                  title: Text(c.descripcion),
                  subtitle: Text('${formatoCantidad(c.cantidad)} × ${formatoPesos(c.precioCentavos)}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _componentes.remove(c)),
                  ),
                ),
              Row(children: [
                OutlinedButton.icon(onPressed: _agregarComponente, icon: const Icon(Icons.add), label: const Text('Agregar producto')),
                const SizedBox(width: 12),
                if (_componentes.isNotEmpty) Text('Por separado costarían ${formatoPesos(sumaKit)}'),
              ]),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _kitDescuenta,
                onChanged: (v) => setState(() => _kitDescuenta = v ?? true),
                title: const Text('Al vender el paquete, descontar del inventario los productos que lleva'),
              ),
            ] else ...[
              _titulo('Inventario'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _usaInv,
                onChanged: (v) => setState(() => _usaInv = v),
                title: const Text('Este producto usa inventario'),
              ),
              if (_usaInv)
                _fila([
                  if (p == null)
                    CampoNumero(controller: _existencia, etiqueta: 'Hay (existencia inicial)')
                  else
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Existencia actual', helperText: 'Se cambia en Inventario'),
                      child: Text(formatoCantidad(p!.existencia)),
                    ),
                  CampoNumero(controller: _minimo, etiqueta: 'Mínimo', ayuda: 'Avisa cuando hay pocos'),
                  CampoNumero(controller: _maximo, etiqueta: 'Máximo', ayuda: 'Para el pedido sugerido'),
                ]),
            ],
          ]),
        ),
      ),
      actions: [
        if (p != null)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: ExColor.rojo),
            onPressed: _eliminar,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Eliminar producto'),
          ),
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: _guardar, child: const Text('Guardar producto')),
      ],
    );
  }
}
