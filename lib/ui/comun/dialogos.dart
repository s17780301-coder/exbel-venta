import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/db.dart';
import '../../core/errores.dart';
import '../../core/formato.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../sesion.dart';
import '../tema/tema.dart';

void aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto), duration: const Duration(seconds: 3)));
}

void avisoError(BuildContext context, Object error) =>
    aviso(context, error is ErrorNegocio ? error.mensaje : 'Ocurrió un error: $error');

/// Ejecuta una acción mostrando el error del negocio si falla.
Future<bool> intentar(BuildContext context, Future<void> Function() accion) async {
  try {
    await accion();
    return true;
  } catch (e) {
    if (context.mounted) avisoError(context, e);
    return false;
  }
}

Future<bool> confirmar(BuildContext context, String titulo, String mensaje,
    {String si = 'Sí', String no = 'No', bool peligro = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: SizedBox(width: 420, child: Text(mensaje)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
        FilledButton(
          autofocus: true,
          style: peligro ? FilledButton.styleFrom(backgroundColor: ExColor.rojo) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(si),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> pedirTexto(BuildContext context, String titulo,
    {String etiqueta = '', String inicial = '', String? ayuda, bool clave = false}) {
  return showDialog<String>(
    context: context,
    builder: (c) => _DialogoTexto(titulo: titulo, etiqueta: etiqueta, inicial: inicial, ayuda: ayuda, clave: clave),
  );
}

class _DialogoTexto extends StatefulWidget {
  const _DialogoTexto({required this.titulo, required this.etiqueta, required this.inicial, this.ayuda, this.clave = false});
  final String titulo;
  final String etiqueta;
  final String inicial;
  final String? ayuda;
  final bool clave;

  @override
  State<_DialogoTexto> createState() => _DialogoTextoState();
}

class _DialogoTextoState extends State<_DialogoTexto> {
  late final _c = TextEditingController(text: widget.inicial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.inicial.length);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _c,
          autofocus: true,
          obscureText: widget.clave,
          decoration: InputDecoration(labelText: widget.etiqueta, helperText: widget.ayuda),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Aceptar')),
      ],
    );
  }
}

/// Pide un número (cantidad o dinero). Con `pesos` regresa centavos.
Future<double?> pedirCantidad(BuildContext context, String titulo,
    {String etiqueta = 'Cantidad', double? inicial, String? ayuda}) async {
  final t = await pedirTexto(context, titulo,
      etiqueta: etiqueta, inicial: inicial == null ? '' : formatoCantidad(inicial), ayuda: ayuda);
  if (t == null) return null;
  final v = leerCantidad(t);
  if (v == null && context.mounted) aviso(context, 'Escribe un número válido.');
  return v;
}

Future<int?> pedirMonto(BuildContext context, String titulo,
    {String etiqueta = 'Cantidad en pesos', int? inicial, String? ayuda}) async {
  final t = await pedirTexto(context, titulo,
      etiqueta: etiqueta, inicial: inicial == null ? '' : (inicial / 100).toStringAsFixed(2), ayuda: ayuda);
  if (t == null) return null;
  final v = leerPesos(t);
  if (v == null && context.mounted) aviso(context, 'Escribe una cantidad válida.');
  return v;
}

/// Si el cajero no tiene el permiso, pide la contraseña de alguien que sí.
Future<bool> autorizar(BuildContext context, String permiso) async {
  if (sesion.cajero?.puede(permiso) ?? false) return true;
  final clave = await pedirTexto(context, 'Se necesita autorización',
      etiqueta: 'Contraseña del supervisor',
      ayuda: Permiso.todos[permiso] ?? '',
      clave: true);
  if (clave == null || clave.isEmpty) return false;
  final ok = await repos.cajeros.autorizar(clave, permiso);
  if (ok == null && context.mounted) aviso(context, 'Contraseña incorrecta o sin permiso.');
  return ok != null;
}

/// Nombre y logotipo de la tienda.
Future<void> editarNegocio(BuildContext context) async {
  final r = await showDialog<(String, String)>(
    context: context,
    builder: (_) => _DialogoNegocio(
      nombre: repos.ajustes.texto(Ajuste.nombreNegocio),
      logo: repos.ajustes.texto(Ajuste.logoNegocio),
    ),
  );
  if (r == null) return;
  if (r.$1.trim().isNotEmpty) await repos.ajustes.guardar(Ajuste.nombreNegocio, r.$1.trim());
  await repos.ajustes.guardar(Ajuste.logoNegocio, r.$2);
  avisarCambio();
}

class _DialogoNegocio extends StatefulWidget {
  const _DialogoNegocio({required this.nombre, required this.logo});
  final String nombre;
  final String logo;

  @override
  State<_DialogoNegocio> createState() => _DialogoNegocioState();
}

class _DialogoNegocioState extends State<_DialogoNegocio> {
  late final _ctrl = TextEditingController(text: widget.nombre);
  late String _logo = widget.logo;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _elegir() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final origen = r?.files.single.path;
    if (origen == null) return;
    try {
      final dir = await AppDb.carpeta();
      final destino = p.join(dir.path, 'logo_${DateTime.now().millisecondsSinceEpoch}${p.extension(origen).toLowerCase()}');
      await File(origen).copy(destino);
      if (mounted) setState(() => _logo = destino);
    } catch (e) {
      if (mounted) aviso(context, 'No se pudo usar esa imagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final archivo = _logo.isEmpty ? null : File(_logo);
    final hay = archivo != null && archivo.existsSync();
    return AlertDialog(
      title: const Text('Tu tienda'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Nombre de la tienda', helperText: 'Aparece arriba y en los tickets'),
          ),
          const SizedBox(height: 20),
          const Text('Logotipo (opcional)', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: ExColor.concreto,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ExColor.linea),
              ),
              clipBehavior: Clip.antiAlias,
              child: hay
                  ? Image.file(archivo, fit: BoxFit.contain)
                  : const Center(child: Text('Sin\nimagen', textAlign: TextAlign.center, style: TextStyle(fontSize: 11))),
            ),
            const SizedBox(width: 16),
            OutlinedButton(onPressed: _elegir, child: Text(hay ? 'Cambiar imagen' : 'Elegir imagen')),
            if (hay) TextButton(onPressed: () => setState(() => _logo = ''), child: const Text('Quitar')),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, (_ctrl.text, _logo)), child: const Text('Guardar')),
      ],
    );
  }
}

/// Campo de texto para dinero o cantidades.
class CampoNumero extends StatelessWidget {
  const CampoNumero({super.key, required this.controller, required this.etiqueta,
      this.ayuda, this.autofocus = false, this.onSubmitted, this.onChanged, this.focusNode, this.ancho});
  final TextEditingController controller;
  final String etiqueta;
  final String? ayuda;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final double? ancho;

  @override
  Widget build(BuildContext context) {
    final campo = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,$-]'))],
      decoration: InputDecoration(labelText: etiqueta, helperText: ayuda),
      onSubmitted: onSubmitted,
      onChanged: onChanged,
    );
    return ancho == null ? campo : SizedBox(width: ancho, child: campo);
  }
}

/// Encabezado de tabla (cuadrado, oscuro).
class EncabezadoTabla extends StatelessWidget {
  const EncabezadoTabla(this.columnas, {super.key, this.tamano = 13});
  final double tamano;

  /// (texto, flex, alineado a la derecha)
  final List<(String, int, bool)> columnas;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: ExColor.tinta,
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: tamano * 0.75),
      child: Row(children: [
        for (final c in columnas)
          Expanded(
            flex: c.$2,
            child: Text(c.$1,
                textAlign: c.$3 ? TextAlign.right : TextAlign.left,
                style: TextStyle(color: ExColor.concreto, fontWeight: FontWeight.w600, fontSize: tamano)),
          ),
      ]),
    );
  }
}

/// Fila de tabla.
/// Fila de tabla. El clic responde al instante: el doble clic se detecta a
/// mano (con InkWell.onDoubleTap cada clic esperaba ~0.3 s).
class FilaTabla extends StatefulWidget {
  const FilaTabla(this.celdas, {super.key, this.seleccionada = false, this.onTap, this.onDoubleTap, this.color, this.par = false});
  final List<(Widget, int, bool)> celdas;
  final bool seleccionada;
  final bool par;
  final Color? color;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  State<FilaTabla> createState() => _FilaTablaState();
}

class _FilaTablaState extends State<FilaTabla> {
  DateTime? _ultimo;

  void _toque() {
    final ahora = DateTime.now();
    final doble = _ultimo != null && ahora.difference(_ultimo!) < const Duration(milliseconds: 400);
    _ultimo = doble ? null : ahora;
    if (doble && widget.onDoubleTap != null) {
      widget.onDoubleTap!();
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return Material(
      color: w.seleccionada ? ExColor.lavanda : (w.color ?? (w.par ? ExColor.concreto : ExColor.blanco)),
      shape: const Border(bottom: BorderSide(color: ExColor.linea)),
      child: InkWell(
        onTap: w.onTap == null && w.onDoubleTap == null ? null : _toque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(children: [
            for (final c in w.celdas)
              Expanded(flex: c.$2, child: Align(alignment: c.$3 ? Alignment.centerRight : Alignment.centerLeft, child: c.$1)),
          ]),
        ),
      ),
    );
  }
}

/// Texto simple para celdas.
Widget celda(String t, {bool negrita = false, Color? color, bool mono = false, double tamano = 14}) => Text(
      t,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: mono
          ? ExTexto.mono(tamano - 1, color: color, peso: negrita ? FontWeight.w700 : FontWeight.w500)
          : TextStyle(fontSize: tamano, fontWeight: negrita ? FontWeight.w700 : FontWeight.w400, color: color),
    );
