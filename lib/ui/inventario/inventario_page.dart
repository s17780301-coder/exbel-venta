import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../data/ajustes_repo.dart';
import '../../data/productos_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/csv.dart';
import '../comun/dialogos.dart';
import '../comun/enter_avanza.dart';
import '../comun/ex_ui.dart';
import '../comun/ex_widgets.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../ventas/buscar_producto.dart';

/// F4: inventario.
class InventarioPage extends StatefulWidget {
  const InventarioPage({super.key});

  @override
  State<InventarioPage> createState() => _InventarioPageState();
}

const _vistas = [
  ('Agregar mercancía', Icons.add_box_outlined),
  ('Ajustar (conteo)', Icons.tune),
  ('Salidas y mermas', Icons.outbox_outlined),
  ('Bajos en inventario', Icons.warning_amber_outlined),
  ('Pedido sugerido', Icons.shopping_cart_outlined),
  ('Reporte de inventario', Icons.summarize_outlined),
  ('Movimientos (kardex)', Icons.history),
];

class _InventarioPageState extends State<InventarioPage> {
  int _vista = 0;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 250,
        decoration: const BoxDecoration(color: Color(0xFFFCFCFD), border: Border(right: BorderSide(color: Color(0xFFE3E1EE)))),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: const TituloSeccion('Inventario', icono: Icons.warehouse_rounded, tono: Tono.ambar),
          ),
          for (var i = 0; i < _vistas.length; i++)
            ListTile(
              selected: _vista == i,
              selectedTileColor: const Color(0xFFF0EEF9),
              selectedColor: ExColor.tinta,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              leading: Mosaico(_vistas[i].$2, tono: Tono.todos[i % Tono.todos.length], tamano: 34),
              title: Text(_vistas[i].$1),
              onTap: () => setState(() => _vista = i),
            ),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_vista) {
            0 => const _Movimiento(tipo: 'Entrada'),
            1 => const _Movimiento(tipo: 'Ajuste'),
            2 => const _Movimiento(tipo: 'Salida'),
            3 => const _Bajos(pedido: false),
            4 => const _Bajos(pedido: true),
            5 => const _Reporte(),
            _ => const _Kardex(),
          },
        ),
      ),
    ]);
  }
}

/// Si la pantalla de entrada/ajuste/salida está abierta, el buscador
/// universal (F10) le pasa aquí el producto elegido.
void Function(Producto)? elegirEnInventario;

/// Entrada, ajuste o salida de un producto.
class _Movimiento extends StatefulWidget {
  const _Movimiento({required this.tipo});
  final String tipo;

  @override
  State<_Movimiento> createState() => _MovimientoState();
}

class _MovimientoState extends State<_Movimiento> {
  final _codigo = TextEditingController();
  final _cant = TextEditingController();
  final _costo = TextEditingController();
  final _precio = TextEditingController();
  final _motivo = TextEditingController();
  final _focoCodigo = FocusNode();
  Producto? _p;
  final _hechos = <String>[];

  @override
  void initState() {
    super.initState();
    elegirEnInventario = _ponerProducto;
  }

  void _ponerProducto(Producto p) {
    if (!mounted) return;
    setState(() {
      _p = p;
      _codigo.clear();
      _cant.text = widget.tipo == 'Ajuste' ? formatoCantidad(p.existencia) : '';
      _costo.text = (p.costoCentavos / 100).toStringAsFixed(2);
      _precio.text = (p.precioCentavos / 100).toStringAsFixed(2);
    });
  }

  @override
  void dispose() {
    if (elegirEnInventario == _ponerProducto) elegirEnInventario = null;
    for (final c in [_codigo, _cant, _costo, _precio, _motivo]) {
      c.dispose();
    }
    _focoCodigo.dispose();
    super.dispose();
  }

  Future<void> _elegir(String t) async {
    var p = await repos.productos.porCodigo(t);
    if (p == null && mounted) p = await buscarProducto(context, texto: t);
    if (!mounted) return;
    setState(() {
      _p = p;
      _codigo.clear();
      _cant.text = widget.tipo == 'Ajuste' && p != null ? formatoCantidad(p.existencia) : '';
      _costo.text = p == null ? '' : (p.costoCentavos / 100).toStringAsFixed(2);
      _precio.text = p == null ? '' : (p.precioCentavos / 100).toStringAsFixed(2);
    });
  }

  Future<void> _guardar() async {
    final p = _p;
    if (p == null) return;
    if (!await autorizar(context, Permiso.inventario) || !mounted) return;
    final c = leerCantidad(_cant.text);
    if (c == null) return aviso(context, 'Escribe la cantidad.');
    final cajero = sesion.cajero?.id;
    final ok = await intentar(context, () async {
      switch (widget.tipo) {
        case 'Entrada':
          final precio = leerPesos(_precio.text);
          await repos.productos.agregarInventario(p.id, c,
              costoCentavos: leerPesos(_costo.text),
              nuevoPrecioCentavos: precio != p.precioCentavos ? precio : null,
              costoPromedio: repos.ajustes.si(Ajuste.costoPromedio),
              cajeroId: cajero);
        case 'Ajuste':
          await repos.productos.ajustarInventario(p.id, c,
              motivo: _motivo.text.trim().isEmpty ? 'Ajuste por conteo' : _motivo.text.trim(), cajeroId: cajero);
        default:
          await repos.productos.salidaInventario(p.id, c,
              motivo: _motivo.text.trim().isEmpty ? 'Merma' : _motivo.text.trim(), cajeroId: cajero);
      }
    });
    if (!ok || !mounted) return;
    avisarCambio();
    final nuevo = await repos.productos.porId(p.id);
    setState(() {
      _hechos.insert(0, '${widget.tipo}: ${p.descripcion} → ahora hay ${formatoCantidad(nuevo?.existencia ?? 0)}');
      _p = null;
      _cant.clear();
      _motivo.clear();
    });
    _focoCodigo.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final titulo = switch (widget.tipo) {
      'Entrada' => 'Agregar mercancía al inventario',
      'Ajuste' => 'Ajustar inventario (conteo físico)',
      _ => 'Salidas: merma, caducado, consumo',
    };
    return EnterGuarda(onGuardar: _guardar, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(titulo, style: ExTexto.titulo(22)),
      const SizedBox(height: 14),
      ExBuscador(
        controller: _codigo,
        focusNode: _focoCodigo,
        autofocus: true,
        hint: 'Escanea el código o escribe el nombre y da ENTER',
        onSubmitted: _elegir,
      ),
      const SizedBox(height: 18),
      if (p != null)
        ExSeccion(
          titulo: p.descripcion,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Código ${p.codigo} · Hay ${formatoCantidad(p.existencia)} · Costo ${formatoPesos(p.costoCentavos)} · '
                'Precio ${formatoPesos(p.precioCentavos)}'),
            if (!p.usaInventario)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Este producto no usa inventario. Actívalo en Productos.', style: TextStyle(color: ExColor.rojo)),
              ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: CampoNumero(
                  controller: _cant,
                  autofocus: true,
                  etiqueta: widget.tipo == 'Ajuste' ? 'Cantidad que hay realmente' : 'Cantidad',
                  // En entradas, Enter pasa a costo y precio; en el último guarda.
                  onSubmitted: widget.tipo == 'Entrada' ? null : (_) => _guardar(),
                ),
              ),
              const SizedBox(width: 12),
              if (widget.tipo == 'Entrada') ...[
                Expanded(child: CampoNumero(controller: _costo, etiqueta: 'Costo por unidad')),
                const SizedBox(width: 12),
                Expanded(child: CampoNumero(controller: _precio, etiqueta: 'Precio de venta (cámbialo si subió)')),
              ] else
                Expanded(
                  flex: 2,
                  child: TextField(
                      controller: _motivo,
                      decoration: InputDecoration(
                          labelText: 'Motivo', hintText: widget.tipo == 'Ajuste' ? 'Conteo físico' : 'Caducado, roto, consumo…'),
                      onSubmitted: (_) => _guardar()),
                ),
            ]),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(onPressed: _guardar, child: Text('Registrar ${widget.tipo.toLowerCase()}')),
            ),
          ]),
        ),
      const SizedBox(height: 16),
      if (_hechos.isNotEmpty) Text('Registrado en esta sesión', style: ExTexto.titulo(15)),
      Expanded(
        child: ListView(children: [
          for (final h in _hechos)
            ListTile(dense: true, leading: const Icon(Icons.check, color: ExColor.verde), title: Text(h)),
        ]),
      ),
    ]));
  }
}

class _Bajos extends StatefulWidget {
  const _Bajos({required this.pedido});
  final bool pedido;

  @override
  State<_Bajos> createState() => _BajosState();
}

class _BajosState extends State<_Bajos> {
  List<Producto> _l = [];

  @override
  void initState() {
    super.initState();
    cambiosDatos.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    cambiosDatos.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final l = await repos.productos.buscar('', soloBajos: true, limite: 5000);
    if (mounted) setState(() => _l = l);
  }

  double _pedir(Producto p) {
    final objetivo = p.maximo > 0 ? p.maximo : p.minimo * 2;
    final x = objetivo - p.existencia;
    return x > 0 ? x : 0;
  }

  @override
  Widget build(BuildContext context) {
    final costo = _l.fold<int>(0, (s, p) => s + calcularImporte(_pedir(p), p.costoCentavos));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(widget.pedido ? 'Pedido sugerido' : 'Productos bajos en inventario', style: ExTexto.titulo(22)),
        const Spacer(),
        if (widget.pedido) Text('Costo estimado ${formatoPesos(costo)}   ', style: ExTexto.titulo(16)),
        OutlinedButton.icon(
          onPressed: () => guardarCsv(context, widget.pedido ? 'pedido-sugerido' : 'bajos-inventario', [
            ['codigo', 'descripcion', 'departamento', 'existencia', 'minimo', 'maximo', if (widget.pedido) 'pedir'],
            for (final p in _l)
              [
                p.codigo, p.descripcion, p.departamentoNombre ?? '', formatoCantidad(p.existencia),
                formatoCantidad(p.minimo), formatoCantidad(p.maximo), if (widget.pedido) formatoCantidad(_pedir(p)),
              ],
          ]),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Exportar'),
        ),
      ]),
      if (widget.pedido)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Lo que hay que comprar para llegar al máximo (o al doble del mínimo si no tiene máximo).',
              style: TextStyle(color: ExColor.texto2)),
        ),
      const SizedBox(height: 12),
      EncabezadoTabla([
        ('Código', 3, false),
        ('Descripción', 8, false),
        ('Departamento', 4, false),
        ('Hay', 2, true),
        ('Mínimo', 2, true),
        if (widget.pedido) ('Pedir', 2, true) else ('Máximo', 2, true),
      ]),
      Expanded(
        child: Container(
          color: ExColor.blanco,
          child: _l.isEmpty
              ? const ExVacio('Todo en orden: ningún producto está bajo su mínimo')
              : ListView.builder(
                  itemCount: _l.length,
                  itemBuilder: (_, i) {
                    final p = _l[i];
                    return FilaTabla([
                      (celda(p.codigo, mono: true), 3, false),
                      (celda(p.descripcion), 8, false),
                      (celda(p.departamentoNombre ?? '—', color: ExColor.texto2), 4, false),
                      (celda(formatoCantidad(p.existencia), mono: true, color: ExColor.rojo, negrita: true), 2, true),
                      (celda(formatoCantidad(p.minimo), mono: true), 2, true),
                      (celda(formatoCantidad(widget.pedido ? _pedir(p) : p.maximo), mono: true, negrita: widget.pedido), 2, true),
                    ], par: i.isOdd);
                  },
                ),
        ),
      ),
    ]);
  }
}

class _Reporte extends StatefulWidget {
  const _Reporte();

  @override
  State<_Reporte> createState() => _ReporteState();
}

class _ReporteState extends State<_Reporte> {
  List<Departamento> _deps = [];
  String? _dep;
  (double, int, int) _valor = (0, 0, 0);
  List<Producto> _l = [];

  @override
  void initState() {
    super.initState();
    cambiosDatos.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    cambiosDatos.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final d = await repos.productos.departamentos();
    final v = await repos.productos.valorInventario(departamentoId: _dep);
    final l = (await repos.productos.buscar('', departamentoId: _dep, limite: 10000)).where((p) => p.usaInventario).toList();
    if (mounted) {
      setState(() {
        _deps = d;
        _valor = v;
        _l = l;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('Reporte de inventario', style: ExTexto.titulo(22)),
        const SizedBox(width: 16),
        DropdownButton<String?>(
          value: _dep,
          items: [
            const DropdownMenuItem(value: null, child: Text('Todos los departamentos')),
            for (final d in _deps) DropdownMenuItem(value: d.id, child: Text(d.nombre)),
          ],
          onChanged: (v) {
            setState(() => _dep = v);
            _cargar();
          },
        ),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => guardarCsv(context, 'inventario', [
            ['codigo', 'descripcion', 'departamento', 'existencia', 'costo', 'precio', 'valor_costo', 'valor_venta'],
            for (final p in _l)
              [
                p.codigo, p.descripcion, p.departamentoNombre ?? '', formatoCantidad(p.existencia),
                (p.costoCentavos / 100).toStringAsFixed(2), (p.precioCentavos / 100).toStringAsFixed(2),
                (calcularImporte(p.existencia, p.costoCentavos) / 100).toStringAsFixed(2),
                (calcularImporte(p.existencia, p.precioCentavos) / 100).toStringAsFixed(2),
              ],
          ]),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Exportar'),
        ),
      ]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: ExKpi(nombre: 'Inversión (a costo)', valor: formatoPesos(_valor.$2), destacado: true)),
        const SizedBox(width: 12),
        Expanded(child: ExKpi(nombre: 'Valor a precio de venta', valor: formatoPesos(_valor.$3))),
        const SizedBox(width: 12),
        Expanded(child: ExKpi(nombre: 'Ganancia potencial', valor: formatoPesos(_valor.$3 - _valor.$2))),
        const SizedBox(width: 12),
        Expanded(child: ExKpi(nombre: 'Artículos en existencia', valor: formatoCantidad(_valor.$1))),
      ]),
      const SizedBox(height: 14),
      const EncabezadoTabla([('Descripción', 8, false), ('Hay', 2, true), ('Costo', 3, true), ('Valor a costo', 3, true), ('Valor a venta', 3, true)]),
      Expanded(
        child: Container(
          color: ExColor.blanco,
          child: ListView.builder(
            itemCount: _l.length,
            itemExtent: 40,
            itemBuilder: (_, i) {
              final p = _l[i];
              return FilaTabla([
                (celda(p.descripcion), 8, false),
                (celda(formatoCantidad(p.existencia), mono: true, color: p.bajoMinimo ? ExColor.rojo : null), 2, true),
                (celda(formatoPesos(p.costoCentavos), mono: true), 3, true),
                (celda(formatoPesos(calcularImporte(p.existencia, p.costoCentavos)), mono: true), 3, true),
                (celda(formatoPesos(calcularImporte(p.existencia, p.precioCentavos)), mono: true), 3, true),
              ], par: i.isOdd);
            },
          ),
        ),
      ),
    ]);
  }
}

class _Kardex extends StatefulWidget {
  const _Kardex();

  @override
  State<_Kardex> createState() => _KardexState();
}

class _KardexState extends State<_Kardex> {
  DateTime _desde = DateTime.now().subtract(const Duration(days: 7));
  DateTime _hasta = DateTime.now();
  String? _tipo;
  Producto? _producto;
  List<MovimientoInventario> _l = [];

  @override
  void initState() {
    super.initState();
    cambiosDatos.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    cambiosDatos.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final l = await repos.productos.movimientos(
      productoId: _producto?.id,
      desde: DateTime(_desde.year, _desde.month, _desde.day),
      hasta: DateTime(_hasta.year, _hasta.month, _hasta.day).add(const Duration(days: 1)),
      tipo: _tipo,
      limite: 5000,
    );
    if (mounted) setState(() => _l = l);
  }

  Future<void> _fecha(bool desde) async {
    final d = await showDatePicker(
        context: context, initialDate: desde ? _desde : _hasta, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (d == null) return;
    setState(() => desde ? _desde = d : _hasta = d);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Movimientos de inventario', style: ExTexto.titulo(22)),
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        OutlinedButton(onPressed: () => _fecha(true), child: Text('Desde ${formatoFecha(_desde)}')),
        OutlinedButton(onPressed: () => _fecha(false), child: Text('Hasta ${formatoFecha(_hasta)}')),
        DropdownButton<String?>(
          value: _tipo,
          items: const [
            DropdownMenuItem(value: null, child: Text('Todos los tipos')),
            DropdownMenuItem(value: 'Venta', child: Text('Ventas')),
            DropdownMenuItem(value: 'Entrada', child: Text('Entradas')),
            DropdownMenuItem(value: 'Ajuste', child: Text('Ajustes')),
            DropdownMenuItem(value: 'Salida', child: Text('Salidas')),
            DropdownMenuItem(value: 'Devolución', child: Text('Devoluciones')),
            DropdownMenuItem(value: 'Cancelación', child: Text('Cancelaciones')),
            DropdownMenuItem(value: 'Inicial', child: Text('Existencia inicial')),
          ],
          onChanged: (v) {
            setState(() => _tipo = v);
            _cargar();
          },
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final p = await buscarProducto(context);
            setState(() => _producto = p);
            _cargar();
          },
          icon: const Icon(Icons.search, size: 18),
          label: Text(_producto?.descripcion ?? 'Todos los productos'),
        ),
        if (_producto != null)
          TextButton(
              onPressed: () {
                setState(() => _producto = null);
                _cargar();
              },
              child: const Text('Quitar filtro')),
        OutlinedButton.icon(
          onPressed: () => guardarCsv(context, 'movimientos-inventario', [
            ['fecha', 'producto', 'tipo', 'habia', 'cantidad', 'hay', 'descripcion', 'cajero'],
            for (final m in _l)
              [formatoFechaHora(m.fecha), m.producto, m.tipo, formatoCantidad(m.habia), formatoCantidad(m.cantidad),
               formatoCantidad(m.hay), m.descripcion, m.cajero ?? ''],
          ]),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Exportar'),
        ),
      ]),
      const SizedBox(height: 12),
      const EncabezadoTabla([
        ('Fecha', 3, false), ('Producto', 6, false), ('Tipo', 2, false), ('Había', 2, true),
        ('Movimiento', 2, true), ('Hay', 2, true), ('Detalle', 4, false), ('Cajero', 2, false),
      ]),
      Expanded(
        child: Container(
          color: ExColor.blanco,
          child: _l.isEmpty
              ? const ExVacio('Sin movimientos en esas fechas')
              : ListView.builder(
                  itemCount: _l.length,
                  itemExtent: 40,
                  itemBuilder: (_, i) {
                    final m = _l[i];
                    return FilaTabla([
                      (celda(formatoFechaHora(m.fecha), mono: true), 3, false),
                      (celda(m.producto), 6, false),
                      (celda(m.tipo), 2, false),
                      (celda(formatoCantidad(m.habia), mono: true), 2, true),
                      (
                        celda('${m.cantidad > 0 ? '+' : ''}${formatoCantidad(m.cantidad)}',
                            mono: true, negrita: true, color: m.cantidad < 0 ? ExColor.rojo : ExColor.verde),
                        2,
                        true
                      ),
                      (celda(formatoCantidad(m.hay), mono: true), 2, true),
                      (celda(m.descripcion, color: ExColor.texto2), 4, false),
                      (celda(m.cajero ?? '', color: ExColor.texto2), 2, false),
                    ], par: i.isOdd);
                  },
                ),
        ),
      ),
    ]);
  }
}
