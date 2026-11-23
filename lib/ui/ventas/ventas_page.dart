import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cajon.dart';
import '../../core/errores.dart';
import '../../core/formato.dart';
import '../../core/tickets.dart';
import '../../data/ajustes_repo.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/impresion.dart';
import '../principal.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../comun/buscador_universal.dart';
import 'buscar_producto.dart';
import 'cobro_dialogo.dart';
import 'dialogos_venta.dart';
import 'ventas_dia.dart';

/// Un ticket en curso. Se pueden tener varios (pendientes).
class Ticket {
  Ticket(this.nombre);
  String nombre;
  final renglones = <Renglon>[];
  Cliente? cliente;
  int seleccion = -1;

  int get totalCentavos => renglones.fold(0, (s, r) => s + r.importeCentavos);
  double get piezas => renglones.fold(0.0, (s, r) => s + r.cantidad);
  int get ahorroCentavos => renglones.fold(0, (s, r) => s + r.descuentoCentavos);
}

class VentasPage extends StatefulWidget {
  const VentasPage({super.key});

  @override
  State<VentasPage> createState() => _VentasPageState();
}

class _VentasPageState extends State<VentasPage> {
  final _tickets = <Ticket>[Ticket('Ticket 1')];
  int _actual = 0;
  int _consecutivo = 1;
  final _codigo = TextEditingController();
  final _focoCodigo = FocusNode();
  final _scroll = ScrollController();
  List<Producto> _favoritos = [];
  Venta? _ultima;
  bool _ocupado = false;

  Ticket get _t => _tickets[_actual];
  Timer? _guardado;

  static const _claveTickets = 'tickets_pendientes';

  @override
  void initState() {
    super.initState();
    teclasVentas.addListener(_alTeclear);
    cambiosDatos.addListener(_cargarFavoritos);
    codigoVentasVacio = () => _codigo.text.isEmpty;
    _cargarFavoritos();
    _restaurarTickets();
  }

  /// Cada cambio guarda los tickets abiertos: si se cierra el programa o se
  /// va la luz, al volver siguen ahí.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _guardado?.cancel();
    _guardado = Timer(const Duration(milliseconds: 400), _guardarTickets);
  }

  Future<void> _guardarTickets() async {
    final datos = {
      'consecutivo': _consecutivo,
      'actual': _actual,
      'tickets': [
        for (final t in _tickets)
          {
            'nombre': t.nombre,
            'cliente': t.cliente?.id,
            'renglones': [
              for (final r in t.renglones)
                {
                  'p': r.producto?.id,
                  'cod': r.codigo,
                  'd': r.descripcion,
                  'c': r.cantidad,
                  'pr': r.precioNormalCentavos,
                  'pm': r.precioManualCentavos,
                  'm': r.mayoreoManual,
                },
            ],
          },
      ],
    };
    try {
      await repos.ajustes.guardar(_claveTickets, jsonEncode(datos));
    } catch (_) {}
  }

  Future<void> _restaurarTickets() async {
    final texto = repos.ajustes.texto(_claveTickets);
    if (texto.isEmpty) return;
    try {
      final d = jsonDecode(texto) as Map<String, dynamic>;
      final lista = <Ticket>[];
      for (final tm in d['tickets'] as List) {
        final tk = Ticket(tm['nombre'] as String);
        final cid = tm['cliente'] as String?;
        if (cid != null) tk.cliente = await repos.clientes.porId(cid);
        for (final rm in tm['renglones'] as List) {
          final pid = rm['p'] as String?;
          final p = pid == null ? null : await repos.productos.porId(pid);
          final cant = (rm['c'] as num).toDouble();
          final r = p != null && p.activo
              ? Renglon.deProducto(p, cantidad: cant, promocion: await repos.productos.promocionDe(p.id))
              : Renglon(
                  descripcion: rm['d'] as String,
                  codigo: (rm['cod'] as String?) ?? '',
                  cantidad: cant,
                  precioNormalCentavos: rm['pr'] as int,
                );
          r.precioManualCentavos = rm['pm'] as int?;
          r.mayoreoManual = rm['m'] == true;
          tk.renglones.add(r);
        }
        lista.add(tk);
      }
      if (lista.isEmpty || !mounted) return;
      setState(() {
        _tickets
          ..clear()
          ..addAll(lista);
        _consecutivo = (d['consecutivo'] as int?) ?? lista.length;
        _actual = ((d['actual'] as int?) ?? 0).clamp(0, lista.length - 1);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    teclasVentas.removeListener(_alTeclear);
    _guardado?.cancel();
    _guardarTickets();
    cambiosDatos.removeListener(_cargarFavoritos);
    _codigo.dispose();
    _focoCodigo.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargarFavoritos() async {
    final f = await repos.productos.buscar('', soloFavoritos: true, limite: 24);
    if (mounted) setState(() => _favoritos = f);
  }

  void _enfocar() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focoCodigo.requestFocus();
      });

  // ---------------- Teclado ----------------

  void _alTeclear() {
    final e = teclasVentas.value;
    if (e == null || _ocupado) return;
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (k == LogicalKeyboardKey.f12) {
      _cobrar();
    } else if (k == LogicalKeyboardKey.f10 || (ctrl && k == LogicalKeyboardKey.keyF)) {
      _buscar();
    } else if (k == LogicalKeyboardKey.f11) {
      _mayoreo();
    } else if (k == LogicalKeyboardKey.f9) {
      _verificador();
    } else if (k == LogicalKeyboardKey.f7) {
      _movimientoCaja('entrada');
    } else if (k == LogicalKeyboardKey.f8) {
      _movimientoCaja('salida');
    } else if (k == LogicalKeyboardKey.f6) {
      _nuevoTicket();
    } else if (k == LogicalKeyboardKey.f5) {
      _siguienteTicket();
    } else if (k == LogicalKeyboardKey.insert) {
      _varios();
    } else if (k == LogicalKeyboardKey.delete) {
      _borrarSeleccion();
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _mover(-1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _mover(1);
    } else if (k == LogicalKeyboardKey.numpadAdd || k == LogicalKeyboardKey.add) {
      if (_codigo.text.isEmpty) _sumar(1);
    } else if (k == LogicalKeyboardKey.numpadSubtract || k == LogicalKeyboardKey.minus) {
      if (_codigo.text.isEmpty) _sumar(-1);
    } else if (ctrl && k == LogicalKeyboardKey.keyP) {
      _comun();
    } else if (ctrl && k == LogicalKeyboardKey.keyD) {
      _descuento();
    } else if (ctrl && k == LogicalKeyboardKey.keyB) {
      _ventasDelDia();
    }
  }

  void _mover(int d) {
    if (_t.renglones.isEmpty) return;
    setState(() => _t.seleccion = (_t.seleccion + d).clamp(0, _t.renglones.length - 1));
  }

  void _sumar(int d) {
    if ((_t.seleccion < 0 || _t.seleccion >= _t.renglones.length) && _t.renglones.isNotEmpty) {
      _t.seleccion = _t.renglones.length - 1;
    }
    final i = _t.seleccion;
    if (i < 0 || i >= _t.renglones.length) return;
    final r = _t.renglones[i];
    final nueva = r.cantidad + d;
    if (nueva <= 0) return _borrarSeleccion();
    if (!_hayExistencia(r, nueva)) return;
    setState(() => r.cantidad = nueva);
  }

  // ---------------- Agregar productos ----------------

  /// Interpreta lo que se escribió: "3*7501…", código de báscula o código.
  Future<void> _capturar(String texto) async {
    texto = texto.trim();
    _codigo.clear();
    if (texto.isEmpty) {
      _enfocar();
      return;
    }
    double? cantidad;
    final estrella = texto.indexOf('*');
    if (estrella > 0) {
      cantidad = leerCantidad(texto.substring(0, estrella));
      texto = texto.substring(estrella + 1).trim();
      if (cantidad == null || cantidad <= 0) {
        aviso(context, 'La cantidad antes del * no es válida.');
        return _enfocar();
      }
    }
    var p = await repos.productos.porCodigo(texto);
    if (p == null) {
      final b = await _deBascula(texto);
      if (b != null) {
        p = b.$1;
        cantidad = b.$2;
      }
    }
    if (!mounted) return;
    if (p == null) {
      // No es un código: se busca por descripción.
      final elegido = await buscarProducto(context, texto: texto);
      if (elegido == null) return _enfocar();
      p = elegido;
    }
    await _agregar(p, cantidad: cantidad);
  }

  /// Etiquetas de báscula: prefijo (2 dígitos) + código (5) + peso en gramos
  /// o precio en centavos (5) + verificador.
  Future<(Producto, double)?> _deBascula(String codigo) async {
    final prefijo = repos.ajustes.texto(Ajuste.basculaPrefijo);
    if (prefijo.isEmpty || codigo.length != 13 || !codigo.startsWith(prefijo)) return null;
    final clave = codigo.substring(2, 7);
    final valor = int.tryParse(codigo.substring(7, 12));
    if (valor == null) return null;
    final p = await repos.productos.porCodigo(clave) ??
        await repos.productos.porCodigo(int.tryParse(clave)?.toString() ?? clave);
    if (p == null) return null;
    final porPrecio = repos.ajustes.texto(Ajuste.basculaModo) == 'precio';
    final cantidad = porPrecio
        ? (p.precioCentavos <= 0 ? 0.0 : (valor / p.precioCentavos * 1000).round() / 1000)
        : valor / 1000;
    return (p, cantidad);
  }

  bool _hayExistencia(Renglon r, double cantidad) {
    if (repos.ajustes.si(Ajuste.venderSinExistencia)) return true;
    final p = r.producto;
    if (p == null || !p.usaInventario || p.esKit) return true;
    final enOtros = _t.renglones.where((x) => x != r && x.producto?.id == p.id).fold<double>(0, (s, x) => s + x.cantidad);
    if (cantidad + enOtros > p.existencia + 1e-9) {
      aviso(context, 'No hay suficiente "${p.descripcion}". Existencia: ${formatoCantidad(p.existencia)}.');
      return false;
    }
    return true;
  }

  Future<void> _agregar(Producto p, {double? cantidad}) async {
    // Granel sin cantidad: se pregunta por peso o por importe.
    if (cantidad == null && p.esGranel) {
      cantidad = await pedirGranel(context, p);
      if (cantidad == null || cantidad <= 0) return _enfocar();
    }
    cantidad ??= 1;
    final existente = _t.renglones.where((r) => r.producto?.id == p.id && r.precioManualCentavos == null).firstOrNull;
    if (existente != null && !p.esGranel) {
      if (!_hayExistencia(existente, existente.cantidad + cantidad)) return _enfocar();
      setState(() {
        existente.cantidad += cantidad!;
        _t.seleccion = _t.renglones.indexOf(existente);
      });
    } else {
      final promo = await repos.productos.promocionDe(p.id);
      final r = Renglon.deProducto(p, cantidad: cantidad, promocion: promo);
      if (!_hayExistencia(r, cantidad)) return _enfocar();
      setState(() {
        _t.renglones.add(r);
        _t.seleccion = _t.renglones.length - 1;
      });
    }
    _alFinal();
    _enfocar();
  }

  void _alFinal() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          final alto = 52.0 * _t.seleccion;
          _scroll.animateTo(alto.clamp(0.0, _scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
        }
      });

  /// F10: buscador universal. Producto → se agrega; cliente → se asigna al
  /// ticket; folio → se abre la venta.
  Future<void> _buscar() async {
    final h = await buscarUniversal(context, titulo: 'Búsqueda');
    if (!mounted) return;
    final p = h?.producto, c = h?.cliente, v = h?.venta;
    if (p != null) {
      await _agregar(p);
    } else if (c != null) {
      setState(() => _t.cliente = c);
      aviso(context, 'Cliente asignado al ticket: ${c.nombre}');
    } else if (v != null) {
      await mostrarVentasDelDia(context, venta: v);
    }
    _enfocar();
  }

  Future<void> _comun() async {
    if (!repos.ajustes.si(Ajuste.permitirComun)) {
      aviso(context, 'El artículo común está desactivado en Configuración.');
      return;
    }
    final r = await pedirArticuloComun(context);
    if (r != null) {
      setState(() {
        _t.renglones.add(r);
        _t.seleccion = _t.renglones.length - 1;
      });
      _alFinal();
    }
    _enfocar();
  }

  Future<void> _varios() async {
    final precio = await pedirMonto(context, 'Varios', etiqueta: 'Importe (\$)', ayuda: 'Artículo sin código');
    if (precio != null && precio > 0) {
      setState(() {
        _t.renglones.add(Renglon(descripcion: 'Varios', cantidad: 1, precioNormalCentavos: precio));
        _t.seleccion = _t.renglones.length - 1;
      });
      _alFinal();
    }
    _enfocar();
  }

  void _borrarSeleccion() {
    final i = _t.seleccion;
    if (i < 0 || i >= _t.renglones.length) return;
    setState(() {
      _t.renglones.removeAt(i);
      _t.seleccion = _t.renglones.isEmpty ? -1 : (i >= _t.renglones.length ? _t.renglones.length - 1 : i);
    });
    _enfocar();
  }

  void _mayoreo() {
    if (_t.renglones.isEmpty) return;
    final activar = !_t.renglones.any((r) => r.mayoreoManual);
    final conPrecio = _t.renglones.where((r) => r.mayoreoCentavos > 0).length;
    setState(() {
      for (final r in _t.renglones) {
        r.mayoreoManual = activar;
      }
    });
    aviso(context, activar
        ? (conPrecio == 0 ? 'Ningún artículo tiene precio de mayoreo.' : 'Precio de mayoreo aplicado ($conPrecio artículos).')
        : 'Se regresó al precio normal.');
  }

  Future<void> _descuento() async {
    if (_t.renglones.isEmpty) return;
    if (!await autorizar(context, Permiso.descuentos) || !mounted) return _enfocar();
    final sel = _t.seleccion >= 0 && _t.seleccion < _t.renglones.length ? _t.renglones[_t.seleccion] : null;
    final cambio = await pedirDescuento(context, sel, _t.totalCentavos);
    if (cambio == null) return _enfocar();
    setState(() {
      if (cambio.todaLaVenta) {
        for (final r in _t.renglones) {
          r.precioManualCentavos = (r.precioUnitarioCentavos * (1 - cambio.porcentaje / 100)).round();
        }
      } else if (sel != null) {
        sel.precioManualCentavos = cambio.nuevoPrecio ?? (sel.precioUnitarioCentavos * (1 - cambio.porcentaje / 100)).round();
      }
    });
    _enfocar();
  }

  Future<void> _editarRenglon(int i) async {
    final r = _t.renglones[i];
    final c = await pedirCantidad(context, r.descripcion,
        etiqueta: r.producto?.esGranel ?? false ? 'Cantidad (kg / litros)' : 'Cantidad', inicial: r.cantidad);
    if (c == null) return _enfocar();
    if (c <= 0) {
      setState(() => _t.seleccion = i);
      return _borrarSeleccion();
    }
    if (!_hayExistencia(r, c)) return _enfocar();
    setState(() => r.cantidad = c);
    _enfocar();
  }

  // ---------------- Tickets ----------------

  Future<void> _nuevoTicket() async {
    if (_t.renglones.isNotEmpty) {
      final nombre = await pedirTexto(context, 'Dejar ticket pendiente',
          etiqueta: 'Nombre (opcional)', inicial: _t.nombre, ayuda: 'Ej. "Señora de azul". F5 para regresar a él.');
      if (nombre == null) return _enfocar();
      if (nombre.trim().isNotEmpty) _t.nombre = nombre.trim();
    }
    setState(() {
      _consecutivo++;
      _tickets.add(Ticket('Ticket $_consecutivo'));
      _actual = _tickets.length - 1;
    });
    _enfocar();
  }

  void _siguienteTicket() {
    if (_tickets.length < 2) return;
    setState(() => _actual = (_actual + 1) % _tickets.length);
    _enfocar();
  }

  Future<void> _cerrarTicket(int i) async {
    final t = _tickets[i];
    if (t.renglones.isNotEmpty &&
        !await confirmar(context, 'Borrar ticket', '¿Descartar "${t.nombre}" con ${t.renglones.length} artículos?',
            si: 'Descartar', peligro: true)) {
      return;
    }
    setState(() {
      _tickets.removeAt(i);
      if (_tickets.isEmpty) {
        _consecutivo++;
        _tickets.add(Ticket('Ticket $_consecutivo'));
      }
      _actual = _actual.clamp(0, _tickets.length - 1);
    });
    _enfocar();
  }

  Future<void> _elegirCliente() async {
    final c = await elegirCliente(context);
    if (c != null) setState(() => _t.cliente = c.id.isEmpty ? null : c);
    _enfocar();
  }

  // ---------------- Cobro ----------------

  Future<void> _cobrar() async {
    if (_t.renglones.isEmpty || _ocupado) return;
    final turno = sesion.turno;
    final cajero = sesion.cajero;
    if (turno == null || cajero == null) return;
    _ocupado = true;
    try {
      final r = await cobrar(context, _t.totalCentavos, cliente: _t.cliente, articulos: _t.piezas);
      if (r == null || !mounted) return;
      final venta = await repos.ventas.registrar(
        renglones: _t.renglones,
        pago: r.pago,
        turnoId: turno.id,
        cajeroId: cajero.id,
        cliente: r.cliente,
        notas: r.notas,
      );
      final cerrado = _t;
      setState(() {
        _ultima = venta;
        _tickets.remove(cerrado);
        if (_tickets.isEmpty) {
          _consecutivo++;
          _tickets.add(Ticket('Ticket $_consecutivo'));
        }
        _actual = _actual.clamp(0, _tickets.length - 1);
      });
      avisarCambio();
      abrirCajonAlCobrar(
          conEfectivo: r.pago.efectivoCentavos != 0 || r.pago.recibidoCentavos > 0 || r.pago.dolaresCentavos > 0);
      if (r.imprimir && mounted) {
        final pdf = await ticketVenta(venta, await repos.ventas.detalle(venta.id));
        if (!mounted) return;
        if (repos.ajustes.texto(Ajuste.impresion) == 'siempre') {
          await imprimir(context, pdf, nombre: 'Ticket ${venta.folio}');
        } else {
          await vistaPrevia(context, pdf, titulo: 'Ticket folio ${venta.folio}');
        }
      }
    } on ErrorNegocio catch (e) {
      if (mounted) aviso(context, e.mensaje);
    } catch (e) {
      if (mounted) avisoError(context, e);
    } finally {
      _ocupado = false;
      _enfocar();
    }
  }

  Future<void> _reimprimir() async {
    final v = _ultima ?? (await repos.ventas.listar(limite: 1)).firstOrNull;
    if (v == null || !mounted) {
      if (mounted) aviso(context, 'Todavía no hay ventas.');
      return;
    }
    final pdf = await ticketVenta(v, await repos.ventas.detalle(v.id), copia: true);
    if (mounted) await vistaPrevia(context, pdf, titulo: 'Ticket folio ${v.folio}');
    _enfocar();
  }

  Future<void> _ventasDelDia() async {
    await mostrarVentasDelDia(context);
    _enfocar();
  }

  Future<void> _verificador() async {
    await verificadorDePrecios(context);
    _enfocar();
  }

  Future<void> _abrirCajon() async {
    if (!await autorizar(context, Permiso.entradasSalidas) || !mounted) return _enfocar();
    final error = await abrirCajon();
    if (error != null && mounted) aviso(context, error);
    _enfocar();
  }

  Future<void> _movimientoCaja(String tipo) async {
    final turno = sesion.turno;
    if (turno == null) return;
    if (!await autorizar(context, Permiso.entradasSalidas) || !mounted) return _enfocar();
    final r = await pedirMovimientoCaja(context, tipo);
    if (r == null) return _enfocar();
    if (!mounted) return;
    final ok = await intentar(context, () => repos.caja.registrarMovimiento(turno.id, tipo, r.$1, r.$2));
    if (ok && mounted) {
      aviso(context, '${tipo == 'entrada' ? 'Entrada' : 'Salida'} de ${formatoPesos(r.$1)} registrada.');
      avisarCambio();
    }
    _enfocar();
  }

  // ---------------- Pantalla ----------------

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Banda como en Eleventa: "VENTA - Ticket 3".
      Container(
        width: double.infinity,
        color: ExColor.indigo,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(children: [
          Text('VENTA - ${_t.nombre}', style: ExTexto.titulo(19, color: ExColor.blanco)),
          if (_t.cliente != null) ...[
            const SizedBox(width: 16),
            const Icon(Icons.person, color: ExColor.lavanda, size: 20),
            const SizedBox(width: 4),
            Text(_t.cliente!.nombre, style: const TextStyle(color: ExColor.lavanda, fontSize: 16)),
          ],
        ]),
      ),
      _captura(),
      if (_favoritos.isNotEmpty && MediaQuery.of(context).size.height > 820) _barraFavoritos(),
      _botones(),
      _barraTickets(),
      Expanded(child: _tabla()),
      _pie(),
    ]);
  }

  Widget _barraTickets() {
    return Container(
      color: ExColor.blanco,
      height: 40,
      child: Row(children: [
        Expanded(
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < _tickets.length; i++)
              InkWell(
                onTap: () {
                  setState(() => _actual = i);
                  _enfocar();
                },
                child: Container(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  decoration: BoxDecoration(
                    color: i == _actual ? ExColor.concreto : ExColor.blanco,
                    border: Border(
                      bottom: BorderSide(color: i == _actual ? ExColor.indigo : ExColor.linea, width: i == _actual ? 3 : 1),
                      right: const BorderSide(color: ExColor.lineaSuave),
                    ),
                  ),
                  child: Row(children: [
                    Text(_tickets[i].nombre,
                        style: TextStyle(fontSize: 15, fontWeight: i == _actual ? FontWeight.w700 : FontWeight.w500)),
                    if (_tickets[i].renglones.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(formatoPesos(_tickets[i].totalCentavos),
                          style: ExTexto.mono(12, color: ExColor.texto2, peso: FontWeight.w500)),
                    ],
                    IconButton(
                      tooltip: 'Descartar ticket',
                      visualDensity: VisualDensity.compact,
                      iconSize: 16,
                      onPressed: () => _cerrarTicket(i),
                      icon: const Icon(Icons.close),
                    ),
                  ]),
                ),
              ),
            TextButton.icon(
              onPressed: _nuevoTicket,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('F6 Pendiente / nuevo ticket'),
            ),
            if (_tickets.length > 1) TextButton(onPressed: _siguienteTicket, child: const Text('F5 Cambiar')),
          ]),
        ),
      ]),
    );
  }

  Widget _captura() {
    final cliente = _t.cliente;
    return Container(
      color: ExColor.concreto,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(children: [
        Text('Código del producto:', style: ExTexto.titulo(19)),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _codigo,
            focusNode: _focoCodigo,
            autofocus: true,
            style: ExTexto.mono(22, peso: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Escanea o escribe el código · 3*código para varias piezas · o escribe el nombre',
              hintStyle: const TextStyle(fontSize: 15, color: ExColor.texto2),
              prefixIcon: const Icon(Icons.qr_code_scanner),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(28)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: ExColor.linea)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28), borderSide: const BorderSide(color: ExColor.indigo, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            ),
            onSubmitted: _capturar,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: () => _capturar(_codigo.text),
            icon: const Icon(Icons.keyboard_return),
            label: const Text('ENTER - Agregar Producto', style: TextStyle(fontSize: 15)),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50)),
          onPressed: _elegirCliente,
          icon: const Icon(Icons.person_outline),
          label: Text(cliente == null ? 'Cliente' : cliente.nombre, overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Widget _barraFavoritos() {
    return Container(
      height: 44,
      color: ExColor.concreto,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _favoritos.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = _favoritos[i];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                side: const BorderSide(color: ExColor.lavanda),
                backgroundColor: ExColor.blanco,
              ),
              onPressed: () => _agregar(p),
              child: Text('${p.descripcion}  ${formatoPesos(p.precioCentavos)}', style: const TextStyle(fontSize: 15)),
            ),
          );
        },
      ),
    );
  }

  Widget _botones() {
    Widget b(String tecla, String texto, VoidCallback f, {IconData? icono}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              side: const BorderSide(color: ExColor.linea),
              backgroundColor: ExColor.blanco,
            ),
            onPressed: f,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icono != null) ...[Icon(icono, size: 20), const SizedBox(width: 6)],
              Text(tecla, style: ExTexto.mono(13, color: ExColor.indigo)),
              const SizedBox(width: 6),
              Text(texto, style: const TextStyle(fontSize: 15)),
            ]),
          ),
        );
    return Container(
      color: ExColor.concreto,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          b('INS', 'Varios', _varios),
          b('CTRL+P', 'Art. común', _comun),
          b('F10', 'Buscar', _buscar, icono: Icons.search),
          b('F11', 'Mayoreo', _mayoreo),
          b('CTRL+D', 'Descuento', _descuento),
          b('F7', 'Entradas', () => _movimientoCaja('entrada')),
          b('F8', 'Salidas', () => _movimientoCaja('salida')),
          b('SUPR', 'Borrar art.', _borrarSeleccion),
          b('F9', 'Verificador', _verificador),
          b('CTRL+B', 'Ventas del día', _ventasDelDia),
          if (repos.ajustes.si(Ajuste.cajonAbrir)) b('', 'Abrir cajón', _abrirCajon, icono: Icons.inbox_outlined),
        ]),
      ),
    );
  }

  Widget _tabla() {
    const columnas = [
      ('Código', 3, false),
      ('Descripción del producto', 8, false),
      ('Precio venta', 3, true),
      ('Cant.', 2, true),
      ('Importe', 3, true),
      ('Existencia', 2, true),
    ];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: ExColor.blanco, border: Border.all(color: ExColor.linea)),
      child: Column(children: [
        const EncabezadoTabla(columnas, tamano: 16),
        Expanded(
          child: _t.renglones.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.shopping_basket_outlined, size: 56, color: ExColor.gris),
                    const SizedBox(height: 10),
                    Text('Escanea un producto para empezar', style: ExTexto.titulo(18, color: ExColor.texto2)),
                    const SizedBox(height: 4),
                    const Text('F10 para buscar por nombre · F12 para cobrar', style: TextStyle(color: ExColor.texto2)),
                  ]),
                )
              : ListView.builder(
                  controller: _scroll,
                  itemCount: _t.renglones.length,
                  itemExtent: 52,
                  itemBuilder: (_, i) {
                    final r = _t.renglones[i];
                    final etiquetas = [
                      if (r.conMayoreo) 'mayoreo',
                      if (r.conPromocion) r.promocion!.nombre,
                      if (r.precioManualCentavos != null) 'precio especial',
                      if (r.esComun) 'común',
                    ];
                    return FilaTabla(
                      [
                        (celda(r.codigo, mono: true, tamano: 17), 3, false),
                        (
                          Row(children: [
                            Flexible(child: celda(r.descripcion, tamano: 17)),
                            for (final e in etiquetas)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                color: ExColor.acento.withOpacity(0.18),
                                child: Text(e, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                          ]),
                          8,
                          false
                        ),
                        (celda(formatoPesos(r.precioUnitarioCentavos), mono: true, tamano: 17), 3, true),
                        (celda(formatoCantidad(r.cantidad), mono: true, negrita: true, tamano: 17), 2, true),
                        (celda(formatoPesos(r.importeCentavos), mono: true, negrita: true, tamano: 17), 3, true),
                        (
                          celda(r.existencia == null ? '—' : formatoCantidad(r.existencia! - r.cantidad),
                              mono: true, tamano: 17, color: r.faltaExistencia ? ExColor.rojo : ExColor.texto2),
                          2,
                          true
                        ),
                      ],
                      par: i.isOdd,
                      seleccionada: i == _t.seleccion,
                      onTap: () {
                        setState(() => _t.seleccion = i);
                        _enfocar();
                      },
                      onDoubleTap: () => _editarRenglon(i),
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Widget _chico(IconData i, String t, VoidCallback f) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: ExColor.blanco,
          side: const BorderSide(color: ExColor.linea),
        ),
        onPressed: () {
          f();
          _enfocar();
        },
        icon: Icon(i, size: 18),
        label: Text(t, style: const TextStyle(fontSize: 14)),
      );

  Widget _pie() {
    final pago = _ultima?.pago;
    final pagoCon = pago == null ? 0 : (pago.recibidoCentavos > 0 ? pago.recibidoCentavos : pago.totalCentavos);
    final cambio = pago == null
        ? 0
        : (pago.recibidoCentavos > pago.efectivoCentavos ? pago.recibidoCentavos - pago.efectivoCentavos : (pago.efectivoCentavos < 0 ? -pago.efectivoCentavos : 0));
    Widget dato(String t, int c) => Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 92, child: Text(t, style: const TextStyle(fontSize: 16, color: ExColor.texto2))),
          SizedBox(
            width: 150,
            child: Text(formatoPesos(c), textAlign: TextAlign.right, style: ExTexto.titulo(24, color: ExColor.tinta)),
          ),
        ]);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('${formatoCantidad(_t.piezas)} productos en la venta actual',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
            if (_t.ahorroCentavos > 0)
              Text('El cliente ahorra ${formatoPesos(_t.ahorroCentavos)}',
                  style: const TextStyle(color: ExColor.verde, fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chico(Icons.sync_alt, 'F5 - Cambiar', _siguienteTicket),
              _chico(Icons.add_box_outlined, 'F6 - Pendiente', _nuevoTicket),
              _chico(Icons.delete_outline, 'Eliminar', () => _cerrarTicket(_actual)),
              _chico(Icons.person_add_alt, 'Asignar cliente', _elegirCliente),
              _chico(Icons.add, '+ Cantidad', () => _sumar(1)),
              _chico(Icons.remove, '− Cantidad', () => _sumar(-1)),
              _chico(Icons.undo, 'Devolución', _ventasDelDia),
              _chico(Icons.print_outlined, 'Reimprimir último ticket', _reimprimir),
              _chico(Icons.receipt_long_outlined, 'Ventas del día y devoluciones', _ventasDelDia),
            ]),
          ]),
        ),
        // Como Eleventa: siempre a la vista lo que pagó y su cambio.
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: ExColor.blanco,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ExColor.linea),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            dato('Pagó con:', pagoCon),
            const SizedBox(height: 4),
            dato('Su cambio:', cambio),
            if (_ultima != null)
              Text('Folio ${_ultima!.folio} · ${pago!.descripcion}', style: const TextStyle(fontSize: 12, color: ExColor.texto2)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(26, 12, 12, 12),
          decoration: BoxDecoration(color: ExColor.tinta, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
              const Text('TOTAL', style: TextStyle(color: ExColor.textoClaro2, fontSize: 14, letterSpacing: 2)),
              Text(formatoPesos(_t.totalCentavos), style: ExTexto.titulo(52, color: ExColor.concreto)),
            ]),
            const SizedBox(width: 20),
            SizedBox(
              height: 84,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: ExColor.acento,
                  foregroundColor: ExColor.tinta,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                ),
                onPressed: _t.renglones.isEmpty ? null : _cobrar,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('F12', style: ExTexto.mono(15, color: ExColor.tinta)),
                  Text('Cobrar', style: ExTexto.titulo(28, color: ExColor.tinta)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
