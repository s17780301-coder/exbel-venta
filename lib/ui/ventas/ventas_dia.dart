import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/tickets.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_widgets.dart';
import '../comun/impresion.dart';
import '../sesion.dart';
import '../tema/tema.dart';

/// Ventas del día y devoluciones (como en Eleventa).
Future<void> mostrarVentasDelDia(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _VentasDia());
}

class _VentasDia extends StatefulWidget {
  const _VentasDia();

  @override
  State<_VentasDia> createState() => _VentasDiaState();
}

class _VentasDiaState extends State<_VentasDia> {
  DateTime _dia = DateTime.now();
  String? _cajeroId;
  List<Cajero> _cajeros = [];
  List<Venta> _ventas = [];
  Venta? _sel;
  List<LineaVendida> _lineas = [];
  final _folio = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _folio.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final inicio = DateTime(_dia.year, _dia.month, _dia.day);
    final v = await repos.ventas.listar(
        desde: inicio, hasta: inicio.add(const Duration(days: 1)), cajeroId: _cajeroId);
    final c = await repos.cajeros.listar(soloActivos: false);
    if (!mounted) return;
    setState(() {
      _ventas = v;
      _cajeros = c;
    });
    if (_sel != null) {
      final nueva = v.where((x) => x.id == _sel!.id).firstOrNull ?? await repos.ventas.porId(_sel!.id);
      await _elegir(nueva);
    }
  }

  Future<void> _elegir(Venta? v) async {
    final l = v == null ? <LineaVendida>[] : await repos.ventas.detalle(v.id);
    if (mounted) {
      setState(() {
        _sel = v;
        _lineas = l;
      });
    }
  }

  Future<void> _buscarFolio(String t) async {
    final f = int.tryParse(t.trim());
    if (f == null) return;
    final v = await repos.ventas.porFolio(f);
    if (!mounted) return;
    if (v == null) return aviso(context, 'No existe el folio $f.');
    setState(() => _dia = v.fecha);
    await _cargar();
    await _elegir(v);
  }

  Future<void> _reimprimir() async {
    final v = _sel;
    if (v == null) return;
    final pdf = await ticketVenta(v, _lineas, copia: true);
    if (mounted) await vistaPrevia(context, pdf, titulo: 'Copia folio ${v.folio}');
  }

  Future<void> _devolver({bool todo = false}) async {
    final v = _sel;
    final turno = sesion.turno;
    final cajero = sesion.cajero;
    if (v == null || turno == null || cajero == null) return;
    if (!await autorizar(context, todo ? Permiso.cancelar : Permiso.devoluciones) || !mounted) return;
    Map<String, double>? cantidades;
    if (!todo) {
      cantidades = await _pedirCantidades(context, _lineas);
      if (cantidades == null || cantidades.isEmpty) return;
    } else if (!await confirmar(context, 'Cancelar venta',
        'Se regresa toda la mercancía del folio ${v.folio} al inventario y el dinero al cliente.',
        si: 'Cancelar venta', no: 'No', peligro: true)) {
      return;
    }
    if (!mounted) return;
    final motivo = await pedirTexto(context, todo ? 'Motivo de la cancelación' : 'Motivo de la devolución',
        etiqueta: 'Motivo (opcional)');
    if (motivo == null || !mounted) return;
    var efectivo = 0;
    final ok = await intentar(context, () async {
      efectivo = todo
          ? await repos.ventas.cancelar(v.id, turnoId: turno.id, cajeroId: cajero.id, motivo: motivo.isEmpty ? 'Cancelación' : motivo)
          : await repos.ventas.devolver(
              ventaId: v.id, cantidades: cantidades!, turnoId: turno.id, cajeroId: cajero.id, motivo: motivo);
    });
    if (!ok || !mounted) return;
    avisarCambio();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(todo ? 'Venta cancelada' : 'Devolución registrada'),
        content: Text(efectivo > 0
            ? 'Entrega al cliente ${formatoPesos(efectivo)} en efectivo.'
            : 'Se descontó del crédito del cliente. No hay que entregar efectivo.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Listo'))],
      ),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final total = _ventas.where((v) => !v.cancelada).fold<int>(0, (s, v) => s + v.totalCentavos);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 1180,
        height: 720,
        child: Column(children: [
          Container(
            color: ExColor.tinta,
            padding: const EdgeInsets.fromLTRB(24, 14, 12, 14),
            child: Row(children: [
              Text('Ventas del día y devoluciones', style: ExTexto.titulo(20, color: ExColor.concreto)),
              const Spacer(),
              IconButton(
                  onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: ExColor.concreto)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(formatoFecha(_dia)),
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: _dia, firstDate: DateTime(2020), lastDate: DateTime.now());
                  if (d != null) {
                    setState(() => _dia = d);
                    _cargar();
                  }
                },
              ),
              const SizedBox(width: 12),
              DropdownButton<String?>(
                value: _cajeroId,
                hint: const Text('Todos los cajeros'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Todos los cajeros')),
                  for (final c in _cajeros) DropdownMenuItem(value: c.id, child: Text(c.nombre)),
                ],
                onChanged: (v) {
                  setState(() => _cajeroId = v);
                  _cargar();
                },
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 220,
                child: ExBuscador(controller: _folio, hint: 'Buscar folio', onSubmitted: _buscarFolio),
              ),
              const Spacer(),
              Text('${_ventas.length} ventas · ${formatoPesos(total)}', style: ExTexto.titulo(16)),
            ]),
          ),
          Expanded(
            child: Row(children: [
              Expanded(
                flex: 5,
                child: Column(children: [
                  const EncabezadoTabla([('Folio', 2, false), ('Hora', 2, false), ('Cajero', 3, false), ('Pago', 4, false), ('Total', 3, true)]),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _ventas.length,
                      itemExtent: 42,
                      itemBuilder: (_, i) {
                        final v = _ventas[i];
                        final color = v.cancelada ? ExColor.texto2 : (v.aCredito ? ExColor.verde : null);
                        return FilaTabla(
                          [
                            (celda('${v.folio}', mono: true, color: color), 2, false),
                            (celda(formatoFechaHora(v.fecha).substring(11), mono: true, color: color), 2, false),
                            (celda(v.cajeroNombre ?? '', color: color), 3, false),
                            (
                              celda(
                                  v.cancelada
                                      ? 'CANCELADA'
                                      : v.estado == 'devolucion'
                                          ? '${v.pago.descripcion} · con devolución'
                                          : v.pago.descripcion,
                                  color: color),
                              4,
                              false
                            ),
                            (celda(formatoPesos(v.totalCentavos), mono: true, negrita: true, color: color), 3, true),
                          ],
                          par: i.isOdd,
                          seleccionada: _sel?.id == v.id,
                          onTap: () => _elegir(v),
                        );
                      },
                    ),
                  ),
                ]),
              ),
              const VerticalDivider(width: 1),
              Expanded(flex: 4, child: _detalle()),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _detalle() {
    final v = _sel;
    if (v == null) return const ExVacio('Elige una venta para ver su detalle');
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Folio ${v.folio}', style: ExTexto.titulo(24)),
        Text('${formatoFechaHora(v.fecha)} · ${v.cajeroNombre ?? ''}${v.clienteNombre == null ? '' : ' · ${v.clienteNombre}'}',
            style: const TextStyle(color: ExColor.texto2)),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(children: [
            for (final l in _lineas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.descripcion),
                      Text('${formatoCantidad(l.cantidad)} × ${formatoPesos(l.precioCentavos)}'
                          '${l.devuelto > 0 ? ' · devuelto ${formatoCantidad(l.devuelto)}' : ''}',
                          style: TextStyle(color: l.devuelto > 0 ? ExColor.rojo : ExColor.texto2, fontSize: 12)),
                    ]),
                  ),
                  Text(formatoPesos(l.importeCentavos), style: ExTexto.mono(14)),
                ]),
              ),
          ]),
        ),
        const Divider(),
        Row(children: [
          Text(v.pago.descripcion),
          const Spacer(),
          Text(formatoPesos(v.totalCentavos), style: ExTexto.titulo(26)),
        ]),
        if (v.notas.isNotEmpty) Text(v.notas, style: const TextStyle(color: ExColor.texto2)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _reimprimir, icon: const Icon(Icons.print_outlined, size: 18), label: const Text('Imprimir copia')),
          if (!v.cancelada) ...[
            OutlinedButton.icon(
                onPressed: () => _devolver(), icon: const Icon(Icons.undo, size: 18), label: const Text('Devolver artículos')),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ExColor.rojo),
              onPressed: () => _devolver(todo: true),
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Cancelar venta'),
            ),
          ],
        ]),
      ]),
    );
  }
}

Future<Map<String, double>?> _pedirCantidades(BuildContext context, List<LineaVendida> lineas) {
  return showDialog<Map<String, double>>(context: context, builder: (_) => _Devolucion(lineas));
}

class _Devolucion extends StatefulWidget {
  const _Devolucion(this.lineas);
  final List<LineaVendida> lineas;

  @override
  State<_Devolucion> createState() => _DevolucionState();
}

class _DevolucionState extends State<_Devolucion> {
  late final _ctrls = {for (final l in widget.lineas) l.id: TextEditingController()};

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devolvibles = widget.lineas.where((l) => l.devolvible > 0).toList();
    return AlertDialog(
      title: const Text('¿Qué se devuelve?'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final l in devolvibles)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  Expanded(child: Text('${l.descripcion}\nCompró ${formatoCantidad(l.cantidad)}'
                      '${l.devuelto > 0 ? ', ya devolvió ${formatoCantidad(l.devuelto)}' : ''}')),
                  TextButton(
                    onPressed: () => setState(() => _ctrls[l.id]!.text = formatoCantidad(l.devolvible)),
                    child: const Text('Todo'),
                  ),
                  SizedBox(width: 110, child: CampoNumero(controller: _ctrls[l.id]!, etiqueta: 'Devolver')),
                ]),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final r = <String, double>{};
            for (final l in devolvibles) {
              final c = leerCantidad(_ctrls[l.id]!.text) ?? 0;
              if (c > 0) r[l.id] = c;
            }
            Navigator.pop(context, r);
          },
          child: const Text('Devolver'),
        ),
      ],
    );
  }
}
