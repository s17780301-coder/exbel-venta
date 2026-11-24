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
import '../comun/ex_ui.dart';
import '../config/config_page.dart' show versionExBel;
import '../comun/impresion.dart';
import '../principal.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../comun/buscador_universal.dart';
import 'buscar_producto.dart';
import 'cobro_dialogo.dart';
import 'dialogos_venta.dart';
import 'ventas_dia.dart';

/// Máximo de tickets abiertos a la vez (Ticket 1 a Ticket 5).
const maxTickets = 5;

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
    encabezadoVentas.value = (_) => _ticketsSegmentados();
    _cargarFavoritos();
    _restaurarTickets();
  }

  /// Cada cambio guarda los tickets abiertos: si se cierra el programa o se
  /// va la luz, al volver siguen ahí.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    refrescoEncabezado.value++;
    _guardado?.cancel();
    _guardado = Timer(const Duration(milliseconds: 400), _guardarTickets);
  }

  Future<void> _guardarTickets() async {
    final datos = {
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
      for (final tm in (d['tickets'] as List).take(maxTickets)) {
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
        for (var n = 0; n < lista.length; n++) {
          lista[n].nombre = 'Ticket ${n + 1}';
        }
        _tickets
          ..clear()
          ..addAll(lista);
        _actual = ((d['actual'] as int?) ?? 0).clamp(0, lista.length - 1);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    teclasVentas.removeListener(_alTeclear);
    encabezadoVentas.value = null;
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
      if (_codigo.text.isEmpty) _borrarSeleccion();
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _mover(-1);
    } else if (k == LogicalKeyboardKey.arrowDown) {
      _mover(1);
    } else if (esMasOMenos(e) != 0) {
      if (_codigo.text.isEmpty) _sumar(esMasOMenos(e));
    } else if (ctrl && k == LogicalKeyboardKey.keyP) {
      _comun();
    } else if (ctrl && k == LogicalKeyboardKey.keyD) {
      _descuento();
    } else if (ctrl && k == LogicalKeyboardKey.keyB) {
      _ventasDelDia();
    } else if (ctrl && k == LogicalKeyboardKey.keyR) {
      _reimprimir();
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
    // Con "−" no se borra el producto: se queda en lo mínimo. Para quitarlo
    // está SUPR / "Borrar art.".
    if (nueva < 1 && d < 0) {
      aviso(context, 'Ya está en lo mínimo. Para quitar el producto usa SUPR o "Borrar art.".');
      return;
    }
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
    if (_t.renglones.isEmpty) return _enfocar();
    final i = _t.seleccion;
    if (i < 0 || i >= _t.renglones.length) {
      aviso(context, 'Haz clic en el artículo que quieres borrar.');
      return _enfocar();
    }
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

  /// "Ticket 1" a "Ticket 5": el primer número libre.
  String _nombreLibre() {
    for (var n = 1; n <= maxTickets; n++) {
      if (!_tickets.any((t) => t.nombre == 'Ticket $n')) return 'Ticket $n';
    }
    return 'Ticket ${_tickets.length + 1}';
  }

  /// F6: deja el ticket actual pendiente y abre otro (máximo 5).
  void _nuevoTicket() {
    if (_tickets.length >= maxTickets) {
      aviso(context, 'Ya hay $maxTickets tickets abiertos. Cobra o elimina uno para abrir otro.');
      return _enfocar();
    }
    if (_t.renglones.isEmpty) {
      aviso(context, 'Este ticket está vacío; úsalo para la siguiente persona.');
      return _enfocar();
    }
    setState(() {
      _tickets.add(Ticket(_nombreLibre()));
      _actual = _tickets.length - 1;
    });
    _enfocar();
  }

  void _siguienteTicket() {
    if (_tickets.length < 2) return;
    setState(() => _actual = (_actual + 1) % _tickets.length);
    _enfocar();
  }

  /// Elimina el ticket. Si es el único, solo lo vacía.
  Future<void> _cerrarTicket(int i) async {
    final t = _tickets[i];
    if (t.renglones.isNotEmpty &&
        !await confirmar(context, 'Eliminar ticket', '¿Borrar "${t.nombre}" con ${t.renglones.length} artículos?',
            si: 'Eliminar', peligro: true)) {
      return _enfocar();
    }
    setState(() {
      if (_tickets.length == 1) {
        t.renglones.clear();
        t.cliente = null;
        t.seleccion = -1;
      } else {
        _tickets.removeAt(i);
        if (_actual > i) _actual--;
        if (_actual >= _tickets.length) _actual = _tickets.length - 1;
      }
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
        if (_tickets.isEmpty) _tickets.add(Ticket('Ticket 1'));
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
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 6, 18, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _captura(),
            const SizedBox(height: 14),
            Expanded(child: _tabla()),
            const SizedBox(height: 8),
            _atajos(),
          ]),
        ),
      ),
      _panelCobro(),
    ]);
  }

  /// En el encabezado: los tickets abiertos como pestañas.
  Widget _ticketsSegmentados() {
    Widget chip(int i) {
      final t = _tickets[i];
      final activa = i == _actual;
      return Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Material(
          color: activa ? ExEstilo.tarjeta : Colors.transparent,
          elevation: 0,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () {
              setState(() => _actual = i);
              _enfocar();
            },
            child: Container(
              decoration: activa
                  ? BoxDecoration(borderRadius: BorderRadius.circular(9), boxShadow: ExEstilo.sombra)
                  : null,
              padding: EdgeInsets.only(left: 13, right: activa ? 4 : 13, top: 7, bottom: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(t.nombre,
                    style: TextStyle(fontSize: 13, fontWeight: activa ? FontWeight.w700 : FontWeight.w500, color: activa ? ExColor.tinta : ExEstilo.texto2)),
                if (t.renglones.isNotEmpty)
                  Text(' · ${formatoPesos(t.totalCentavos)}',
                      style: TextStyle(fontSize: 13, color: activa ? ExColor.tinta : ExEstilo.texto2)),
                if (activa) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _cerrarTicket(i),
                    child: const Tooltip(
                      message: 'Eliminar ticket',
                      child: Padding(padding: EdgeInsets.all(3), child: Icon(Icons.close_rounded, size: 15, color: ExEstilo.texto2)),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: ExEstilo.suave, borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < _tickets.length; i++) chip(i),
          if (_tickets.length < maxTickets)
            Tooltip(
              message: 'Nuevo ticket (F6)',
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: _nuevoTicket,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Icon(Icons.add_rounded, size: 19, color: ExEstilo.primario),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _captura() {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: ExEstilo.tarjeta,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCFCBEA), width: 1.5),
        boxShadow: const [BoxShadow(color: ExEstilo.suave, spreadRadius: 4)],
      ),
      padding: const EdgeInsets.only(left: 16, right: 7),
      child: Row(children: [
        const Icon(Icons.qr_code_scanner_rounded, color: ExEstilo.primario, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _codigo,
            focusNode: _focoCodigo,
            autofocus: true,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500, color: ExColor.tinta),
            decoration: const InputDecoration(
              hintText: 'Escanea o escribe el código del producto…',
              hintStyle: TextStyle(fontSize: 17, color: ExEstilo.texto2, fontWeight: FontWeight.w400),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
            ),
            onSubmitted: _capturar,
          ),
        ),
        InkWell(
          onTap: _buscar,
          borderRadius: BorderRadius.circular(8),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Tecla('F10'),
              SizedBox(width: 6),
              Text('buscar por nombre', style: TextStyle(fontSize: 12.5, color: ExEstilo.texto2)),
            ]),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          height: 42,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: ExEstilo.suave,
              foregroundColor: ExEstilo.primarioOscuro,
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _capturar(_codigo.text),
            icon: const Icon(Icons.keyboard_return_rounded, size: 18),
            label: const Text('Agregar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  Widget _tabla() {
    const flex = [2, 8, 3, 2, 3, 2];
    Widget enc(String t, int f, {bool der = false}) => Expanded(
          flex: f,
          child: Text(t,
              textAlign: der ? TextAlign.right : TextAlign.left,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ExEstilo.texto2, letterSpacing: 0.4)),
        );
    const num = TextStyle(fontSize: 15, fontFeatures: [FontFeature.tabularFigures()], color: ExColor.tinta);
    return Tarjeta(
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: ExEstilo.linea))),
          child: Row(children: [
            enc('CÓDIGO', flex[0]),
            enc('PRODUCTO', flex[1]),
            enc('PRECIO', flex[2], der: true),
            enc('CANT.', flex[3], der: true),
            enc('IMPORTE', flex[4], der: true),
            enc('EXIST.', flex[5], der: true),
          ]),
        ),
        Expanded(
          child: _t.renglones.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Mosaico(Icons.shopping_basket_rounded, tono: Tono.lavanda, tamano: 64),
                    const SizedBox(height: 14),
                    Text('Escanea un producto para empezar', style: ExTexto.titulo(18, color: ExColor.tinta)),
                    const SizedBox(height: 6),
                    const Row(mainAxisSize: MainAxisSize.min, children: [
                      Tecla('F10'),
                      Text('  para buscar por nombre   ·   ', style: TextStyle(color: ExEstilo.texto2)),
                      Tecla('F12'),
                      Text('  para cobrar', style: TextStyle(color: ExEstilo.texto2)),
                    ]),
                  ]),
                )
              : ListView.builder(
                  controller: _scroll,
                  itemCount: _t.renglones.length,
                  itemExtent: 56,
                  itemBuilder: (_, i) {
                    final r = _t.renglones[i];
                    final sel = i == _t.seleccion;
                    final dep = r.producto?.departamentoNombre ?? (r.esComun ? 'Artículo común' : 'Sin departamento');
                    final etiquetas = [
                      if (r.conMayoreo) 'mayoreo',
                      if (r.conPromocion) r.promocion!.nombre,
                      if (r.precioManualCentavos != null) 'precio especial',
                    ];
                    return FilaTabla(
                      [
                        (Text(r.codigo, style: num.copyWith(color: ExEstilo.texto2)), flex[0], false),
                        (
                          Row(children: [
                            AvatarColor(dep, tamano: 34, redondo: false),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(r.descripcion,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ExColor.tinta)),
                                  ),
                                  for (final e in etiquetas)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: Tono.verde.fondo, borderRadius: BorderRadius.circular(5)),
                                      child: Text(e, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Tono.verde.color)),
                                    ),
                                ]),
                                Text(dep, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: ExEstilo.texto2)),
                              ]),
                            ),
                          ]),
                          flex[1],
                          false
                        ),
                        (Text(formatoPesos(r.precioUnitarioCentavos), style: num), flex[2], true),
                        (Text(formatoCantidad(r.cantidad), style: num.copyWith(fontWeight: FontWeight.w700)), flex[3], true),
                        (Text(formatoPesos(r.importeCentavos), style: num.copyWith(fontWeight: FontWeight.w700)), flex[4], true),
                        (
                          Text(r.existencia == null ? '—' : formatoCantidad(r.existencia! - r.cantidad),
                              style: num.copyWith(color: r.faltaExistencia ? ExColor.rojo : ExEstilo.texto2)),
                          flex[5],
                          true
                        ),
                      ],
                      seleccionada: sel,
                      color: ExEstilo.tarjeta,
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

  Widget _atajos() {
    void y(VoidCallback f) {
      f();
      _enfocar();
    }

    return Row(children: [
      Expanded(
        child: Wrap(spacing: 2, runSpacing: 2, children: [
          Atajo('+ / −', 'Cantidad', () => y(() => _sumar(1))),
          Atajo('Supr', 'Quitar', () => y(_borrarSeleccion)),
          Atajo('INS', 'Varios', () => y(_varios)),
          Atajo('Ctrl+P', 'Art. común', () => y(_comun)),
          Atajo('F11', 'Mayoreo', () => y(_mayoreo)),
          Atajo('F7', 'Entrada', () => y(() => _movimientoCaja('entrada'))),
          Atajo('F8', 'Salida', () => y(() => _movimientoCaja('salida'))),
          Atajo('F9', 'Verificador', () => y(_verificador)),
          Atajo('F5', 'Cambiar ticket', () => y(_siguienteTicket)),
          if (repos.ajustes.si(Ajuste.cajonAbrir)) Atajo('Cajón', 'Abrir', () => y(_abrirCajon)),
        ]),
      ),
      const _Reloj(),
    ]);
  }

  Widget _panelCobro() {
    final pago = _ultima?.pago;
    final pagoCon = pago == null ? 0 : (pago.recibidoCentavos > 0 ? pago.recibidoCentavos : pago.totalCentavos);
    final cambio = pago == null
        ? 0
        : (pago.recibidoCentavos > pago.efectivoCentavos ? pago.recibidoCentavos - pago.efectivoCentavos : (pago.efectivoCentavos < 0 ? -pago.efectivoCentavos : 0));
    final cliente = _t.cliente;
    const num = [FontFeature.tabularFigures()];
    Widget renglon(String a, String b, {Color? color, bool fuerte = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(a, style: const TextStyle(fontSize: 14, color: ExEstilo.texto2))),
            Text(b, style: TextStyle(fontSize: 15, fontWeight: fuerte ? FontWeight.w700 : FontWeight.w600, color: color ?? ExColor.tinta, fontFeatures: num)),
          ]),
        );
    void y(VoidCallback f) {
      f();
      _enfocar();
    }

    return Container(
      width: 340,
      decoration: const BoxDecoration(color: ExEstilo.superficie, border: Border(left: BorderSide(color: ExEstilo.linea))),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Cliente
        Material(
          color: ExEstilo.tarjeta,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => y(_elegirCliente),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: ExEstilo.linea)),
              child: Row(children: [
                cliente == null
                    ? const Mosaico(Icons.person_rounded, tono: Tono.coral, tamano: 36)
                    : AvatarColor(cliente.nombre, tamano: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cliente?.nombre ?? 'Público en general',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: ExColor.tinta)),
                    Text(
                        cliente == null
                            ? 'Asignar cliente para crédito'
                            : 'Debe ${formatoPesos(cliente.saldoCentavos)}${cliente.tieneLimite ? ' · tope ${formatoPesos(cliente.limiteCentavos)}' : ''}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: ExEstilo.texto2)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: ExEstilo.texto2),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Total
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: ExEstilo.suave,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCD8EF)),
          ),
          child: Stack(children: [
            const Positioned(right: -40, top: -40, child: _Adorno()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                renglon('Artículos', formatoCantidad(_t.piezas)),
                if (_t.ahorroCentavos > 0) renglon('Ahorro del cliente', formatoPesos(_t.ahorroCentavos), color: Tono.verde.color),
                Container(height: 1, color: const Color(0xFFD8D4EE), margin: const EdgeInsets.symmetric(vertical: 8)),
                const Text('TOTAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2, color: ExEstilo.texto2)),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(formatoPesos(_t.totalCentavos),
                      style: ExTexto.titulo(52, color: ExEstilo.primarioOscuro, peso: FontWeight.w600).copyWith(fontFeatures: num, letterSpacing: -1.2)),
                ),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Cobrar
        SizedBox(
          height: 64,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ExEstilo.primario,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFB9B6D6),
              disabledForegroundColor: Colors.white,
              side: BorderSide.none,
              elevation: 3,
              shadowColor: ExEstilo.primario.withOpacity(0.35),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _t.renglones.isEmpty ? null : _cobrar,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.payments_rounded, size: 26),
              const SizedBox(width: 12),
              const Text('Cobrar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(6)),
                child: const Text('F12', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        // Venta anterior
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(color: ExEstilo.tarjeta, borderRadius: BorderRadius.circular(14), border: Border.all(color: ExEstilo.linea)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Mosaico(_ultima == null ? Icons.receipt_long_rounded : Icons.check_rounded, tono: _ultima == null ? Tono.gris : Tono.verde, tamano: 28),
              const SizedBox(width: 10),
              Text(_ultima == null ? 'VENTA ANTERIOR' : 'VENTA ANTERIOR · FOLIO ${_ultima!.folio}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: ExEstilo.texto2)),
            ]),
            const SizedBox(height: 6),
            renglon('Pagó con', formatoPesos(pagoCon)),
            renglon('Su cambio', formatoPesos(cambio), color: cambio > 0 ? Tono.verde.color : null, fuerte: true),
          ]),
        ),
        const Spacer(),
        // Acciones
        Row(children: [
          Expanded(child: BotonAccion(icono: Icons.print_rounded, texto: 'Reimprimir último ticket', tecla: 'Ctrl+R', tono: Tono.azul, onTap: () => y(_reimprimir))),
          const SizedBox(width: 8),
          Expanded(
              child: BotonAccion(
                  icono: Icons.receipt_long_rounded, texto: 'Ventas del día y devoluciones', tecla: 'Ctrl+B', tono: Tono.rosa, onTap: () => y(_ventasDelDia))),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: BotonAccion(icono: Icons.schedule_rounded, texto: 'Dejar pendiente', tecla: 'F6', tono: Tono.ambar, onTap: () => y(_nuevoTicket))),
          const SizedBox(width: 8),
          Expanded(child: BotonAccion(icono: Icons.percent_rounded, texto: 'Descuento', tecla: 'Ctrl+D', tono: Tono.verde, onTap: () => y(_descuento))),
        ]),
      ]),
    );
  }
}

/// Detalle de la tarjeta del total: círculos y el punto coral de la marca.
class _Adorno extends StatelessWidget {
  const _Adorno();

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 150,
        height: 150,
        child: Stack(children: [
          Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFDCD8EF), width: 1.5))),
          Center(
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFDCD8EF), width: 1.5)),
            ),
          ),
          Positioned(
            right: 25,
            bottom: 25,
            child: Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: ExColor.acento.withOpacity(0.6))),
          ),
        ]),
      );
}

/// Abajo a la derecha: versión, fecha y hora.
class _Reloj extends StatefulWidget {
  const _Reloj();

  @override
  State<_Reloj> createState() => _RelojState();
}

class _RelojState extends State<_Reloj> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  static const _meses = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];

  @override
  Widget build(BuildContext context) {
    final a = DateTime.now();
    final h = a.hour % 12 == 0 ? 12 : a.hour % 12;
    final hora = '$h:${a.minute.toString().padLeft(2, '0')} ${a.hour < 12 ? 'am' : 'pm'}';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('exBel venta $versionExBel', style: const TextStyle(color: ExColor.texto2, fontSize: 12)),
      const SizedBox(width: 18),
      Text('${a.day} - ${_meses[a.month - 1]}   $hora', style: ExTexto.titulo(18, color: ExColor.texto2, peso: FontWeight.w500)),
    ]);
  }
}
