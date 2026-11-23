import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/bascula.dart';
import '../../core/formato.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_widgets.dart';
import '../sesion.dart';
import '../zoom.dart';
import '../tema/tema.dart';

/// Granel: cantidad (0.250 = 250 g) o importe ($20 de jamón).
Future<double?> pedirGranel(BuildContext context, Producto p) {
  return showDialog<double>(context: context, builder: (_) => _Granel(p));
}

class _Granel extends StatefulWidget {
  const _Granel(this.p);
  final Producto p;

  @override
  State<_Granel> createState() => _GranelState();
}

class _GranelState extends State<_Granel> {
  final _cant = TextEditingController();
  final _imp = TextEditingController();
  final _bascula = configBascula(repos.ajustes);
  final _lector = LectorBascula.instancia;

  /// Mientras el cajero no escriba, la cantidad sigue a la báscula.
  bool _siguePeso = true;

  @override
  void initState() {
    super.initState();
    final b = _bascula;
    if (b != null) {
      _lector.peso.addListener(_nuevoPeso);
      _lector.usar(b);
      _nuevoPeso();
    }
  }

  void _nuevoPeso() {
    final v = _lector.peso.value;
    if (!_siguePeso || v == null || !mounted) return;
    _cant.text = v <= 0 ? '' : formatoCantidad(v);
    _cant.selection = TextSelection.collapsed(offset: _cant.text.length);
    _desdeCantidad(_cant.text);
  }

  @override
  void dispose() {
    if (_bascula != null) {
      _lector.peso.removeListener(_nuevoPeso);
      _lector.soltar();
    }
    _cant.dispose();
    _imp.dispose();
    super.dispose();
  }

  void _desdeCantidad(String v) {
    final c = leerCantidad(v);
    _imp.text = c == null ? '' : (calcularImporte(c, widget.p.precioCentavos) / 100).toStringAsFixed(2);
  }

  void _desdeImporte(String v) {
    final i = leerPesos(v);
    if (i == null || widget.p.precioCentavos <= 0) {
      _cant.text = '';
      return;
    }
    _cant.text = formatoCantidad((i / widget.p.precioCentavos * 1000).round() / 1000);
  }

  void _aceptar() => Navigator.pop(context, leerCantidad(_cant.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.p.descripcion),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Precio: ${formatoPesos(widget.p.precioCentavos)} por kilo / litro',
              style: const TextStyle(color: ExColor.texto2)),
          const SizedBox(height: 16),
          if (_bascula != null) ...[
            _PesoEnVivo(lector: _lector, siguiendo: _siguePeso, onVolver: () {
              setState(() => _siguePeso = true);
              _nuevoPeso();
            }),
            const SizedBox(height: 14),
          ],
          CampoNumero(
              controller: _cant,
              etiqueta: 'Cantidad (kg)',
              ayuda: _bascula != null ? 'Se llena con la báscula. Enter para agregar.' : 'Ej. 0.250 = 250 gramos',
              autofocus: true,
              onChanged: (v) {
                if (_siguePeso) setState(() => _siguePeso = false);
                _desdeCantidad(v);
              },
              onSubmitted: (_) => _aceptar()),
          const SizedBox(height: 14),
          CampoNumero(
              controller: _imp,
              etiqueta: 'O importe (\$)',
              ayuda: 'Ej. 20 = veinte pesos',
              onChanged: (v) {
                if (_siguePeso) setState(() => _siguePeso = false);
                _desdeImporte(v);
              },
              onSubmitted: (_) => _aceptar()),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Agregar')),
      ],
    );
  }
}

/// Peso que marca la báscula en este momento.
class _PesoEnVivo extends StatelessWidget {
  const _PesoEnVivo({required this.lector, required this.siguiendo, required this.onVolver});
  final LectorBascula lector;
  final bool siguiendo;
  final VoidCallback onVolver;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: ExColor.concreto,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ExColor.borde, width: 1.2),
      ),
      child: Row(children: [
        const Icon(Icons.scale_outlined, color: ExColor.indigo, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: ValueListenableBuilder2(
            a: lector.peso,
            b: lector.estado,
            builder: (peso, estado) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(peso == null ? '— kg' : '${peso.toStringAsFixed(3)} kg', style: ExTexto.mono(30, color: ExColor.tinta)),
              Text(estado.isNotEmpty ? estado : (siguiendo ? 'Báscula' : 'Cantidad escrita a mano'),
                  style: TextStyle(color: estado.isNotEmpty ? ExColor.rojo : ExColor.texto2, fontSize: 13)),
            ]),
          ),
        ),
        if (!siguiendo) TextButton(onPressed: onVolver, child: const Text('Usar báscula')),
      ]),
    );
  }
}

class ValueListenableBuilder2<A, B> extends StatelessWidget {
  const ValueListenableBuilder2({super.key, required this.a, required this.b, required this.builder});
  final ValueListenable<A> a;
  final ValueListenable<B> b;
  final Widget Function(A a, B b) builder;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<A>(
        valueListenable: a,
        builder: (_, va, __) => ValueListenableBuilder<B>(valueListenable: b, builder: (_, vb, __) => builder(va, vb)),
      );
}

/// Ctrl+P: artículo que no está en el catálogo.
Future<Renglon?> pedirArticuloComun(BuildContext context) {
  return showDialog<Renglon>(context: context, builder: (_) => const _Comun());
}

class _Comun extends StatefulWidget {
  const _Comun();

  @override
  State<_Comun> createState() => _ComunState();
}

class _ComunState extends State<_Comun> {
  final _desc = TextEditingController();
  final _precio = TextEditingController();
  final _cant = TextEditingController(text: '1');

  @override
  void dispose() {
    _desc.dispose();
    _precio.dispose();
    _cant.dispose();
    super.dispose();
  }

  void _aceptar() {
    final precio = leerPesos(_precio.text);
    final cant = leerCantidad(_cant.text);
    if (_desc.text.trim().isEmpty || precio == null || precio <= 0 || cant == null || cant <= 0) {
      aviso(context, 'Escribe la descripción, el precio y la cantidad.');
      return;
    }
    Navigator.pop(context, Renglon(descripcion: _desc.text.trim(), cantidad: cant, precioNormalCentavos: precio));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Artículo común'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _desc,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descripción')),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: CampoNumero(controller: _cant, etiqueta: 'Cantidad', onSubmitted: (_) => _aceptar())),
            const SizedBox(width: 12),
            Expanded(child: CampoNumero(controller: _precio, etiqueta: 'Precio (\$)', onSubmitted: (_) => _aceptar())),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Agregar')),
      ],
    );
  }
}

class CambioPrecio {
  CambioPrecio({this.porcentaje = 0, this.nuevoPrecio, this.todaLaVenta = false});
  final double porcentaje;
  final int? nuevoPrecio;
  final bool todaLaVenta;
}

/// Ctrl+D: descuento al artículo seleccionado (por % o precio nuevo) o a
/// toda la venta.
Future<CambioPrecio?> pedirDescuento(BuildContext context, Renglon? r, int totalCentavos) {
  return showDialog<CambioPrecio>(context: context, builder: (_) => _Descuento(r, totalCentavos));
}

class _Descuento extends StatefulWidget {
  const _Descuento(this.r, this.total);
  final Renglon? r;
  final int total;

  @override
  State<_Descuento> createState() => _DescuentoState();
}

class _DescuentoState extends State<_Descuento> {
  late bool _toda = widget.r == null;
  bool _porPrecio = false;
  final _valor = TextEditingController();

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  void _aceptar() {
    if (_porPrecio && !_toda) {
      final p = leerPesos(_valor.text);
      if (p == null || p < 0) return aviso(context, 'Escribe el precio nuevo.');
      Navigator.pop(context, CambioPrecio(nuevoPrecio: p));
    } else {
      final pc = leerCantidad(_valor.text);
      if (pc == null || pc <= 0 || pc > 100) return aviso(context, 'Escribe un porcentaje entre 1 y 100.');
      Navigator.pop(context, CambioPrecio(porcentaje: pc, todaLaVenta: _toda));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    return AlertDialog(
      title: const Text('Descuento'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(r == null ? 'Artículo' : 'Solo "${r.descripcion}"'), enabled: r != null),
              const ButtonSegment(value: true, label: Text('Toda la venta')),
            ],
            selected: {_toda},
            onSelectionChanged: (s) => setState(() => _toda = s.first),
          ),
          const SizedBox(height: 14),
          if (!_toda)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Porcentaje')),
                ButtonSegment(value: true, label: Text('Precio nuevo')),
              ],
              selected: {_porPrecio},
              onSelectionChanged: (s) => setState(() => _porPrecio = s.first),
            ),
          const SizedBox(height: 14),
          CampoNumero(
            controller: _valor,
            autofocus: true,
            etiqueta: _porPrecio && !_toda ? 'Precio nuevo por unidad (\$)' : 'Descuento (%)',
            ayuda: _toda
                ? 'Total actual: ${formatoPesos(widget.total)}'
                : (r == null ? null : 'Precio actual: ${formatoPesos(r.precioUnitarioCentavos)}'),
            onSubmitted: (_) => _aceptar(),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Aplicar')),
      ],
    );
  }
}

/// F9: verificador de precios.
Future<void> verificadorDePrecios(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _Verificador());
}

class _Verificador extends StatefulWidget {
  const _Verificador();

  @override
  State<_Verificador> createState() => _VerificadorState();
}

class _VerificadorState extends State<_Verificador> {
  final _c = TextEditingController();
  final _foco = FocusNode();
  Producto? _p;
  Promocion? _promo;
  bool _noEncontrado = false;

  @override
  void dispose() {
    _c.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<void> _ver(String codigo) async {
    var p = await repos.productos.porCodigo(codigo);
    if (p == null && codigo.trim().isNotEmpty) {
      final l = await repos.productos.buscar(codigo, limite: 1);
      p = l.firstOrNull;
    }
    final promo = p == null ? null : await repos.productos.promocionDe(p.id);
    if (!mounted) return;
    setState(() {
      _p = p;
      _promo = promo;
      _noEncontrado = p == null;
    });
    _c.clear();
    _foco.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Dialog(
      child: SizedBox(
        width: 620,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Verificador de precios', style: ExTexto.titulo(22)),
            const SizedBox(height: 16),
            ExBuscador(controller: _c, focusNode: _foco, autofocus: true, hint: 'Escanea el producto', onSubmitted: _ver),
            const SizedBox(height: 24),
            if (_noEncontrado) const Text('Producto no encontrado', style: TextStyle(color: ExColor.rojo, fontSize: 18)),
            if (p != null) ...[
              Text(p.descripcion, style: ExTexto.titulo(26)),
              const SizedBox(height: 8),
              Text(formatoPesos(p.precioCentavos), style: ExTexto.titulo(64, color: ExColor.indigo)),
              if (p.esGranel) const Text('por kilo / litro', style: TextStyle(color: ExColor.texto2)),
              if (p.tieneMayoreo)
                Text('Mayoreo: ${formatoPesos(p.mayoreoCentavos)}'
                    '${p.mayoreoDesde > 0 ? ' desde ${formatoCantidad(p.mayoreoDesde)} piezas' : ''}',
                    style: const TextStyle(fontSize: 16)),
              if (_promo != null)
                Text('Promoción: ${_promo!.nombre}', style: const TextStyle(fontSize: 16, color: ExColor.verde)),
              if (p.usaInventario)
                Text('Existencia: ${formatoCantidad(p.existencia)}', style: const TextStyle(color: ExColor.texto2)),
            ],
            const SizedBox(height: 16),
            Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar (Esc)'))),
          ]),
        ),
      ),
    );
  }
}

/// F7 / F8: entrada o salida de efectivo. Regresa (monto, concepto).
Future<(int, String)?> pedirMovimientoCaja(BuildContext context, String tipo) {
  return showDialog<(int, String)>(context: context, builder: (_) => _MovCaja(tipo));
}

class _MovCaja extends StatefulWidget {
  const _MovCaja(this.tipo);
  final String tipo;

  @override
  State<_MovCaja> createState() => _MovCajaState();
}

class _MovCajaState extends State<_MovCaja> {
  final _monto = TextEditingController();
  final _concepto = TextEditingController();

  @override
  void dispose() {
    _monto.dispose();
    _concepto.dispose();
    super.dispose();
  }

  void _aceptar() {
    final m = leerPesos(_monto.text);
    if (m == null || m <= 0) return aviso(context, 'Escribe la cantidad.');
    Navigator.pop(context, (m, _concepto.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final entrada = widget.tipo == 'entrada';
    return AlertDialog(
      title: Text(entrada ? 'Entrada de efectivo' : 'Salida de efectivo'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CampoNumero(controller: _monto, etiqueta: 'Cantidad (\$)', autofocus: true),
          const SizedBox(height: 14),
          TextField(
            controller: _concepto,
            decoration: InputDecoration(
                labelText: entrada ? 'Comentarios' : 'Razón o proveedor', hintText: entrada ? 'Ej. cambio, morralla' : 'Ej. pago al proveedor de refrescos'),
            onSubmitted: (_) => _aceptar(),
          ),
          const SizedBox(height: 16),
          Text(entrada ? 'Entradas de este turno' : 'Salidas de este turno', style: const TextStyle(fontWeight: FontWeight.w700)),
          FutureBuilder<List<MovimientoCaja>>(
            future: sesion.turno == null ? Future.value(<MovimientoCaja>[]) : repos.caja.movimientosCaja([sesion.turno!.id]),
            builder: (_, s) {
              final l = (s.data ?? []).where((m) => m.tipo == widget.tipo && !m.cancelado).toList();
              if (l.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('- Ninguna -', style: TextStyle(color: ExColor.texto2)));
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView(shrinkWrap: true, children: [
                  for (final m in l)
                    ListTile(
                      dense: true,
                      title: Text(m.concepto.isEmpty ? '(sin concepto)' : m.concepto),
                      subtitle: Text(formatoFechaHora(m.fecha)),
                      trailing: Text(formatoPesos(m.montoCentavos), style: ExTexto.mono(14)),
                    ),
                ]),
              );
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Elige un cliente. Un cliente con id vacío significa "quitar cliente".
Future<Cliente?> elegirCliente(BuildContext context) {
  return showDialog<Cliente>(context: context, builder: (_) => const _ElegirCliente());
}

class _ElegirCliente extends StatefulWidget {
  const _ElegirCliente();

  @override
  State<_ElegirCliente> createState() => _ElegirClienteState();
}

class _ElegirClienteState extends State<_ElegirCliente> {
  final _c = TextEditingController();
  List<Cliente> _lista = [];

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final l = await repos.clientes.buscar(_c.text);
    if (mounted) setState(() => _lista = l);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: anchoDialogo(context, 640),
        height: altoDialogo(context, 560),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: ExBuscador(
              controller: _c,
              autofocus: true,
              hint: 'Buscar cliente por nombre, teléfono o número',
              onChanged: (_) => _buscar(),
              onSubmitted: (_) {
                if (_lista.isNotEmpty) Navigator.pop(context, _lista.first);
              },
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _lista.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (_, i) {
                final c = _lista[i];
                return ListTile(
                  leading: ExAvatar(c.nombre),
                  title: Text(c.nombre),
                  subtitle: Text([
                    'No. ${c.numero}',
                    if (c.telefono.isNotEmpty) c.telefono,
                    if (c.tieneLimite) 'Límite ${formatoPesos(c.limiteCentavos)}',
                  ].join(' · ')),
                  trailing: Text(formatoPesos(c.saldoCentavos),
                      style: ExTexto.mono(14, color: c.saldoCentavos > 0 ? ExColor.rojo : ExColor.texto2)),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(context, Cliente(id: '', nombre: '')),
                child: const Text('Quitar cliente (público en general)'),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
            ]),
          ),
        ]),
      ),
    );
  }
}
