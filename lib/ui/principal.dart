import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ajustes_repo.dart';
import '../data/repos.dart';
import '../models/modelos.dart';
import 'acceso/acceso_page.dart';
import 'clientes/clientes_page.dart';
import 'comun/buscador_universal.dart';
import 'productos/producto_form.dart';
import 'ventas/ventas_dia.dart';
import 'comun/dialogos.dart';
import 'comun/ex_widgets.dart';
import 'comun/nombre_tienda.dart';
import 'comun/ventana.dart';
import 'config/config_page.dart';
import 'cortes/corte_page.dart';
import 'inventario/inventario_page.dart';
import 'productos/productos_page.dart';
import 'reportes/reportes_page.dart';
import 'sesion.dart';
import 'tema/tema.dart';
import 'ventas/ventas_page.dart';

/// Teclas que la pantalla de ventas atiende cuando está a la vista.
final teclasVentas = ValueNotifier<KeyEvent?>(null);

/// +1 / −1 si la tecla escribe "+" o "-" (en cualquier teclado: con Shift en
/// laptops, la tecla junto al Enter o el teclado numérico); 0 si no.
int esMasOMenos(KeyEvent e) {
  final c = e.character;
  if (c == '+' || e.logicalKey == LogicalKeyboardKey.numpadAdd || e.logicalKey == LogicalKeyboardKey.add) return 1;
  if (c == '-' || e.logicalKey == LogicalKeyboardKey.numpadSubtract || e.logicalKey == LogicalKeyboardKey.minus) return -1;
  return 0;
}

/// Lo pone Ventas: si el campo de código está vacío, + y − cambian la cantidad.
bool Function() codigoVentasVacio = () => true;

class _Seccion {
  const _Seccion(this.nombre, this.tecla, this.icono, this.permiso);
  final String nombre;
  final String? tecla;
  final IconData icono;
  final String? permiso;
}

const _secciones = <_Seccion>[
  _Seccion('Ventas', 'F1', Icons.point_of_sale, null),
  _Seccion('Clientes', 'F2', Icons.people_alt_outlined, null),
  _Seccion('Productos', 'F3', Icons.inventory_2_outlined, null),
  _Seccion('Inventario', 'F4', Icons.warehouse_outlined, null),
  _Seccion('Corte', null, Icons.calculate_outlined, null),
  _Seccion('Reportes', null, Icons.bar_chart, Permiso.reportes),
  _Seccion('Configuración', null, Icons.settings_outlined, Permiso.configuracion),
];

class Principal extends StatefulWidget {
  const Principal({super.key});

  @override
  State<Principal> createState() => _PrincipalState();
}

class _PrincipalState extends State<Principal> {
  int _actual = 0;
  final _visitadas = <int>{0};

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tecla);
    cambiosDatos.addListener(_refrescar);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tecla);
    cambiosDatos.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  bool _tecla(KeyEvent e) {
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final buscar = e.logicalKey == LogicalKeyboardKey.f10 || (ctrl && e.logicalKey == LogicalKeyboardKey.keyF);
    // F10 es tecla de sistema en Windows (activa el menú de la ventana y se
    // "come" las teclas siguientes): se consume también al soltarla.
    if (e is! KeyDownEvent) return e.logicalKey == LogicalKeyboardKey.f10;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return e.logicalKey == LogicalKeyboardKey.f10;
    final mapa = {
      LogicalKeyboardKey.f1: 0,
      LogicalKeyboardKey.f2: 1,
      LogicalKeyboardKey.f3: 2,
      LogicalKeyboardKey.f4: 3,
    };
    final i = mapa[e.logicalKey];
    if (i != null) {
      _ir(i);
      return true;
    }
    // F10 en cualquier pantalla: buscador universal.
    if (buscar && _actual != 0) {
      _buscarUniversal();
      return true;
    }
    if (_actual == 0) {
      teclasVentas.value = e;
      return _teclaDeVentas(e);
    }
    return false;
  }

  /// Teclas que se "comen" para que no escriban en el campo de código.
  bool _teclaDeVentas(KeyEvent e) {
    final k = e.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    return [
          LogicalKeyboardKey.f5, LogicalKeyboardKey.f6, LogicalKeyboardKey.f7, LogicalKeyboardKey.f8,
          LogicalKeyboardKey.f9, LogicalKeyboardKey.f10, LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
          LogicalKeyboardKey.insert, LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
        ].contains(k) ||
        ((esMasOMenos(e) != 0 || k == LogicalKeyboardKey.delete) && codigoVentasVacio()) ||
        (ctrl && [LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyB, LogicalKeyboardKey.keyF].contains(k));
  }

  Future<void> _ir(int i) async {
    final permiso = _secciones[i].permiso;
    if (permiso != null && !await autorizar(context, permiso)) return;
    setState(() {
      _actual = i;
      _visitadas.add(i);
    });
  }

  Future<void> _buscarUniversal() async {
    final h = await buscarUniversal(context);
    if (h == null || !mounted) return;
    final p = h.producto, c = h.cliente, v = h.venta;
    if (p != null) {
      if (await autorizar(context, Permiso.productos) && mounted && await editarProducto(context, p)) avisarCambio();
    } else if (c != null) {
      clienteParaAbrir.value = c.id;
      await _ir(1);
    } else if (v != null) {
      await mostrarVentasDelDia(context, venta: v);
    }
  }

  Future<void> _cambiarCajero() async {
    if (!await confirmar(context, 'Cambiar de cajero', 'El turno sigue abierto. ¿Salir para que entre otro cajero?')) return;
    sesion.salir();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AccesoPage()));
    }
  }

  Widget _pagina(int i) {
    if (!_visitadas.contains(i)) return const SizedBox.shrink();
    return switch (i) {
      0 => const VentasPage(),
      1 => const ClientesPage(),
      2 => const ProductosPage(),
      3 => const InventarioPage(),
      4 => CortePage(alCerrarTurno: () {
          sesion.salir();
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const AccesoPage()));
        }),
      5 => const ReportesPage(),
      _ => const ConfigPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        _barraSuperior(),
        Expanded(
          child: IndexedStack(
            index: _actual,
            children: [for (var i = 0; i < _secciones.length; i++) _pagina(i)],
          ),
        ),
      ]),
    );
  }

  /// Barra superior clara, como Eleventa: la tienda a la izquierda y las
  /// secciones en botones con recuadro.
  Widget _barraSuperior() {
    final negocio = repos.ajustes.texto(Ajuste.nombreNegocio);
    final logo = repos.ajustes.texto(Ajuste.logoNegocio);
    final archivo = logo.isEmpty ? null : File(logo);
    final cajero = sesion.cajero;
    final turno = sesion.turno;
    return Container(
      height: 92,
      decoration: const BoxDecoration(
        color: ExColor.blanco,
        border: Border(bottom: BorderSide(color: ExColor.borde, width: 1.4)),
      ),
      padding: const EdgeInsets.only(left: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Extremo superior izquierdo: exBel™ chiquito y la tienda.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            const ExMarca(tamano: 11),
            const SizedBox(height: 2),
            Tooltip(
              message: 'Cambiar el nombre o el logotipo de la tienda',
              child: InkWell(
                onTap: () async {
                  if (await autorizar(context, Permiso.configuracion) && mounted) await editarNegocio(context);
                },
                borderRadius: BorderRadius.circular(8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (archivo != null && archivo.existsSync()) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(archivo, height: 34, width: 34, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: NombreTienda(negocio, tamano: 26, oscuro: false),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [for (var i = 0; i < _secciones.length; i++) _pestana(i)]),
            ),
          ),
        ),
        if (cajero != null)
          InkWell(
            onTap: _cambiarCajero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  const Text('Le atiende:', style: TextStyle(color: ExColor.texto2, fontSize: 12)),
                  Text(cajero.nombre, style: const TextStyle(color: ExColor.tinta, fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(turno == null ? 'Sin turno' : 'Turno ${turno.numero}',
                      style: const TextStyle(color: ExColor.texto2, fontSize: 12)),
                ]),
                const SizedBox(width: 8),
                ExAvatar(cajero.nombre, size: 38),
              ]),
            ),
          ),
        const Align(alignment: Alignment.topCenter, child: BotonesVentana()),
      ]),
    );
  }

  Widget _pestana(int i) {
    final s = _secciones[i];
    final activa = i == _actual;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: activa ? ExColor.indigo : ExColor.concreto,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: activa ? ExColor.indigo : ExColor.borde, width: 1.4),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _ir(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(s.icono, size: 26, color: activa ? ExColor.blanco : ExColor.indigo),
              const SizedBox(width: 8),
              Text(
                s.tecla == null ? s.nombre : '${s.tecla} ${s.nombre}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: activa ? ExColor.blanco : ExColor.tinta),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
