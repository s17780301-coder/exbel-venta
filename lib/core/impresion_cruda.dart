import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Manda bytes tal cual (ESC/POS) a una impresora de Windows por su nombre,
/// usando winspool. No necesita que la impresora esté compartida.
final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

typedef _OpenC = Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>);
typedef _OpenD = int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>);
typedef _StartDocC = Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>);
typedef _StartDocD = int Function(int, int, Pointer<_DocInfo1>);
typedef _HC = Int32 Function(IntPtr);
typedef _HD = int Function(int);
typedef _WriteC = Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _WriteD = int Function(int, Pointer<Uint8>, int, Pointer<Uint32>);

/// Regresa null si salió bien, o el mensaje de error.
String? imprimirCrudo(String impresora, List<int> datos, {String documento = 'exBel'}) {
  if (!Platform.isWindows) return 'Solo funciona en Windows.';
  if (impresora.trim().isEmpty) return 'No hay impresora de tickets elegida.';
  final lib = DynamicLibrary.open('winspool.drv');
  final open = lib.lookupFunction<_OpenC, _OpenD>('OpenPrinterW');
  final startDoc = lib.lookupFunction<_StartDocC, _StartDocD>('StartDocPrinterW');
  final startPage = lib.lookupFunction<_HC, _HD>('StartPagePrinter');
  final write = lib.lookupFunction<_WriteC, _WriteD>('WritePrinter');
  final endPage = lib.lookupFunction<_HC, _HD>('EndPagePrinter');
  final endDoc = lib.lookupFunction<_HC, _HD>('EndDocPrinter');
  final close = lib.lookupFunction<_HC, _HD>('ClosePrinter');

  final nombre = impresora.toNativeUtf16();
  final h = calloc<IntPtr>();
  final info = calloc<_DocInfo1>();
  final doc = documento.toNativeUtf16();
  final tipo = 'RAW'.toNativeUtf16();
  final buf = calloc<Uint8>(datos.length);
  final escritos = calloc<Uint32>();
  try {
    if (open(nombre, h, nullptr) == 0) return 'Windows no encontró la impresora "$impresora".';
    try {
      info.ref
        ..pDocName = doc
        ..pOutputFile = nullptr
        ..pDatatype = tipo;
      if (startDoc(h.value, 1, info) == 0) return 'La impresora "$impresora" no aceptó la orden.';
      startPage(h.value);
      buf.asTypedList(datos.length).setAll(0, datos);
      final ok = write(h.value, buf, datos.length, escritos);
      endPage(h.value);
      endDoc(h.value);
      if (ok == 0) return 'No se pudo mandar la orden a "$impresora".';
      return null;
    } finally {
      close(h.value);
    }
  } finally {
    calloc
      ..free(nombre)
      ..free(h)
      ..free(info)
      ..free(doc)
      ..free(tipo)
      ..free(buf)
      ..free(escritos);
  }
}
