import 'package:flutter/material.dart';

import '../../core/db.dart';
import '../../core/formato.dart';
import '../../core/tickets.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_widgets.dart';
import '../comun/impresion.dart';
import '../sesion.dart';
import '../tema/tema.dart';

/// Corte de caja: turno actual, cierre, corte del día e historial.
class CortePage extends StatefulWidget {
  const CortePage({super.key, required this.alCerrarTurno});
  final VoidCallback alCerrarTurno;

  @override
  State<CortePage> createState() => _CortePageState();
}

enum _Vista { turno, dia, historial }

class _CortePageState extends State<CortePage> {
  _Vista _vista = _Vista.turno;
  Corte? _corte;
  DateTime _dia = DateTime.now();
  List<Turno> _turnos = [];
  List<MovimientoCaja> _movs = [];

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
    final t = sesion.turno;
    Corte? c;
    var movs = <MovimientoCaja>[];
    var turnos = <Turno>[];
    switch (_vista) {
      case _Vista.turno:
        if (t != null) {
          c = await repos.caja.corteTurno(t.id);
          movs = await repos.caja.movimientosCaja([t.id]);
        }
      case _Vista.dia:
        c = await repos.caja.corteDia(_dia);
        final inicio = DateTime(_dia.year, _dia.month, _dia.day);
        final ts = await repos.caja.turnos(desde: inicio, hasta: inicio.add(const Duration(days: 1)));
        movs = await repos.caja.movimientosCaja(ts.map((x) => x.id).toList());
      case _Vista.historial:
        turnos = await repos.caja.turnos(desde: DateTime.now().subtract(const Duration(days: 60)));
    }
    if (!mounted) return;
    setState(() {
      _corte = c;
      _movs = movs;
      _turnos = turnos;
    });
  }

  Future<void> _cambiarVista(_Vista v) async {
    if (v != _Vista.turno && !await autorizar(context, Permiso.corteDia)) return;
    setState(() => _vista = v);
    _cargar();
  }

  Future<void> _imprimir({int? contado}) async {
    final c = _corte;
    if (c == null) return;
    final pdf = await ticketCorte(c, contadoCentavos: contado);
    if (mounted) await vistaPrevia(context, pdf, titulo: c.titulo);
  }

  Future<void> _cerrarTurno() async {
    final t = sesion.turno;
    final c = _corte;
    if (t == null || c == null) return;
    final contado = await showDialog<int>(context: context, builder: (_) => const _Conteo());
    if (contado == null || !mounted) return;
    if (!await confirmar(context, 'Cerrar turno',
        'Contaste ${formatoPesos(contado)}. Al cerrar el turno ya no se pueden registrar ventas en él. ¿Cerrar?',
        si: 'Cerrar turno')) {
      return;
    }
    final dif = await repos.caja.cerrarTurno(t.id, contado);
    await respaldoAutomatico(repos.db);
    if (!mounted) return;
    final corte = await repos.caja.corteTurno(t.id);
    final pdf = await ticketCorte(corte, contadoCentavos: contado);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Turno cerrado'),
        content: Text(dif == 0
            ? 'La caja cuadra exacto. ¡Bien!'
            : dif > 0
                ? 'Sobran ${formatoPesos(dif)} en la caja.'
                : 'Faltan ${formatoPesos(-dif)} en la caja.'),
        actions: [
          OutlinedButton(
              onPressed: () async {
                await imprimir(context, pdf, nombre: 'Corte turno ${t.numero}');
              },
              child: const Text('Imprimir corte')),
          FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Salir')),
        ],
      ),
    );
    widget.alCerrarTurno();
  }

  @override
  Widget build(BuildContext context) {
    final mostrarEsperado = repos.ajustes.si(Ajuste.corteMostrarEsperado) || sesion.puede(Permiso.corteDia);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Corte', style: ExTexto.titulo(28)),
          const SizedBox(width: 20),
          SegmentedButton<_Vista>(
            segments: const [
              ButtonSegment(value: _Vista.turno, label: Text('Turno actual')),
              ButtonSegment(value: _Vista.dia, label: Text('Corte del día')),
              ButtonSegment(value: _Vista.historial, label: Text('Historial de turnos')),
            ],
            selected: {_vista},
            onSelectionChanged: (s) => _cambiarVista(s.first),
          ),
          if (_vista == _Vista.dia) ...[
            const SizedBox(width: 12),
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
          ],
          const Spacer(),
          if (_vista != _Vista.historial)
            OutlinedButton.icon(onPressed: _imprimir, icon: const Icon(Icons.print_outlined), label: const Text('Imprimir')),
          if (_vista == _Vista.turno) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: ExColor.acento, foregroundColor: ExColor.tinta),
              onPressed: _cerrarTurno,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Hacer corte y cerrar turno'),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        Expanded(child: _vista == _Vista.historial ? _historial() : _detalle(mostrarEsperado)),
      ]),
    );
  }

  Widget _detalle(bool mostrarEsperado) {
    final c = _corte;
    if (c == null) return const ExVacio('No hay turno abierto');
    Widget fila(String a, int b, {bool negrita = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: negrita ? FontWeight.w700 : FontWeight.w400))),
            Text(formatoPesos(b), style: ExTexto.mono(15, color: color, peso: negrita ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(c.titulo, style: const TextStyle(color: ExColor.texto2)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ExKpi(nombre: 'Ventas totales', valor: formatoPesos(c.ventasCentavos), nota: '${c.numeroVentas} ventas', destacado: true)),
          const SizedBox(width: 12),
          if (sesion.puede(Permiso.reportes)) ...[
            Expanded(child: ExKpi(nombre: 'Ganancia', valor: formatoPesos(c.gananciaCentavos))),
            const SizedBox(width: 12),
          ],
          if (mostrarEsperado)
            Expanded(child: ExKpi(nombre: 'Dinero en caja', valor: formatoPesos(c.esperadoCentavos), nota: 'Efectivo que debe haber')),
          const SizedBox(width: 12),
          Expanded(child: ExKpi(nombre: 'Por cobrar (crédito)', valor: formatoPesos(c.creditoCentavos))),
        ]),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: ExSeccion(
              titulo: 'Dinero en caja',
              child: Column(children: [
                fila('Fondo de caja', c.fondoCentavos),
                fila('+ Ventas en efectivo', c.efectivoCentavos),
                fila('+ Abonos en efectivo', c.abonosEfectivoCentavos),
                fila('+ Entradas', c.entradasCentavos),
                fila('− Salidas', c.salidasCentavos, color: ExColor.rojo),
                fila('− Devoluciones en efectivo', c.devolucionesEfectivoCentavos, color: ExColor.rojo),
                const Divider(),
                if (mostrarEsperado) fila('= Efectivo esperado', c.esperadoCentavos, negrita: true),
                if (c.dolaresCentavos > 0) fila('Además, dólares (en pesos)', c.dolaresCentavos),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ExSeccion(
              titulo: 'Ventas por forma de pago',
              child: Column(children: [
                fila('Efectivo', c.efectivoCentavos),
                fila('Tarjeta', c.tarjetaCentavos),
                fila('Vales de despensa', c.valesCentavos),
                fila('Dólares', c.dolaresCentavos),
                fila('A crédito', c.creditoCentavos),
                const Divider(),
                fila('Abonos con tarjeta / transferencia', c.abonosOtrosCentavos),
                fila('Devoluciones y cancelaciones', c.devolucionesCentavos, color: ExColor.rojo),
                if (c.ivaCentavos > 0) fila('IVA incluido', c.ivaCentavos),
                if (c.iepsCentavos > 0) fila('IEPS incluido', c.iepsCentavos),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ExSeccion(
              titulo: 'Ventas por departamento',
              child: c.porDepartamento.isEmpty
                  ? const Text('Sin ventas')
                  : Column(children: [
                      for (final d in c.porDepartamento)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(children: [
                            Expanded(child: Text(d.$1)),
                            Text(formatoPesos(d.$2), style: ExTexto.mono(14)),
                            if (sesion.puede(Permiso.reportes))
                              SizedBox(
                                width: 110,
                                child: Text('gan. ${formatoPesos(d.$3)}',
                                    textAlign: TextAlign.right, style: const TextStyle(color: ExColor.texto2, fontSize: 12)),
                              ),
                          ]),
                        ),
                    ]),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        ExSeccion(
          titulo: 'Entradas y salidas de efectivo',
          child: _movs.isEmpty
              ? const Text('Sin movimientos')
              : Column(children: [
                  for (final m in _movs)
                    ListTile(
                      dense: true,
                      leading: Icon(m.tipo == 'entrada' ? Icons.south_west : Icons.north_east,
                          color: m.tipo == 'entrada' ? ExColor.verde : ExColor.rojo),
                      title: Text(m.concepto.isEmpty ? (m.tipo == 'entrada' ? 'Entrada' : 'Salida') : m.concepto),
                      subtitle: Text(formatoFechaHora(m.fecha)),
                      trailing: Text(formatoPesos(m.montoCentavos), style: ExTexto.mono(14)),
                    ),
                ]),
        ),
      ]),
    );
  }

  Widget _historial() {
    return Column(children: [
      const EncabezadoTabla([
        ('Turno', 1, false), ('Cajero', 3, false), ('Abierto', 3, false), ('Cerrado', 3, false),
        ('Fondo', 2, true), ('Esperado', 2, true), ('Contado', 2, true), ('Diferencia', 2, true),
      ]),
      Expanded(
        child: Container(
          color: ExColor.blanco,
          child: ListView.builder(
            itemCount: _turnos.length,
            itemBuilder: (_, i) {
              final t = _turnos[i];
              final dif = t.contadoCentavos == null || t.esperadoCentavos == null ? null : t.contadoCentavos! - t.esperadoCentavos!;
              return FilaTabla(
                [
                  (celda('${t.numero}', mono: true), 1, false),
                  (celda(t.cajeroNombre ?? ''), 3, false),
                  (celda(formatoFechaHora(t.abierto), mono: true), 3, false),
                  (celda(t.cerrado == null ? 'Abierto' : formatoFechaHora(t.cerrado!), mono: true), 3, false),
                  (celda(formatoPesos(t.fondoCentavos), mono: true), 2, true),
                  (celda(t.esperadoCentavos == null ? '—' : formatoPesos(t.esperadoCentavos!), mono: true), 2, true),
                  (celda(t.contadoCentavos == null ? '—' : formatoPesos(t.contadoCentavos!), mono: true), 2, true),
                  (
                    celda(dif == null ? '—' : formatoPesos(dif),
                        mono: true, negrita: true, color: dif == null || dif == 0 ? null : (dif > 0 ? ExColor.verde : ExColor.rojo)),
                    2,
                    true
                  ),
                ],
                par: i.isOdd,
                onDoubleTap: () async {
                  final c = await repos.caja.corteTurno(t.id);
                  final pdf = await ticketCorte(c, contadoCentavos: t.contadoCentavos);
                  if (mounted) await vistaPrevia(context, pdf, titulo: 'Corte turno ${t.numero}');
                },
              );
            },
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text('Doble clic en un turno para ver e imprimir su corte.', style: TextStyle(color: ExColor.texto2)),
      ),
    ]);
  }
}

/// Conteo del efectivo por billetes y monedas.
class _Conteo extends StatefulWidget {
  const _Conteo();

  @override
  State<_Conteo> createState() => _ConteoState();
}

const _denominaciones = [100000, 50000, 20000, 10000, 5000, 2000, 1000, 500, 200, 100, 50];

class _ConteoState extends State<_Conteo> {
  final _ctrls = {for (final d in _denominaciones) d: TextEditingController()};
  final _directo = TextEditingController();

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _directo.dispose();
    super.dispose();
  }

  int get _suma => _ctrls.entries.fold(0, (s, e) => s + (int.tryParse(e.value.text) ?? 0) * e.key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('¿Cuánto dinero hay en la caja?'),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Cuenta billetes y monedas, o escribe el total directo.'),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final d in _denominaciones)
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _ctrls[d],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: d >= 2000 ? 'Billetes \$${d ~/ 100}' : 'Monedas \$${d / 100 < 1 ? '0.50' : d ~/ 100}'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
          ]),
          const SizedBox(height: 14),
          Text('Suma: ${formatoPesos(_suma)}', style: ExTexto.titulo(20)),
          const SizedBox(height: 14),
          CampoNumero(controller: _directo, etiqueta: 'O escribe el total contado (\$)'),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            final directo = leerPesos(_directo.text);
            Navigator.pop(context, directo ?? _suma);
          },
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}
