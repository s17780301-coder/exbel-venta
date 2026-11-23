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
    final r = await repos.productos.buscar(_c.text, limite: 200);
    if (mounted) {
      setState(() {
        _lista = r;
        _sel = 0;
      });
    }
  }

  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _sel = (_sel + 1).clamp(0, _lista.isEmpty ? 0 : _lista.length - 1));
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _sel = (_sel - 1).clamp(0, _lista.isEmpty ? 0 : _lista.length - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _aceptar() {
    if (_lista.isEmpty) return;
    Navigator.pop(context, _lista[_sel]);
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
                      _espera = Timer(const Duration(milliseconds: 180), _buscar);
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
                ? const Center(child: Text('Sin resultados'))
                : ListView.builder(
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
                        onTap: () => setState(() => _sel = i),
                        onDoubleTap: () => Navigator.pop(context, p),
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
