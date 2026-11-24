import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../core/ids.dart';
import '../../core/tickets.dart';
import '../../data/clientes_repo.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/csv.dart';
import '../comun/dialogos.dart';
import '../comun/importar_dialogo.dart';
import '../comun/ex_widgets.dart';
import '../comun/impresion.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../ventas/ventas_dia.dart';

/// El buscador universal (F10) pide abrir un cliente aquí.
final clienteParaAbrir = ValueNotifier<String?>(null);

/// F2: clientes y crédito.
class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _buscar = TextEditingController();
  List<Cliente> _lista = [];
  bool _soloAdeudo = false;
  Cliente? _sel;
  List<MovimientoCuenta> _cuenta = [];
  DateTime? _desde;
  int _saldoTotal = 0;

  @override
  void initState() {
    super.initState();
    cambiosDatos.addListener(_cargar);
    clienteParaAbrir.addListener(_abrirPedido);
    _cargar();
    _abrirPedido();
  }

  Future<void> _abrirPedido() async {
    final id = clienteParaAbrir.value;
    if (id == null) return;
    clienteParaAbrir.value = null;
    await _elegir(await repos.clientes.porId(id));
  }

  @override
  void dispose() {
    clienteParaAbrir.removeListener(_abrirPedido);
    cambiosDatos.removeListener(_cargar);
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final l = await repos.clientes.buscar(_buscar.text, soloConSaldo: _soloAdeudo);
    final t = await repos.clientes.saldoTotal();
    if (!mounted) return;
    setState(() {
      _lista = l;
      _saldoTotal = t;
    });
    final s = _sel;
    if (s != null) await _elegir(await repos.clientes.porId(s.id));
  }

  Future<void> _elegir(Cliente? c) async {
    final cuenta = c == null ? <MovimientoCuenta>[] : await repos.clientes.estadoDeCuenta(c.id);
    final desde = c == null ? null : await repos.clientes.deudaMasAntigua(c.id);
    if (!mounted) return;
    setState(() {
      _sel = c;
      _cuenta = cuenta.reversed.toList();
      _desde = desde;
    });
  }

  Future<void> _editar([Cliente? c]) async {
    if (!await autorizar(context, Permiso.clientes) || !mounted) return;
    final r = await showDialog<(Cliente, int)>(context: context, builder: (_) => _FormCliente(c));
    if (r == null || !mounted) return;
    await intentar(context, () async {
      var g = await repos.clientes.guardar(r.$1);
      if (c == null && r.$2 > 0) {
        await repos.clientes.fijarSaldoAnterior(g.id, r.$2);
        g = (await repos.clientes.porId(g.id))!;
      }
      avisarCambio();
      await _elegir(g);
    });
  }

  Future<void> _exportarSaldos() async {
    final todos = await repos.clientes.buscar('');
    if (!mounted) return;
    await guardarCsv(context, 'saldos-clientes', [
      ['numero', 'nombre', 'telefono', 'direccion', 'limite', 'saldo'],
      for (final c in todos)
        [
          '${c.numero}', c.nombre, c.telefono, c.direccion,
          (c.limiteCentavos / 100).toStringAsFixed(2), (c.saldoCentavos / 100).toStringAsFixed(2),
        ],
    ]);
  }

  Future<void> _eliminar() async {
    final c = _sel;
    if (c == null) return;
    if (!await autorizar(context, Permiso.clientes) || !mounted) return;
    if (!await confirmar(context, 'Eliminar cliente', '¿Eliminar a ${c.nombre}?', si: 'Eliminar', peligro: true)) return;
    if (!mounted) return;
    final ok = await intentar(context, () => repos.clientes.eliminar(c.id));
    if (ok) {
      _sel = null;
      avisarCambio();
    }
  }

  Future<void> _abonar({bool liquidar = false}) async {
    final c = _sel;
    final turno = sesion.turno;
    if (c == null || turno == null) return;
    if (c.saldoCentavos <= 0) return aviso(context, '${c.nombre} no debe nada.');
    if (!await autorizar(context, Permiso.abonos) || !mounted) return;
    final r = await showDialog<(int, String)>(
        context: context, builder: (_) => _Abono(c, liquidar ? c.saldoCentavos : null));
    if (r == null || !mounted) return;
    final ok = await intentar(
        context, () => repos.clientes.abonar(clienteId: c.id, montoCentavos: r.$1, turnoId: turno.id, formaPago: r.$2));
    if (!ok || !mounted) return;
    avisarCambio();
    final saldo = c.saldoCentavos - r.$1;
    final pdf = await ticketAbono(c, r.$1, saldo);
    if (mounted) await vistaPrevia(context, pdf, titulo: 'Abono de ${c.nombre}');
  }

  Future<void> _cancelarAbono(MovimientoCuenta m) async {
    if (m.abonoId == null || m.cancelado) return;
    if (!await autorizar(context, Permiso.cancelar) || !mounted) return;
    if (!await confirmar(context, 'Devolver abono', '¿Cancelar el abono de ${formatoPesos(m.abonoCentavos)}? El saldo vuelve a subir.',
        si: 'Cancelar abono', peligro: true)) {
      return;
    }
    await repos.clientes.cancelarAbono(m.abonoId!);
    avisarCambio();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 420,
          child: Container(
            color: ExColor.blanco,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  ExBuscador(controller: _buscar, hint: 'Buscar cliente', onChanged: (_) => _cargar()),
                  const SizedBox(height: 10),
                  Row(children: [
                    FilterChip(
                      label: const Text('Solo con adeudo'),
                      selected: _soloAdeudo,
                      onSelected: (v) {
                        setState(() => _soloAdeudo = v);
                        _cargar();
                      },
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: 'Más',
                      onSelected: (v) async {
                        if (v == 'imp') {
                          if (await autorizar(context, Permiso.clientes) && context.mounted) {
                            await importarDesdeArchivo(context, clientes: true);
                          }
                        } else {
                          await _exportarSaldos();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'imp', child: Text('Importar clientes (Eleventa o Excel)')),
                        PopupMenuItem(value: 'exp', child: Text('Exportar saldos a Excel')),
                      ],
                      icon: const Icon(Icons.more_vert),
                    ),
                    FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Nuevo cliente')),
                  ]),
                ]),
              ),
              const Divider(),
              Expanded(
                child: _lista.isEmpty
                    ? const ExVacio('Sin clientes')
                    : ListView.builder(
                        itemCount: _lista.length,
                        itemBuilder: (_, i) {
                          final c = _lista[i];
                          return ListTile(
                            selected: _sel?.id == c.id,
                            selectedTileColor: ExColor.lavanda.withOpacity(0.5),
                            leading: ExAvatar(c.nombre),
                            title: Text(c.nombre),
                            subtitle: Text('No. ${c.numero}${c.telefono.isEmpty ? '' : ' · ${c.telefono}'}'),
                            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text(formatoPesos(c.saldoCentavos),
                                  style: ExTexto.mono(14, color: c.saldoCentavos > 0 ? ExColor.rojo : ExColor.texto2)),
                              if (c.alertaCredito(porcentajeAvisoCredito(repos.ajustes)).isNotEmpty)
                                _EtiquetaTope(c.alertaCredito(porcentajeAvisoCredito(repos.ajustes)) == 'alcanzado'),
                            ]),
                            onTap: () => _elegir(c),
                          );
                        },
                      ),
              ),
              Container(
                color: ExColor.banda,
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const Text('Saldo total por cobrar', style: TextStyle(color: ExColor.bandaTexto)),
                  const Spacer(),
                  Text(formatoPesos(_saldoTotal), style: ExTexto.titulo(20, color: ExColor.bandaTexto)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: _panel()),
      ]),
    );
  }

  Widget _panel() {
    final c = _sel;
    if (c == null) {
      return const ExVacio('Elige un cliente para ver su estado de cuenta, abonar o liquidar');
    }
    final dias = _desde == null ? null : DateTime.now().difference(_desde!).inDays;
    return Container(
      color: ExColor.blanco,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          ExAvatar(c.nombre, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.nombre, style: ExTexto.titulo(26)),
              Text([
                'Cliente No. ${c.numero}',
                if (c.telefono.isNotEmpty) c.telefono,
                if (c.direccion.isNotEmpty) c.direccion,
              ].join(' · '), style: const TextStyle(color: ExColor.texto2)),
            ]),
          ),
          OutlinedButton(onPressed: () => _editar(c), child: const Text('Modificar')),
          const SizedBox(width: 8),
          TextButton(onPressed: _eliminar, child: const Text('Eliminar')),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: ExKpi(nombre: 'Saldo actual', valor: formatoPesos(c.saldoCentavos), destacado: true, alerta: c.saldoCentavos > 0)),
          const SizedBox(width: 12),
          Expanded(
              child: ExKpi(
                  nombre: 'Tope de crédito',
                  valor: c.tieneLimite ? formatoPesos(c.limiteCentavos) : 'Sin tope',
                  alerta: c.alertaCredito(porcentajeAvisoCredito(repos.ajustes)).isNotEmpty,
                  nota: c.tieneLimite
                      ? (c.alertaCredito(porcentajeAvisoCredito(repos.ajustes)) == 'alcanzado'
                          ? 'Tope alcanzado (${c.usoCredito} %)'
                          : 'Disponible ${formatoPesos(c.disponibleCentavos)} · usado ${c.usoCredito} %')
                      : null)),
          const SizedBox(width: 12),
          Expanded(
              child: ExKpi(
                  nombre: 'Debe desde',
                  valor: _desde == null ? '—' : formatoFecha(_desde!),
                  nota: dias == null ? null : 'hace $dias días',
                  alerta: (dias ?? 0) > 30)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Text('Estado de cuenta', style: ExTexto.titulo(18)),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => mostrarVentasDelDia(context, clienteId: c.id, clienteNombre: c.nombre),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('Historial de compras'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () => _abonar(liquidar: true), child: const Text('Liquidar adeudo')),
          const SizedBox(width: 8),
          FilledButton.icon(onPressed: _abonar, icon: const Icon(Icons.payments_outlined), label: const Text('Abonar')),
        ]),
        const SizedBox(height: 10),
        const EncabezadoTabla([('Fecha', 3, false), ('Concepto', 5, false), ('Cargo', 2, true), ('Abono', 2, true), ('Saldo', 2, true)]),
        Expanded(
          child: _cuenta.isEmpty
              ? const ExVacio('Sin movimientos')
              : ListView.builder(
                  itemCount: _cuenta.length,
                  itemBuilder: (_, i) {
                    final m = _cuenta[i];
                    final gris = m.cancelado ? ExColor.texto2 : null;
                    return FilaTabla(
                      [
                        (celda(formatoFechaHora(m.fecha), mono: true, color: gris), 3, false),
                        (celda(m.concepto, color: gris), 5, false),
                        (celda(m.cargoCentavos > 0 ? formatoPesos(m.cargoCentavos) : '', mono: true), 2, true),
                        (celda(m.abonoCentavos > 0 ? formatoPesos(m.abonoCentavos) : '', mono: true, color: ExColor.verde), 2, true),
                        (celda(formatoPesos(m.saldoCentavos), mono: true, negrita: true), 2, true),
                      ],
                      par: i.isOdd,
                      onDoubleTap: m.abonoId != null && !m.cancelado ? () => _cancelarAbono(m) : null,
                    );
                  },
                ),
        ),
        const Text('Doble clic en un abono para devolverlo (si se capturó por error).',
            style: TextStyle(color: ExColor.texto2, fontSize: 12)),
      ]),
    );
  }
}

class _FormCliente extends StatefulWidget {
  const _FormCliente(this.c);
  final Cliente? c;

  @override
  State<_FormCliente> createState() => _FormClienteState();
}

class _FormClienteState extends State<_FormCliente> {
  late final _nombre = TextEditingController(text: widget.c?.nombre ?? '');
  late final _tel = TextEditingController(text: widget.c?.telefono ?? '');
  late final _dir = TextEditingController(text: widget.c?.direccion ?? '');
  final _anterior = TextEditingController();
  late final _limite = TextEditingController(
      text: (widget.c?.limiteCentavos ?? 0) > 0 ? (widget.c!.limiteCentavos / 100).toStringAsFixed(2) : '');

  @override
  void dispose() {
    for (final c in [_nombre, _tel, _dir, _limite, _anterior]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return AlertDialog(
      title: Text(c == null ? 'Nuevo cliente' : 'Modificar cliente'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _nombre,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre completo')),
          const SizedBox(height: 12),
          TextField(controller: _tel, decoration: const InputDecoration(labelText: 'Teléfono / WhatsApp')),
          const SizedBox(height: 12),
          TextField(controller: _dir, decoration: const InputDecoration(labelText: 'Dirección')),
          const SizedBox(height: 12),
          CampoNumero(controller: _limite, etiqueta: 'Tope de crédito (\$)', ayuda: 'Lo máximo que puede deber. Vacío = sin tope. Se avisa al acercarse.'),
          if (c == null) ...[
            const SizedBox(height: 12),
            CampoNumero(controller: _anterior, etiqueta: 'Saldo anterior (\$)', ayuda: 'Lo que ya debía (de la libreta o de otro sistema)'),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            (Cliente(
              id: c?.id ?? nuevoId(),
              numero: c?.numero ?? 0,
              nombre: _nombre.text,
              telefono: _tel.text.trim(),
              direccion: _dir.text.trim(),
              limiteCentavos: leerPesos(_limite.text) ?? 0,
              saldoCentavos: c?.saldoCentavos ?? 0,
            ), leerPesos(_anterior.text) ?? 0),
          ),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _Abono extends StatefulWidget {
  const _Abono(this.c, this.monto);
  final Cliente c;
  final int? monto;

  @override
  State<_Abono> createState() => _AbonoState();
}

class _AbonoState extends State<_Abono> {
  late final _m = TextEditingController(text: widget.monto == null ? '' : (widget.monto! / 100).toStringAsFixed(2));
  String _forma = 'efectivo';

  @override
  void dispose() {
    _m.dispose();
    super.dispose();
  }

  void _aceptar() {
    final v = leerPesos(_m.text);
    if (v == null || v <= 0) return aviso(context, 'Escribe la cantidad del abono.');
    Navigator.pop(context, (v, _forma));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.monto == null ? 'Abono de ${widget.c.nombre}' : 'Liquidar a ${widget.c.nombre}'),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Debe ${formatoPesos(widget.c.saldoCentavos)}', style: ExTexto.titulo(20)),
          const SizedBox(height: 14),
          CampoNumero(controller: _m, etiqueta: 'Cantidad (\$)', autofocus: true, onSubmitted: (_) => _aceptar()),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'efectivo', label: Text('Efectivo')),
              ButtonSegment(value: 'tarjeta', label: Text('Tarjeta')),
              ButtonSegment(value: 'transferencia', label: Text('Transferencia')),
            ],
            selected: {_forma},
            onSelectionChanged: (s) => setState(() => _forma = s.first),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _aceptar, child: const Text('Registrar abono')),
      ],
    );
  }
}

class _EtiquetaTope extends StatelessWidget {
  const _EtiquetaTope(this.alcanzado);
  final bool alcanzado;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: (alcanzado ? ExColor.rojo : ExColor.naranja).withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: alcanzado ? ExColor.rojo : ExColor.naranja),
        ),
        child: Text(alcanzado ? 'Tope alcanzado' : 'Cerca del tope',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: alcanzado ? ExColor.rojo : const Color(0xFF8A5A2B))),
      );
}
