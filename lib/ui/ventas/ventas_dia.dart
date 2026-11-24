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
import '../zoom.dart';

/// Historial de ventas: ventas del día o de otras fechas
/// (hasta un mes atrás con un clic), reimprimir, devolver y cancelar.
/// Con [clienteId] muestra todas las compras de ese cliente.
Future<void> mostrarVentasDelDia(BuildContext context, {Venta? venta, String? clienteId, String? clienteNombre}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _Historial(venta: venta, clienteId: clienteId, clienteNombre: clienteNombre),
  );
}

enum _Rango { dia, ayer, semana, mes, todo }

const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

String _hora(DateTime f) {
  final h = f.hour % 12 == 0 ? 12 : f.hour % 12;
  return '$h:${f.minute.toString().padLeft(2, '0')} ${f.hour < 12 ? 'am' : 'pm'}';
}

String fechaLarga(DateTime f) => '${f.day} de ${_meses[f.month - 1]} de ${f.year}, ${_hora(f)}';

class _Historial extends StatefulWidget {
  const _Historial({this.venta, this.clienteId, this.clienteNombre});
  final Venta? venta;
  final String? clienteId;
  final String? clienteNombre;

  @override
  State<_Historial> createState() => _HistorialState();
}

class _HistorialState extends State<_Historial> {
  late _Rango _rango = widget.clienteId != null ? _Rango.todo : _Rango.dia;
  late DateTime _dia = widget.venta?.fecha ?? DateTime.now();
  String? _cajeroId;
  bool _soloCredito = false;
  List<Cajero> _cajeros = [];
  List<Venta> _ventas = [];
  Venta? _sel;
  final _scroll = ScrollController();

  void _mover(int d) {
    if (_ventas.isEmpty) return;
    final actual = _sel == null ? -1 : _ventas.indexWhere((v) => v.id == _sel!.id);
    final i = actual < 0 ? (d > 0 ? 0 : _ventas.length - 1) : (actual + d).clamp(0, _ventas.length - 1);
    _elegir(_ventas[i]);
    seguirFila(_scroll, i, 40);
  }
  List<LineaVendida> _lineas = [];
  int _linea = -1;
  final _buscar = TextEditingController();

  @override
  void initState() {
    super.initState();
    _sel = widget.venta;
    _cargar();
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  (DateTime?, DateTime?) get _periodo {
    final h = DateTime.now();
    final hoy = DateTime(h.year, h.month, h.day);
    final manana = hoy.add(const Duration(days: 1));
    final dia = DateTime(_dia.year, _dia.month, _dia.day);
    return switch (_rango) {
      _Rango.dia => (dia, dia.add(const Duration(days: 1))),
      _Rango.ayer => (hoy.subtract(const Duration(days: 1)), hoy),
      _Rango.semana => (hoy.subtract(const Duration(days: 6)), manana),
      _Rango.mes => (hoy.subtract(const Duration(days: 30)), manana),
      _Rango.todo => (null, null),
    };
  }

  Future<void> _cargar() async {
    final (desde, hasta) = _periodo;
    final texto = _buscar.text.trim();
    // Un folio se busca en todas las fechas.
    final porFolio = int.tryParse(texto) != null;
    final v = await repos.ventas.listar(
      desde: porFolio ? null : desde,
      hasta: porFolio ? null : hasta,
      cajeroId: _cajeroId,
      clienteId: widget.clienteId,
      soloCredito: _soloCredito,
      texto: texto,
    );
    final c = await repos.cajeros.listar(soloActivos: false);
    if (!mounted) return;
    setState(() {
      _ventas = v;
      _cajeros = c;
    });
    final s = _sel;
    if (s != null) {
      await _elegir(v.where((x) => x.id == s.id).firstOrNull ?? await repos.ventas.porId(s.id));
    } else if (v.isNotEmpty) {
      await _elegir(v.first);
    }
  }

  Future<void> _elegir(Venta? v) async {
    final l = v == null ? <LineaVendida>[] : await repos.ventas.detalle(v.id);
    if (mounted) {
      setState(() {
        _sel = v;
        _lineas = l;
        _linea = l.isEmpty ? -1 : 0;
      });
    }
  }

  Future<void> _reimprimir() async {
    final v = _sel;
    if (v == null) return;
    final pdf = await ticketVenta(v, _lineas, copia: true);
    if (mounted) await vistaPrevia(context, pdf, titulo: 'Copia folio ${v.folio}');
  }

  /// Devuelve el artículo seleccionado, varios, o cancela toda la venta.
  Future<void> _devolver({bool todo = false, bool varios = false}) async {
    final v = _sel;
    final turno = sesion.turno;
    final cajero = sesion.cajero;
    if (v == null || turno == null || cajero == null) return;
    if (!await autorizar(context, todo ? Permiso.cancelar : Permiso.devoluciones) || !mounted) return;
    Map<String, double>? cantidades;
    if (todo) {
      if (!await confirmar(context, 'Cancelar venta',
          'Se regresa toda la mercancía del folio ${v.folio} al inventario y el dinero al cliente.',
          si: 'Cancelar venta', no: 'No', peligro: true)) {
        return;
      }
    } else if (varios) {
      cantidades = await _pedirCantidades(context, _lineas);
      if (cantidades == null || cantidades.isEmpty) return;
    } else {
      if (_linea < 0 || _linea >= _lineas.length) return aviso(context, 'Elige el artículo a devolver.');
      final l = _lineas[_linea];
      if (l.devolvible <= 0) return aviso(context, 'Ese artículo ya se devolvió completo.');
      final c = await pedirCantidad(context, 'Devolver "${l.descripcion}"',
          etiqueta: 'Cantidad a devolver', inicial: l.devolvible, ayuda: 'Compró ${formatoCantidad(l.cantidad)}');
      if (c == null || c <= 0) return;
      cantidades = {l.id: c};
    }
    if (!mounted) return;
    final motivo = await pedirTexto(context, todo ? 'Motivo de la cancelación' : 'Motivo de la devolución', etiqueta: 'Motivo (opcional)');
    if (motivo == null || !mounted) return;
    var efectivo = 0;
    final ok = await intentar(context, () async {
      efectivo = todo
          ? await repos.ventas.cancelar(v.id, turnoId: turno.id, cajeroId: cajero.id, motivo: motivo.isEmpty ? 'Cancelación' : motivo)
          : await repos.ventas.devolver(ventaId: v.id, cantidades: cantidades!, turnoId: turno.id, cajeroId: cajero.id, motivo: motivo);
    });
    if (!ok || !mounted) return;
    avisarCambio();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(todo ? 'Venta cancelada' : 'Devolución registrada'),
        content: Text(
            efectivo > 0
                ? 'Entrega al cliente ${formatoPesos(efectivo)} en efectivo.'
                : 'Se descontó del crédito del cliente. No hay que entregar efectivo.',
            style: const TextStyle(fontSize: 18)),
        actions: [FilledButton(autofocus: true, onPressed: () => Navigator.pop(c), child: const Text('Listo'))],
      ),
    );
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final total = _ventas.where((v) => !v.cancelada).fold<int>(0, (s, v) => s + v.totalCentavos);
    final variosDias = _rango != _Rango.dia || int.tryParse(_buscar.text.trim()) != null;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: anchoDialogo(context, 1200),
        height: altoDialogo(context, 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: ExColor.banda,
            padding: const EdgeInsets.fromLTRB(22, 8, 8, 8),
            child: Row(children: [
              Text(widget.clienteNombre == null ? 'HISTORIAL DE VENTAS' : 'COMPRAS DE ${widget.clienteNombre!.toUpperCase()}',
                  style: ExTexto.titulo(20, color: ExColor.bandaTexto)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: ExColor.bandaTexto)),
            ]),
          ),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(flex: 5, child: _lista(total, variosDias)),
              const VerticalDivider(width: 1),
              Expanded(flex: 5, child: _detalle()),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _lista(int total, bool variosDias) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Puedes buscar por folio o nombre del cliente:'),
        const SizedBox(height: 6),
        ExBuscador(controller: _buscar, autofocus: true, hint: 'Folio o cliente', onChanged: (_) => _cargar(), onFlecha: _mover),
        const SizedBox(height: 10),
        EncabezadoTabla([
          ('Folio', 2, false),
          ('Arts', 1, true),
          (variosDias ? 'Fecha' : 'Hora', variosDias ? 3 : 2, false),
          ('Total', 2, true),
        ], tamano: 14),
        Expanded(
          child: Container(
            color: ExColor.blanco,
            child: _ventas.isEmpty
                ? const ExVacio('Sin ventas')
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _ventas.length,
                    itemExtent: 40,
                    itemBuilder: (_, i) {
                      final v = _ventas[i];
                      final color = v.cancelada ? ExColor.texto2 : (v.aCredito ? ExColor.verde : null);
                      return FilaTabla(
                        [
                          (celda('${v.folio}${v.cancelada ? ' (cancelada)' : ''}', mono: true, color: color, tamano: 15), 2, false),
                          (celda(formatoCantidad(v.articulos), mono: true, color: color, tamano: 15), 1, true),
                          (
                            celda(variosDias ? '${formatoFecha(v.fecha)} ${_hora(v.fecha)}' : _hora(v.fecha),
                                mono: true, color: color, tamano: 15),
                            variosDias ? 3 : 2,
                            false
                          ),
                          (celda(formatoPesos(v.totalCentavos), mono: true, negrita: true, color: color, tamano: 15), 2, true),
                        ],
                        par: i.isOdd,
                        seleccionada: _sel?.id == v.id,
                        onTap: () => _elegir(v),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text('${_ventas.length} ventas · ${formatoPesos(total)}   (verde = a crédito)', style: const TextStyle(color: ExColor.texto2)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Del día: '),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(_rango == _Rango.dia ? formatoFecha(_dia) : 'Elegir'),
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _dia, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) {
                setState(() {
                  _dia = d;
                  _rango = _Rango.dia;
                });
                _cargar();
              }
            },
          ),
          for (final r in [
            (_Rango.dia, 'Hoy'),
            (_Rango.ayer, 'Ayer'),
            (_Rango.semana, '7 días'),
            (_Rango.mes, '30 días'),
            if (widget.clienteId != null) (_Rango.todo, 'Todas'),
          ])
            ChoiceChip(
              label: Text(r.$2),
              selected: r.$1 == _Rango.dia ? _rango == _Rango.dia && DateUtils.isSameDay(_dia, DateTime.now()) : _rango == r.$1,
              onSelected: (_) {
                setState(() {
                  _rango = r.$1;
                  if (r.$1 == _Rango.dia) _dia = DateTime.now();
                });
                _cargar();
              },
            ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          const Text('Cajero: '),
          Expanded(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: _cajeroId,
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos los cajeros')),
                for (final c in _cajeros) DropdownMenuItem(value: c.id, child: Text(c.nombre)),
              ],
              onChanged: (v) {
                setState(() => _cajeroId = v);
                _cargar();
              },
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Ventas a crédito'),
            selected: _soloCredito,
            onSelected: (v) {
              setState(() => _soloCredito = v);
              _cargar();
            },
          ),
        ]),
      ]),
    );
  }

  Widget _detalle() {
    final v = _sel;
    if (v == null) return const ExVacio('Elige una venta para ver su detalle');
    Widget dato(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 80, child: Text(a, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            Expanded(child: Text(b)),
          ]),
        );
    final pago = v.pago;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Text('Ticket folio ${v.folio}', style: ExTexto.titulo(22, color: ExColor.indigo))),
        const SizedBox(height: 6),
        dato('Folio:', '${v.folio}${v.cancelada ? '  ·  CANCELADA' : v.estado == 'devolucion' ? '  ·  con devolución' : ''}'),
        dato('Cajero:', v.cajeroNombre ?? ''),
        dato('Cliente:', v.clienteNombre ?? 'Público en general'),
        dato('Fecha:', fechaLarga(v.fecha)),
        const SizedBox(height: 8),
        const EncabezadoTabla([('Cant.', 2, true), ('Descripción', 6, false), ('Importe', 3, true)], tamano: 14),
        Expanded(
          child: Container(
            color: ExColor.blanco,
            child: ListView.builder(
              itemCount: _lineas.length,
              itemBuilder: (_, i) {
                final l = _lineas[i];
                return FilaTabla(
                  [
                    (celda(formatoCantidad(l.cantidad), mono: true, tamano: 15), 2, true),
                    (
                      celda(l.devuelto > 0 ? '${l.descripcion}  (devuelto ${formatoCantidad(l.devuelto)})' : l.descripcion,
                          tamano: 15, color: l.devuelto > 0 ? ExColor.rojo : null),
                      6,
                      false
                    ),
                    (celda(formatoPesos(l.importeCentavos), mono: true, tamano: 15), 3, true),
                  ],
                  par: i.isOdd,
                  seleccionada: i == _linea,
                  onTap: () => setState(() => _linea = i),
                  onDoubleTap: v.cancelada ? null : () => _devolver(),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (!v.cancelada)
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: () => _devolver(),
                icon: const Icon(Icons.undo),
                label: const Text('Devolver artículo seleccionado'),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
              onPressed: () => _devolver(varios: true),
              child: const Text('Devolver varios'),
            ),
          ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: Text(pago.descripcion + (v.notas.isEmpty ? '' : '\nNotas: ${v.notas}'),
                  style: const TextStyle(color: ExColor.texto2))),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Pagó con:  ${formatoPesos(pago.recibidoCentavos > 0 ? pago.recibidoCentavos : pago.totalCentavos)}',
                style: ExTexto.titulo(18)),
            Text('Total:  ${formatoPesos(v.totalCentavos)}', style: ExTexto.titulo(24)),
          ]),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (!v.cancelada)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: ExColor.rojo, side: const BorderSide(color: ExColor.rojo)),
              onPressed: () => _devolver(todo: true),
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Cancelar venta'),
            ),
          const Spacer(),
          FilledButton.icon(onPressed: _reimprimir, icon: const Icon(Icons.print_outlined), label: const Text('Imprimir copia')),
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
                  Expanded(
                      child: Text('${l.descripcion}\nCompró ${formatoCantidad(l.cantidad)}'
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
