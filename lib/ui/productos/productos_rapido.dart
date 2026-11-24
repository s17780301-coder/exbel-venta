import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formato.dart';
import '../../core/ids.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_ui.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../zoom.dart';
import 'producto_form.dart';

/// F3: ventana sencilla para agregar o eliminar productos.
Future<void> productosRapido(BuildContext context) async {
  if (!await autorizar(context, Permiso.productos)) return;
  if (!context.mounted) return;
  await showDialog<void>(context: context, builder: (_) => const _Rapido());
}

class _Rapido extends StatefulWidget {
  const _Rapido();

  @override
  State<_Rapido> createState() => _RapidoState();
}

class _RapidoState extends State<_Rapido> {
  bool _agregar = true;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: anchoDialogo(context, 760),
        height: altoDialogo(context, 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 10),
            child: Row(children: [
              const TituloSeccion('Productos', icono: Icons.inventory_2_rounded, tono: Tono.verde, subtitulo: 'Agregar o eliminar en un paso'),
              const Spacer(),
              IconButton(tooltip: 'Cerrar (Esc)', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(children: [
              Expanded(child: _pestana(true, Icons.add_rounded, 'Agregar producto', Tono.verde)),
              const SizedBox(width: 10),
              Expanded(child: _pestana(false, Icons.delete_outline_rounded, 'Eliminar producto', Tono.coral)),
            ]),
          ),
          const SizedBox(height: 14),
          Expanded(child: _agregar ? const _Agregar() : const _Eliminar()),
        ]),
      ),
    );
  }

  Widget _pestana(bool agregar, IconData icono, String texto, Tono tono) {
    final activa = _agregar == agregar;
    return Material(
      color: activa ? tono.fondo : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _agregar = agregar),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: activa ? tono.color : ExEstilo.linea, width: activa ? 1.6 : 1),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icono, color: tono.color),
            const SizedBox(width: 8),
            Text(texto, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: activa ? tono.color : ExColor.tinta)),
          ]),
        ),
      ),
    );
  }
}

// ---------------- Agregar ----------------

class _Agregar extends StatefulWidget {
  const _Agregar();

  @override
  State<_Agregar> createState() => _AgregarState();
}

class _AgregarState extends State<_Agregar> {
  final _codigo = TextEditingController();
  final _desc = TextEditingController();
  final _precio = TextEditingController();
  final _costo = TextEditingController();
  final _existencia = TextEditingController();
  final _focoCodigo = FocusNode();
  String _tipo = 'unidad';
  String? _dep;
  List<Departamento> _deps = [];
  Producto? _existente;
  String? _hecho;

  @override
  void initState() {
    super.initState();
    repos.productos.departamentos().then((d) {
      if (mounted) setState(() => _deps = d);
    });
  }

  @override
  void dispose() {
    for (final c in [_codigo, _desc, _precio, _costo, _existencia]) {
      c.dispose();
    }
    _focoCodigo.dispose();
    super.dispose();
  }

  Future<void> _revisarCodigo(String c) async {
    final p = c.trim().isEmpty ? null : await repos.productos.porCodigo(c.trim());
    if (mounted) setState(() => _existente = p);
  }

  Future<void> _guardar() async {
    if (_existente != null) return aviso(context, 'Ese código ya es de "${_existente!.descripcion}".');
    final p = Producto(
      id: nuevoId(),
      codigo: _codigo.text.trim(),
      descripcion: _desc.text.trim(),
      tipo: _tipo,
      departamentoId: _dep,
      costoCentavos: leerPesos(_costo.text) ?? 0,
      precioCentavos: leerPesos(_precio.text) ?? 0,
      iva: repos.ajustes.numero(Ajuste.ivaPorOmision),
    );
    final ok = await intentar(context, () async {
      await repos.productos.guardar(p, existenciaInicial: leerCantidad(_existencia.text) ?? 0, cajeroId: sesion.cajero?.id);
    });
    if (!ok || !mounted) return;
    avisarCambio();
    setState(() {
      _hecho = 'Se agregó "${p.descripcion}" a ${formatoPesos(p.precioCentavos)}.';
      for (final c in [_codigo, _desc, _precio, _costo, _existencia]) {
        c.clear();
      }
      _tipo = 'unidad';
      _existente = null;
    });
    _focoCodigo.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    Widget campo(String etiqueta, TextEditingController c, {bool numero = false, bool auto = false, FocusNode? foco, ValueChanged<String>? cambio, String? ayuda}) =>
        numero
            ? CampoNumero(controller: c, etiqueta: etiqueta, ayuda: ayuda, onSubmitted: (_) => _guardar())
            : TextField(
                controller: c,
                focusNode: foco,
                autofocus: auto,
                onChanged: cambio,
                decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
                onSubmitted: (_) => _guardar(),
              );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_hecho != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Tono.verde.fondo, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Icon(Icons.check_circle_rounded, color: Tono.verde.color),
              const SizedBox(width: 10),
              Expanded(child: Text(_hecho!, style: TextStyle(color: Tono.verde.color, fontWeight: FontWeight.w600))),
            ]),
          ),
        campo('Código de barras (escanéalo)', _codigo, auto: true, foco: _focoCodigo, cambio: _revisarCodigo,
            ayuda: _existente != null ? 'Ya existe: ${_existente!.descripcion}' : 'Puede quedar vacío'),
        const SizedBox(height: 12),
        campo('Descripción', _desc),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: campo('Precio de venta (\$)', _precio, numero: true)),
          const SizedBox(width: 12),
          Expanded(child: campo('Costo (\$)', _costo, numero: true, ayuda: 'Opcional')),
          const SizedBox(width: 12),
          Expanded(child: campo('Existencia', _existencia, numero: true, ayuda: 'Opcional')),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          const Text('Se vende:  ', style: TextStyle(fontWeight: FontWeight.w600)),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'unidad', label: Text('Por pieza'), icon: Icon(Icons.inventory_2_outlined)),
              ButtonSegment(value: 'granel', label: Text('A granel (kilo)'), icon: Icon(Icons.scale_outlined)),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => setState(() => _tipo = s.first),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DropdownButtonFormField<String?>(
              value: _dep,
              decoration: const InputDecoration(labelText: 'Departamento'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin departamento')),
                for (final d in _deps) DropdownMenuItem(value: d.id, child: Text(d.nombre, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _dep = v),
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Row(children: [
          TextButton.icon(
            onPressed: () async {
              final navegador = Navigator.of(context);
              navegador.pop();
              await editarProducto(navegador.context, null);
              avisarCambio();
            },
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Más opciones (mayoreo, impuestos, paquete…)'),
          ),
          const Spacer(),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _guardar,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar producto  (Enter)', style: TextStyle(fontSize: 16)),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ---------------- Eliminar ----------------

class _Eliminar extends StatefulWidget {
  const _Eliminar();

  @override
  State<_Eliminar> createState() => _EliminarState();
}

class _EliminarState extends State<_Eliminar> {
  final _buscar = TextEditingController();
  List<Producto> _lista = [];
  int _sel = -1;

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _cargar(String t) async {
    if (t.trim().length < 2) {
      setState(() {
        _lista = [];
        _sel = -1;
      });
      return;
    }
    final porCodigo = await repos.productos.porCodigo(t.trim());
    final l = porCodigo != null ? [porCodigo] : await repos.productos.buscar(t, limite: 40);
    if (mounted) {
      setState(() {
        _lista = l;
        _sel = l.isEmpty ? -1 : 0;
      });
    }
  }

  Future<void> _eliminar() async {
    if (_sel < 0 || _sel >= _lista.length) return aviso(context, 'Busca y elige el producto que quieres eliminar.');
    final p = _lista[_sel];
    if (!await confirmar(context, 'Eliminar producto', '¿Eliminar "${p.descripcion}"? Sus ventas pasadas se conservan.',
        si: 'Eliminar', peligro: true)) {
      return;
    }
    await repos.productos.eliminar(p.id);
    avisarCambio();
    if (!mounted) return;
    aviso(context, 'Se eliminó "${p.descripcion}".');
    _buscar.clear();
    _cargar('');
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.delete): _eliminar,
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => setState(() => _sel = (_sel + 1).clamp(0, _lista.length - 1)),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => setState(() => _sel = (_sel - 1).clamp(0, _lista.length - 1)),
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _buscar,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Escanea el código o escribe el nombre',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: _cargar,
            onSubmitted: (_) => _eliminar(),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: ExEstilo.linea)),
              clipBehavior: Clip.antiAlias,
              child: _lista.isEmpty
                  ? const Center(child: Text('Escribe al menos 2 letras o escanea el producto', style: TextStyle(color: ExColor.texto2)))
                  : ListView.builder(
                      itemCount: _lista.length,
                      itemBuilder: (_, i) {
                        final p = _lista[i];
                        final sel = i == _sel;
                        return Material(
                          color: sel ? Tono.coral.fondo : Colors.white,
                          child: InkWell(
                            onTap: () => setState(() => _sel = i),
                            onDoubleTap: () {
                              setState(() => _sel = i);
                              _eliminar();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: ExEstilo.lineaFila))),
                              child: Row(children: [
                                AvatarColor(p.departamentoNombre ?? 'Sin departamento', tamano: 34, redondo: false),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(p.descripcion, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                    Text('${p.codigo.isEmpty ? 'Sin código' : p.codigo} · ${p.departamentoNombre ?? 'Sin departamento'}',
                                        style: const TextStyle(fontSize: 12, color: ExEstilo.texto2)),
                                  ]),
                                ),
                                Text(formatoPesos(p.precioCentavos), style: const TextStyle(fontWeight: FontWeight.w700)),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            const Text('Elige con ↑ ↓ y elimina con Supr o Enter', style: TextStyle(color: ExColor.texto2)),
            const Spacer(),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Tono.coral.color),
                onPressed: _eliminar,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Eliminar producto', style: TextStyle(fontSize: 16)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}
