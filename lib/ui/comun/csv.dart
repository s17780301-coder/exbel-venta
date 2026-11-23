import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'dialogos.dart';

/// Texto CSV que Excel abre bien (con BOM UTF-8).
String aCsv(List<List<String>> filas) {
  String campo(String s) => s.contains(RegExp(r'[",\n\r]')) ? '"${s.replaceAll('"', '""')}"' : s;
  return filas.map((f) => f.map(campo).join(',')).join('\r\n');
}

List<List<String>> leerCsv(String texto) {
  if (texto.startsWith('﻿')) texto = texto.substring(1);
  final sep = texto.split('\n').first.split(';').length > texto.split('\n').first.split(',').length ? ';' : ',';
  final filas = <List<String>>[];
  var fila = <String>[];
  final campo = StringBuffer();
  var comillas = false;
  for (var i = 0; i < texto.length; i++) {
    final c = texto[i];
    if (comillas) {
      if (c == '"') {
        if (i + 1 < texto.length && texto[i + 1] == '"') {
          campo.write('"');
          i++;
        } else {
          comillas = false;
        }
      } else {
        campo.write(c);
      }
    } else if (c == '"') {
      comillas = true;
    } else if (c == sep) {
      fila.add(campo.toString());
      campo.clear();
    } else if (c == '\n') {
      fila.add(campo.toString());
      campo.clear();
      if (fila.any((x) => x.trim().isNotEmpty)) filas.add(fila);
      fila = <String>[];
    } else if (c != '\r') {
      campo.write(c);
    }
  }
  fila.add(campo.toString());
  if (fila.any((x) => x.trim().isNotEmpty)) filas.add(fila);
  return filas;
}

Future<void> guardarCsv(BuildContext context, String nombre, List<List<String>> filas) async {
  try {
    final hoy = DateTime.now();
    final ruta = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar como',
      fileName: '$nombre-${hoy.year}${hoy.month.toString().padLeft(2, '0')}${hoy.day.toString().padLeft(2, '0')}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (ruta == null) return;
    final destino = ruta.toLowerCase().endsWith('.csv') ? ruta : '$ruta.csv';
    await File(destino).writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(aCsv(filas))]);
    if (context.mounted) aviso(context, 'Guardado en $destino');
  } catch (e) {
    if (context.mounted) aviso(context, 'No se pudo guardar: $e');
  }
}

Future<List<List<String>>?> abrirCsv(BuildContext context) async {
  try {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv', 'txt']);
    final ruta = r?.files.single.path;
    if (ruta == null) return null;
    final bytes = await File(ruta).readAsBytes();
    String texto;
    try {
      texto = utf8.decode(bytes);
    } catch (_) {
      texto = latin1.decode(bytes);
    }
    return leerCsv(texto);
  } catch (e) {
    if (context.mounted) aviso(context, 'No se pudo leer el archivo: $e');
    return null;
  }
}
