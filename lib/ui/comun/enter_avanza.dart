import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// En todo el sistema: Enter en un campo de texto pasa al siguiente campo.
/// - Si el campo tiene su propia acción con Enter (buscar, agregar, cobrar),
///   se respeta.
/// - Campos de varias líneas: Enter hace renglón nuevo.
/// - En el último campo: si el formulario está dentro de [EnterGuarda], guarda.
class EnterAvanza extends StatelessWidget {
  const EnterAvanza({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _tecla, child: child);
}

/// Marca un formulario: Enter en su último campo ejecuta [onGuardar].
class EnterGuarda extends InheritedWidget {
  const EnterGuarda({super.key, required this.onGuardar, required super.child});
  final VoidCallback onGuardar;

  @override
  bool updateShouldNotify(EnterGuarda old) => false;
}

EditableText? _editable(FocusNode n) {
  final c = n.context;
  if (c == null) return null;
  if (c.widget is EditableText) return c.widget as EditableText;
  return c.findAncestorWidgetOfExactType<EditableText>();
}

bool _esCampo(FocusNode n) {
  final e = _editable(n);
  return e != null && e.maxLines == 1 && !e.readOnly && n.canRequestFocus && n.context != null;
}

KeyEventResult _tecla(FocusNode _, KeyEvent e) {
  if (e is! KeyDownEvent) return KeyEventResult.ignored;
  if (e.logicalKey != LogicalKeyboardKey.enter && e.logicalKey != LogicalKeyboardKey.numpadEnter) {
    return KeyEventResult.ignored;
  }
  final k = HardwareKeyboard.instance;
  if (k.isShiftPressed || k.isControlPressed || k.isAltPressed) return KeyEventResult.ignored;
  final foco = FocusManager.instance.primaryFocus;
  if (foco == null || !_esCampo(foco)) return KeyEventResult.ignored;
  final ed = _editable(foco)!;
  // El campo tiene su propia acción con Enter: se respeta.
  if (ed.onSubmitted != null || ed.onEditingComplete != null) return KeyEventResult.ignored;
  final ctx = foco.context!;
  final ambito = foco.nearestScope;
  if (ambito == null) return KeyEventResult.ignored;
  final campos = ambito.traversalDescendants.where(_esCampo).toList();
  final politica = FocusTraversalGroup.maybeOf(ctx) ?? ReadingOrderTraversalPolicy();
  final orden = politica.sortDescendants(campos, foco).toList();
  final i = orden.indexOf(foco);
  if (i >= 0 && i < orden.length - 1) {
    final sig = orden[i + 1];
    sig.requestFocus();
    // Selecciona lo que tenga para escribir encima.
    final ed2 = _editable(sig);
    final t = ed2?.controller;
    if (t != null) t.selection = TextSelection(baseOffset: 0, extentOffset: t.text.length);
    return KeyEventResult.handled;
  }
  // Último campo: guardar si el formulario lo permite.
  final g = ctx.findAncestorWidgetOfExactType<EnterGuarda>();
  if (g != null) {
    g.onGuardar();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
