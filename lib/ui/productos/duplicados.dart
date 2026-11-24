import 'package:flutter/material.dart';

import '../../core/formato.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../tema/tema.dart';

/// Anti duplicados: muestra los productos repetidos (mismo código o mismo
/// nombre) para dejar solo uno.
Future<bool> revisarDuplicados(BuildContext context) async {
  final r = await showDialog<bool>(context: context, builder: (_) => const _Duplicados());
  return r ?? false;
}

class _Duplicados extends StatefulWidget {
  const _Duplicados();

  @override
  State<_Duplicados> createState() => _DuplicadosState();
}

class _DuplicadosState extends State<_Duplicados> {
  List<({String motivo, List<Producto> productos})>? _grupos;
  bool _cambio = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final g = await repos.productos.duplicados();
    if (mounted) setState(() => _grupos = g);
  }

  Future<void> _eliminar(Producto p) async {
    if (!await confirmar(context, 'Eliminar repetido',
        '¿Eliminar "${p.descripcion}" (código ${p.codigo.isEmpty ? 'sin código' : p.codigo}, existencia ${formatoCantidad(p.existencia)})? '
            'Sus ventas pasadas se conservan.',
        si: 'Eliminar', peligro: true)) {
      return;
    }
    await repos.productos.eliminar(p.id);
    _cambio = true;
    await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final g = _grupos;
    return AlertDialog(
      title: const Text('Productos repetidos'),
      content: SizedBox(
        width: 760,
        height: 520,
        child: g == null
            ? const Center(child: CircularProgressIndicator())
            : g.isEmpty
                ? const Center(child: Text('No hay productos repetidos. ¡Todo en orden!', style: TextStyle(fontSize: 16)))
                : ListView(children: [
                    Text('Se encontraron ${g.length} grupos. Deja el bueno y elimina los demás. '
                        'Antes de eliminar, revisa cuál tiene la existencia correcta.',
                        style: const TextStyle(color: ExColor.texto2)),
                    const SizedBox(height: 10),
                    for (final grupo in g)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text(grupo.motivo, style: const TextStyle(fontWeight: FontWeight.w700, color: ExColor.rojo)),
                            for (final p in grupo.productos)
                              Row(children: [
                                SizedBox(width: 130, child: Text(p.codigo.isEmpty ? '(sin código)' : p.codigo, style: ExTexto.mono(13))),
                                Expanded(child: Text(p.descripcion, overflow: TextOverflow.ellipsis)),
                                SizedBox(width: 90, child: Text(formatoPesos(p.precioCentavos), textAlign: TextAlign.right, style: ExTexto.mono(13))),
                                SizedBox(
                                    width: 90,
                                    child: Text(p.usaInventario ? 'Hay ${formatoCantidad(p.existencia)}' : '—',
                                        textAlign: TextAlign.right, style: const TextStyle(color: ExColor.texto2))),
                                TextButton(onPressed: () => _eliminar(p), child: const Text('Eliminar')),
                              ]),
                          ]),
                        ),
                      ),
                  ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context, _cambio), child: const Text('Cerrar'))],
    );
  }
}
