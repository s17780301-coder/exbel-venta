import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Cómo habla la báscula por el puerto COM (USB o serial).
class ConfigBascula {
  const ConfigBascula({required this.puerto, this.baudios = 9600, this.formato = '8N1', this.pedido = 'P'});
  final String puerto;
  final int baudios;

  /// '8N1' (casi todas) o '7E1' (Toledo y algunas antiguas).
  final String formato;

  /// Lo que se le manda para que diga el peso: 'P', 'W', 'ENQ' o '' (manda sola).
  final String pedido;

  bool get valida => puerto.trim().isNotEmpty;

  @override
  String toString() => '$puerto · $baudios · $formato · ${pedido.isEmpty ? 'continuo' : pedido}';
}

/// Configuraciones que se prueban al buscar la báscula, de la más común a
/// la menos común (Torrey, Rhino, Noval, CAS, Toledo, Ohaus…).
const configsComunes = <(int, String, String)>[
  (9600, '8N1', 'P'),
  (9600, '8N1', ''),
  (9600, '8N1', 'W'),
  (9600, '8N1', 'ENQ'),
  (9600, '7E1', 'W'),
  (4800, '8N1', 'P'),
  (4800, '8N1', ''),
  (2400, '8N1', 'P'),
  (2400, '8N1', ''),
  (19200, '8N1', 'P'),
  (19200, '8N1', ''),
  (9600, '7E1', ''),
  (2400, '7E1', 'W'),
  (1200, '8N1', 'P'),
];

/// Saca el peso en kg del texto que manda la báscula.
/// Ejemplos: "  0.250kg", "ST,GS,+  1.235kg", "\x0200250\r", "W: 0,500 kg".
double? leerPesoTexto(String t) {
  final s = t.replaceAll(',', '.');
  final conPunto = RegExp(r'-?\d+\.\d+').allMatches(s).toList();
  if (conPunto.isNotEmpty) {
    var v = double.tryParse(conPunto.last.group(0)!);
    if (v == null) return null;
    final despues = s.substring(conPunto.last.end).trimLeft().toLowerCase();
    if (despues.startsWith('lb')) v = v * 0.45359237;
    if (despues.startsWith('g') && !despues.startsWith('gs')) v = v / 1000;
    if (despues.startsWith('oz')) v = v * 0.0283495;
    return (v * 1000).round() / 1000;
  }
  // Sin punto (Toledo): 5 dígitos = gramos.
  final enteros = RegExp(r'\d{4,6}').allMatches(s).toList();
  if (enteros.isNotEmpty) return int.parse(enteros.last.group(0)!) / 1000;
  return null;
}

const _script = r'''
param([string]$modo, [string]$puerto, [int]$baudios, [string]$formato, [string]$pedido, [int]$padre)
$ErrorActionPreference = 'Stop'
function Abrir($pt, $b, $f) {
  $par = 'None'; $bits = 8
  if ($f -eq '7E1') { $par = 'Even'; $bits = 7 }
  $sp = New-Object System.IO.Ports.SerialPort $pt, $b, $par, $bits, 'One'
  $sp.ReadTimeout = 400; $sp.WriteTimeout = 400; $sp.DtrEnable = $true; $sp.RtsEnable = $true
  $sp.Open(); return $sp
}
function Pedir($sp, $q) {
  $sp.DiscardInBuffer()
  if ($q -eq 'ENQ') { $sp.Write([string][char]5) } elseif ($q -ne '') { $sp.Write($q) }
  Start-Sleep -Milliseconds 300
  $s = $sp.ReadExisting()
  return ($s -replace '[\x00-\x1F]', ' ')
}
function Vivo { if ($padre -gt 0 -and -not (Get-Process -Id $padre -ErrorAction SilentlyContinue)) { exit } }
if ($modo -eq 'puertos') {
  try {
    Get-CimInstance Win32_PnPEntity | Where-Object { $_.Name -match '\((COM\d+)\)' } | ForEach-Object {
      $c = [regex]::Match($_.Name, 'COM\d+').Value; [Console]::Out.WriteLine("P:$c|$($_.Name)") }
  } catch {}
  foreach ($c in [System.IO.Ports.SerialPort]::GetPortNames()) { [Console]::Out.WriteLine("P:$c|$c") }
  exit
}
if ($modo -eq 'buscar') {
  $configs = $formato -split ';'
  foreach ($pt in ($puerto -split ';')) {
    foreach ($cf in $configs) {
      Vivo
      $x = $cf -split ','
      [Console]::Out.WriteLine("T:$pt|$cf"); [Console]::Out.Flush()
      try {
        $sp = Abrir $pt ([int]$x[0]) $x[1]
        try {
          $s = ''
          for ($i = 0; $i -lt 3 -and $s.Trim() -eq ''; $i++) { $s = Pedir $sp $x[2] }
          if ($s -match '\d') { [Console]::Out.WriteLine("OK:$pt|$cf|$s"); [Console]::Out.Flush(); $sp.Close(); exit }
        } finally { if ($sp.IsOpen) { $sp.Close() } }
      } catch {
        [Console]::Out.WriteLine("E:$pt|$($_.Exception.Message)"); [Console]::Out.Flush()
        break
      }
    }
  }
  [Console]::Out.WriteLine('FIN'); exit
}
# modo leer: pesa sin parar
while ($true) {
  Vivo
  try {
    $sp = Abrir $puerto $baudios $formato
    while ($true) {
      Vivo
      $s = Pedir $sp $pedido
      [Console]::Out.WriteLine("L:$s"); [Console]::Out.Flush()
      Start-Sleep -Milliseconds 120
    }
  } catch {
    [Console]::Out.WriteLine("E:$($_.Exception.Message)"); [Console]::Out.Flush()
    try { if ($sp -and $sp.IsOpen) { $sp.Close() } } catch {}
    Start-Sleep -Milliseconds 1500
  }
}
''';

Future<String> _rutaScript() async {
  final f = File(p.join(Directory.systemTemp.path, 'exbel_bascula_v1.ps1'));
  if (!await f.exists() || await f.readAsString() != _script) await f.writeAsString(_script);
  return f.path;
}

Future<Process> _correr(List<String> args) async => Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      await _rutaScript(),
      ...args,
    ]);

/// Puertos COM de la computadora: (COM3, "USB-SERIAL CH340 (COM3)").
Future<List<(String, String)>> puertosCom() async {
  if (!Platform.isWindows) return [];
  try {
    final pr = await _correr(['puertos', '', '0', '', '', '0']);
    final salida = await pr.stdout.transform(utf8.decoder).join().timeout(const Duration(seconds: 20));
    final r = <(String, String)>[];
    for (final l in const LineSplitter().convert(salida)) {
      if (!l.startsWith('P:')) continue;
      final x = l.substring(2).split('|');
      if (!r.any((e) => e.$1 == x[0])) r.add((x[0], x.length > 1 ? x[1] : x[0]));
    }
    r.sort((a, b) => a.$1.compareTo(b.$1));
    return r;
  } catch (_) {
    return [];
  }
}

/// Prueba puertos y configuraciones hasta que una báscula conteste.
Future<(ConfigBascula, String)?> buscarBascula(List<String> puertos, {void Function(String)? avance}) async {
  if (!Platform.isWindows || puertos.isEmpty) return null;
  final configs = configsComunes.map((c) => '${c.$1},${c.$2},${c.$3}').join(';');
  final pr = await _correr(['buscar', puertos.join(';'), '0', configs, '', '$pid']);
  (ConfigBascula, String)? hallada;
  await for (final l in pr.stdout.transform(utf8.decoder).transform(const LineSplitter())) {
    if (l.startsWith('T:')) {
      final x = l.substring(2).split('|');
      avance?.call('Probando ${x[0]} (${x[1].replaceAll(',', ' · ')})…');
    } else if (l.startsWith('E:')) {
      final x = l.substring(2).split('|');
      avance?.call('${x[0]}: ${x.length > 1 ? x[1] : ''}');
    } else if (l.startsWith('OK:')) {
      final x = l.substring(3).split('|');
      final c = x[1].split(',');
      hallada = (
        ConfigBascula(puerto: x[0], baudios: int.parse(c[0]), formato: c[1], pedido: c.length > 2 ? c[2] : ''),
        x.length > 2 ? x.sublist(2).join('|').trim() : ''
      );
    }
  }
  return hallada;
}

/// Lectura continua del peso mientras alguien lo necesita.
class LectorBascula {
  LectorBascula._();
  static final instancia = LectorBascula._();

  final peso = ValueNotifier<double?>(null);
  final estado = ValueNotifier<String>('');
  Process? _proc;
  ConfigBascula? _config;
  int _usuarios = 0;
  Timer? _apagar;

  /// Empieza a leer (o sigue leyendo). Llamar a [soltar] al terminar.
  Future<void> usar(ConfigBascula c) async {
    _usuarios++;
    _apagar?.cancel();
    if (_proc != null && _config.toString() == c.toString()) return;
    await _detener();
    if (!Platform.isWindows || !c.valida) return;
    _config = c;
    peso.value = null;
    estado.value = 'Conectando con la báscula…';
    try {
      final pr = await _correr(['leer', c.puerto, '${c.baudios}', c.formato, c.pedido, '$pid']);
      _proc = pr;
      pr.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
        if (l.startsWith('L:')) {
          final v = leerPesoTexto(l.substring(2));
          if (v != null) {
            peso.value = v;
            estado.value = '';
          } else if (l.substring(2).trim().isEmpty) {
            estado.value = 'La báscula no contesta';
          }
        } else if (l.startsWith('E:')) {
          peso.value = null;
          estado.value = l.contains('denied') || l.contains('denegado')
              ? '${c.puerto} está ocupado por otro programa'
              : 'No se pudo abrir ${c.puerto}';
        }
      });
      unawaited(pr.exitCode.then((_) {
        if (identical(_proc, pr)) _proc = null;
      }));
    } catch (_) {
      estado.value = 'No se pudo iniciar la lectura de la báscula';
    }
  }

  /// Se deja prendida unos segundos por si se pesa otro producto enseguida.
  void soltar() {
    _usuarios = (_usuarios - 1).clamp(0, 999);
    if (_usuarios > 0) return;
    _apagar?.cancel();
    _apagar = Timer(const Duration(minutes: 2), _detener);
  }

  Future<void> _detener() async {
    _proc?.kill();
    _proc = null;
    _config = null;
  }
}
