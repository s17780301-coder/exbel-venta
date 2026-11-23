import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../data/reportes_repo.dart';
import '../../data/repos.dart';
import '../comun/csv.dart';
import '../comun/dialogos.dart' show EncabezadoTabla, FilaTabla, celda;
import '../comun/ex_widgets.dart';
import '../tema/tema.dart';

/// Reportes de ventas y ganancias.
class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

enum _Periodo { hoy, ayer, semana, mes, mesPasado, otro }

const _reportes = [
  'Por día',
  'Por producto',
  'Por departamento',
  'Por cajero',
  'Por cliente',
  'Por hora',
  'Formas de pago',
  'Sin ventas (no rotan)',
];

class _ReportesPageState extends State<ReportesPage> {
  _Periodo _periodo = _Periodo.mes;
  late DateTime _desde;
  late DateTime _hasta;
  int _reporte = 0;
  List<FilaReporte> _filas = [];
  bool _porGanancia = false;

  @override
  void initState() {
    super.initState();
    _fijar(_Periodo.mes);
    cambiosDatos.addListener(_cargar);
  }

  @override
  void dispose() {
    cambiosDatos.removeListener(_cargar);
    super.dispose();
  }

  void _fijar(_Periodo p) {
    final h = DateTime.now();
    final hoy = DateTime(h.year, h.month, h.day);
    switch (p) {
      case _Periodo.hoy:
        _desde = hoy;
        _hasta = hoy.add(const Duration(days: 1));
      case _Periodo.ayer:
        _desde = hoy.subtract(const Duration(days: 1));
        _hasta = hoy;
      case _Periodo.semana:
        _desde = hoy.subtract(Duration(days: hoy.weekday - 1));
        _hasta = hoy.add(const Duration(days: 1));
      case _Periodo.mes:
        _desde = DateTime(hoy.year, hoy.month);
        _hasta = hoy.add(const Duration(days: 1));
      case _Periodo.mesPasado:
        _desde = DateTime(hoy.year, hoy.month - 1);
        _hasta = DateTime(hoy.year, hoy.month);
      case _Periodo.otro:
        break;
    }
    _periodo = p;
    _cargar();
  }

  Future<void> _otro() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _desde, end: _hasta.subtract(const Duration(days: 1))),
    );
    if (r == null) return;
    _desde = r.start;
    _hasta = r.end.add(const Duration(days: 1));
    setState(() => _periodo = _Periodo.otro);
    _cargar();
  }

  Future<void> _cargar() async {
    final r = repos.reportes;
    final f = switch (_reporte) {
      0 => await r.porDia(_desde, _hasta),
      1 => await r.porProducto(_desde, _hasta, orden: _porGanancia ? 'ganancia DESC' : 'ventas DESC'),
      2 => await r.porDepartamento(_desde, _hasta),
      3 => await r.porCajero(_desde, _hasta),
      4 => await r.porCliente(_desde, _hasta),
      5 => await r.porHora(_desde, _hasta),
      6 => await r.porFormaPago(_desde, _hasta),
      _ => await r.sinMovimiento(_desde, _hasta),
    };
    if (mounted) setState(() => _filas = f);
  }

  String _nombre(FilaReporte f) {
    if (_reporte == 0 && f.nombre.length == 10) {
      final d = DateTime.tryParse(f.nombre);
      if (d != null) return formatoFecha(d);
    }
    if (_reporte == 5) return '${f.nombre}:00';
    return f.nombre;
  }

  @override
  Widget build(BuildContext context) {
    final ventas = _filas.fold<int>(0, (s, f) => s + f.ventasCentavos);
    final ganancia = _filas.fold<int>(0, (s, f) => s + f.gananciaCentavos);
    final sinVentas = _reporte == 7;
    final maximo = _filas.isEmpty ? 1 : _filas.map((f) => f.ventasCentavos).reduce(math.max).clamp(1, 1 << 62);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Reportes', style: ExTexto.titulo(28)),
          const SizedBox(width: 20),
          Expanded(
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in _Periodo.values)
                ChoiceChip(
                  label: Text(switch (p) {
                    _Periodo.hoy => 'Hoy',
                    _Periodo.ayer => 'Ayer',
                    _Periodo.semana => 'Esta semana',
                    _Periodo.mes => 'Este mes',
                    _Periodo.mesPasado => 'Mes pasado',
                    _Periodo.otro => _periodo == _Periodo.otro
                        ? '${formatoFecha(_desde)} – ${formatoFecha(_hasta.subtract(const Duration(days: 1)))}'
                        : 'Otras fechas…',
                  }),
                  selected: _periodo == p,
                  onSelected: (_) {
                    if (p == _Periodo.otro) {
                      _otro();
                    } else {
                      setState(() => _fijar(p));
                    }
                  },
                ),
            ]),
          ),
          OutlinedButton.icon(
            onPressed: () => guardarCsv(context, 'reporte-${_reportes[_reporte].toLowerCase().replaceAll(' ', '-')}', [
              ['nombre', 'cantidad', sinVentas ? 'valor_inventario' : 'ventas', 'ganancia'],
              for (final f in _filas)
                [_nombre(f), formatoCantidad(f.cantidad), (f.ventasCentavos / 100).toStringAsFixed(2), (f.gananciaCentavos / 100).toStringAsFixed(2)],
            ]),
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Exportar a Excel'),
          ),
        ]),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var i = 0; i < _reportes.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ExFiltro(
                  texto: _reportes[i],
                  seleccionado: _reporte == i,
                  onTap: () {
                    setState(() => _reporte = i);
                    _cargar();
                  },
                ),
              ),
            if (_reporte == 1) ...[
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Ordenar por ganancia'),
                selected: _porGanancia,
                onSelected: (v) {
                  setState(() => _porGanancia = v);
                  _cargar();
                },
              ),
            ],
          ]),
        ),
        const SizedBox(height: 14),
        if (!sinVentas)
          Row(children: [
            Expanded(child: ExKpi(nombre: 'Ventas del periodo', valor: formatoPesos(ventas), destacado: true)),
            const SizedBox(width: 12),
            if (_reporte != 6) ...[
              Expanded(child: ExKpi(nombre: 'Ganancia', valor: formatoPesos(ganancia))),
              const SizedBox(width: 12),
              Expanded(
                  child: ExKpi(
                      nombre: 'Margen', valor: ventas == 0 ? '—' : '${(ganancia / ventas * 100).toStringAsFixed(1)}%')),
            ],
          ]),
        const SizedBox(height: 14),
        EncabezadoTabla([
          (_reportes[_reporte].replaceFirst('Por ', '').replaceFirst('Sin ventas (no rotan)', 'Producto'), 6, false),
          if (_reporte != 6) (sinVentas ? 'Existencia' : 'Cantidad', 2, true),
          (sinVentas ? 'Dinero detenido (costo)' : 'Ventas', 3, true),
          if (!sinVentas && _reporte != 6) ('Ganancia', 3, true),
          if (!sinVentas) ('', 5, false),
        ]),
        Expanded(
          child: Container(
            color: ExColor.blanco,
            child: _filas.isEmpty
                ? const ExVacio('Sin datos en ese periodo')
                : ListView.builder(
                    itemCount: _filas.length,
                    itemExtent: 40,
                    itemBuilder: (_, i) {
                      final f = _filas[i];
                      return FilaTabla([
                        (celda(_nombre(f)), 6, false),
                        if (_reporte != 6) (celda(formatoCantidad(f.cantidad), mono: true), 2, true),
                        (celda(formatoPesos(f.ventasCentavos), mono: true, negrita: true), 3, true),
                        if (!sinVentas && _reporte != 6)
                          (celda(formatoPesos(f.gananciaCentavos), mono: true, color: f.gananciaCentavos < 0 ? ExColor.rojo : ExColor.verde), 3, true),
                        if (!sinVentas)
                          (
                            Padding(
                              padding: const EdgeInsets.only(left: 16),
                              child: FractionallySizedBox(
                                widthFactor: (f.ventasCentavos / maximo).clamp(0.0, 1.0).toDouble(),
                                alignment: Alignment.centerLeft,
                                child: Container(height: 14, color: i == 0 ? ExColor.acento : ExColor.indigo),
                              ),
                            ),
                            5,
                            false
                          ),
                      ], par: i.isOdd);
                    },
                  ),
          ),
        ),
        if (sinVentas)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Productos que no se vendieron en el periodo, ordenados por el dinero que tienes invertido en ellos.',
                style: TextStyle(color: ExColor.texto2)),
          ),
      ]),
    );
  }
}
