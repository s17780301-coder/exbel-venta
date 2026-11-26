import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formato.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../tema/tema.dart';
import '../zoom.dart';
import 'ex_widgets.dart';

/// Lo que se eligió en el buscador universal.
class Hallazgo {
  Hallazgo.producto(Producto this.producto) : cliente = null, venta = null;
  Hallazgo.cliente(Cliente this.cliente) : producto = null, venta = null;
  Hallazgo.venta(Venta this.venta) : producto = null, cliente = null;
  final Producto? producto;
  final Cliente? cliente;
  final Venta? venta;
}

/// F10 desde cualquier pantalla: busca productos (nombre o código),
/// clientes (nombre, teléfono o número) y ventas (folio) a la vez.
/// true mientras el buscador está abierto (F10 no abre otro encima).
bool buscadorAbierto = false;

Future<Hallazgo?> buscarUniversal(BuildContext context, {String texto = '', String titulo = 'Buscar'}) async {
  buscadorAbierto = true;
  try {
    return await showDialog<Hallazgo>(context: context, builder: (_) => _Buscador(texto: texto, titulo: titulo));
  } finally {
    buscadorAbierto = false;
  }
}

class _Buscador extends StatefulWidget {
  const _Buscador({required this.texto, required this.titulo});
  final String texto;
  final String titulo;

  @override
  State<_Buscador> createState() => _BuscadorState();
}

class _BuscadorState extends State<_Buscador> {
  late final _c = TextEditingController(text: widget.texto);
  List<Hallazgo> _r = [];
  int _sel = 0;
  final _claveSel = GlobalKey();
  Timer? _espera;
  int _consulta = 0;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _c.dispose();
    super.dispose();
  }

  String _buscado = '\u0000';

  Future<void> _buscar() async {
    final n = ++_consulta;
    final t = _c.text.trim();
    final r = <Hallazgo>[];
    // Vacío hasta que se escriban al menos 2 letras (como pidió la tienda).
    if (t.isEmpty) {
      if (mounted) {
        setState(() {
          _r = [];
          _buscado = t;
        });
      }
      return;
    }
    final folio = int.tryParse(t);
    if (folio != null) {
      final v = await repos.ventas.porFolio(folio);
      if (v != null) r.add(Hallazgo.venta(v));
    }
    final codigo = t.isEmpty ? null : await repos.productos.porCodigo(t);
    if (codigo != null) r.add(Hallazgo.producto(codigo));
    // Desde 2 letras busca; antes muestra los más vendidos.
    for (final p in await repos.productos.buscar(t, porUso: true, limite: 60)) {
      if (p.id != codigo?.id) r.add(Hallazgo.producto(p));
    }
    {
      for (final c in (await repos.clientes.buscar(t)).take(20)) {
        r.add(Hallazgo.cliente(c));
      }
    }
    if (!mounted || n != _consulta) return;
    setState(() {
      _r = r;
      _sel = 0;
      _buscado = t;
    });
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    final d = switch (e.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.pageDown => 10,
      LogicalKeyboardKey.pageUp => -10,
      _ => 0,
    };
    if (d == 0) return KeyEventResult.ignored;
    setState(() => _sel = (_sel + d).clamp(0, _r.isEmpty ? 0 : _r.length - 1));
    verFila(_claveSel, bajando: d > 0);
    return KeyEventResult.handled;
  }

  /// Enter: espera a que termine la búsqueda de lo escrito (no se pierde el
  /// primer Enter).
  Future<void> _aceptar() async {
    if (_c.text.trim() != _buscado) {
      _espera?.cancel();
      await _buscar();
      if (!mounted) return;
    }
    if (_r.isEmpty) return;
    _elegir(_r[_sel.clamp(0, _r.length - 1)]);
  }

  bool _cerrado = false;

  void _elegir(Hallazgo h) {
    if (_cerrado) return;
    _cerrado = true;
    final p = h.producto;
    if (p != null) repos.productos.registrarBusqueda(p.id);
    Navigator.pop(context, h);
  }

  Widget _fila(int i) {
    final h = _r[i];
    final sel = i == _sel;
    late IconData icono;
    late String titulo, sub, derecha;
    String tipo;
    final p = h.producto, c = h.cliente, v = h.venta;
    if (p != null) {
      icono = Icons.inventory_2_outlined;
      tipo = 'Producto';
      titulo = p.descripcion;
      sub = [if (p.codigo.isNotEmpty) p.codigo, p.departamentoNombre ?? '', if (p.usaInventario) 'Hay ${formatoCantidad(p.existencia)}']
          .where((x) => x.isNotEmpty)
          .join(' · ');
      derecha = formatoPesos(p.precioCentavos);
    } else if (c != null) {
      icono = Icons.person_outline;
      tipo = 'Cliente';
      titulo = c.nombre;
      sub = ['No. ${c.numero}', if (c.telefono.isNotEmpty) c.telefono].join(' · ');
      derecha = c.saldoCentavos > 0 ? 'Debe ${formatoPesos(c.saldoCentavos)}' : '';
    } else {
      icono = Icons.receipt_long_outlined;
      tipo = 'Venta';
      titulo = 'Folio ${v!.folio}';
      sub = '${formatoFechaHora(v.fecha)} · ${v.clienteNombre ?? 'Público en general'}${v.cancelada ? ' · cancelada' : ''}';
      derecha = formatoPesos(v.totalCentavos);
    }
    return Material(
      color: sel ? ExColor.lavanda : (i.isOdd ? ExColor.concreto : ExColor.blanco),
      child: InkWell(
        // Un clic basta para elegir.
        onTap: () => _elegir(h),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Icon(icono, color: ExColor.indigo),
            const SizedBox(width: 12),
            SizedBox(width: 72, child: Text(tipo, style: const TextStyle(fontSize: 12, color: ExColor.texto2))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 13, color: ExColor.texto2), overflow: TextOverflow.ellipsis),
              ]),
            ),
            Text(derecha, style: ExTexto.mono(15, peso: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: anchoDialogo(context, 940),
        height: altoDialogo(context, 660),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            color: ExColor.banda,
            padding: const EdgeInsets.fromLTRB(22, 10, 8, 10),
            child: Row(children: [
              Text(widget.titulo.toUpperCase(), style: ExTexto.titulo(20, color: ExColor.bandaTexto)),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: ExColor.bandaTexto)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Focus(
              onKeyEvent: _tecla,
              child: ExBuscador(
                controller: _c,
                autofocus: true,
                hint: 'Producto (nombre o código), cliente o folio de venta',
                onChanged: (_) {
                  _espera?.cancel();
                  _espera = Timer(const Duration(milliseconds: 120), _buscar);
                },
                onSubmitted: (_) => _aceptar(),
              ),
            ),
          ),
          Expanded(
            child: _r.isEmpty
                ? ExVacio(_c.text.trim().isEmpty ? 'Escribe una letra del producto, cliente o folio' : 'Sin resultados')
                : ListView.builder(itemCount: _r.length, itemBuilder: (_, i) => KeyedSubtree(key: i == _sel ? _claveSel : null, child: _fila(i))),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Text(_c.text.trim().isEmpty ? 'Primero salen los más buscados y vendidos' : '${_r.length} resultados · clic o ENTER para elegir',
                  style: const TextStyle(color: ExColor.texto2)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('ESC - Cancelar')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _aceptar, child: const Text('ENTER - Aceptar')),
            ]),
          ),
        ]),
      ),
    );
  }
}
