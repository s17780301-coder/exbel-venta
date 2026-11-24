import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formato.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_widgets.dart';
import '../zoom.dart';
import '../tema/tema.dart';

/// F10: buscar producto por nombre o código. Enter agrega el seleccionado.
Future<Producto?> buscarProducto(BuildContext context, {String texto = ''}) {
  return showDialog<Producto>(context: context, builder: (_) => _Buscador(texto: texto));
}

class _Buscador extends StatefulWidget {
  const _Buscador({required this.texto});
  final String texto;

  @override
  State<_Buscador> createState() => _BuscadorState();
}

class _BuscadorState extends State<_Buscador> {
  late final _c = TextEditingController(text: widget.texto);
  final _foco = FocusNode();
  List<Producto> _lista = [];
  int _sel = 0;
  final _scroll = ScrollController();
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _c.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final t = _c.text.trim();
    // Vacío hasta 2 letras; luego primero los más buscados y vendidos.
    final r = t.isEmpty ? <Producto>[] : await repos.productos.buscar(t, porUso: true, limite: 200);
    if (mounted) {
      setState(() {
        _lista = r;
        _sel = 0;
      });
    }
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
    setState(() => _sel = (_sel + d).clamp(0, _lista.isEmpty ? 0 : _lista.length - 1));
    seguirFila(_scroll, _sel, 44);
    return KeyEventResult.handled;
  }

  void _aceptar() {
    if (_lista.isEmpty) return;
    _elegir(_lista[_sel]);
  }

  void _elegir(Producto p) {
    repos.productos.registrarBusqueda(p.id);
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: anchoDialogo(context, 960),
        height: altoDialogo(context, 640),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(children: [
              Text('Buscar producto', style: ExTexto.titulo(22)),
              const SizedBox(width: 20),
              Expanded(
                child: Focus(
                  onKeyEvent: _tecla,
                  child: ExBuscador(
                    controller: _c,
                    focusNode: _foco,
                    autofocus: true,
                    hint: 'Escribe parte del nombre o del código',
                    onChanged: (_) {
                      _espera?.cancel();
                      _espera = Timer(const Duration(milliseconds: 120), _buscar);
                    },
                    onSubmitted: (_) => _aceptar(),
                  ),
                ),
              ),
            ]),
          ),
          const EncabezadoTabla([
            ('Código', 3, false),
            ('Descripción', 8, false),
            ('Departamento', 4, false),
            ('Precio', 3, true),
            ('Mayoreo', 3, true),
            ('Existencia', 2, true),
          ]),
          Expanded(
            child: _lista.isEmpty
                ? Center(child: Text(_c.text.trim().isEmpty ? 'Escribe una letra o el código del producto' : 'Sin resultados', style: const TextStyle(fontSize: 16, color: ExColor.texto2)))
                : ListView.builder(
                    controller: _scroll,
                    itemCount: _lista.length,
                    itemExtent: 44,
                    itemBuilder: (_, i) {
                      final p = _lista[i];
                      return FilaTabla(
                        [
                          (celda(p.codigo, mono: true), 3, false),
                          (celda(p.descripcion), 8, false),
                          (celda(p.departamentoNombre ?? '—', color: ExColor.texto2), 4, false),
                          (celda(formatoPesos(p.precioCentavos), mono: true, negrita: true), 3, true),
                          (celda(p.tieneMayoreo ? formatoPesos(p.mayoreoCentavos) : '—', mono: true), 3, true),
                          (
                            celda(p.usaInventario ? formatoCantidad(p.existencia) : '—',
                                mono: true, color: p.bajoMinimo ? ExColor.rojo : null),
                            2,
                            true
                          ),
                        ],
                        par: i.isOdd,
                        seleccionada: i == _sel,
                        onTap: () => _elegir(p),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Text('${_lista.length} productos · ↑ ↓ para moverte · ENTER para agregar',
                  style: const TextStyle(color: ExColor.texto2)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar (Esc)')),
              const SizedBox(width: 8),
              FilledButton(onPressed: _aceptar, child: const Text('Agregar')),
            ]),
          ),
        ]),
      ),
    );
  }
}
