import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/caja_local.dart';
import '../core/emergencia.dart';
import '../core/licencia.dart';
import '../data/ajustes_repo.dart';
import '../data/repos.dart';
import '../models/modelos.dart';
import 'acceso/acceso_page.dart';
import 'clientes/clientes_page.dart';
import 'comun/buscador_universal.dart';
import 'productos/producto_form.dart';
import 'productos/productos_rapido.dart';
import 'ventas/ventas_dia.dart';
import 'comun/dialogos.dart';
import 'comun/licencia_ui.dart';
import 'comun/actualizacion_ui.dart';
import 'comun/ex_ui.dart';
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

/// Borra lo que se haya escrito en el campo de código (al activar el pánico).
void Function() limpiarCapturaVentas = () {};

/// Pone el cursor en el campo de código de Ventas.
void Function() enfocarVentas = () {};

/// true mientras la sección visible es Ventas.
bool ventasVisible = true;

class _Seccion {
  const _Seccion(this.nombre, this.tecla, this.icono, this.permiso, this.tono);
  final String nombre;
  final String? tecla;
  final IconData icono;
  final String? permiso;
  final Tono tono;
}

const _secciones = <_Seccion>[
  _Seccion('Ventas', 'F1', Icons.point_of_sale_rounded, null, Tono.lavanda),
  _Seccion('Clientes', 'F2', Icons.people_alt_rounded, null, Tono.coral),
  _Seccion('Productos', null, Icons.inventory_2_rounded, null, Tono.verde),
  _Seccion('Inventario', 'F4', Icons.warehouse_rounded, null, Tono.ambar),
  _Seccion('Corte', null, Icons.calculate_rounded, null, Tono.azul),
  _Seccion('Reportes', null, Icons.bar_chart_rounded, Permiso.reportes, Tono.rosa),
  _Seccion('Ajustes', null, Icons.settings_rounded, Permiso.configuracion, Tono.gris),
];

/// Lo que la sección de Ventas pone en el encabezado (sus tickets).
final encabezadoVentas = ValueNotifier<WidgetBuilder?>(null);
final refrescoEncabezado = ValueNotifier<int>(0);

class Principal extends StatefulWidget {
  const Principal({super.key});

  @override
  State<Principal> createState() => _PrincipalState();
}

class _PrincipalState extends State<Principal> with WidgetsBindingObserver {
  int _actual = 0;
  final _visitadas = <int>{0};
  Timer? _latido;

  void _latir() => latido(caja: cajaLocal.nombreCaja, cajero: sesion.cajero?.nombre ?? '', equipo: Licencia.instancia.equipo);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_tecla);
    cambiosDatos.addListener(_refrescar);
    // Latido a la nube: así exBel Alerta sabe que esta caja está en línea.
    _latir();
    _latido = Timer.periodic(const Duration(minutes: 3), (_) => _latir());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState estado) {
    // Al volver a exBel desde otro programa, el cursor regresa al código.
    if (estado == AppLifecycleState.resumed && _actual == 0) enfocarVentas();
  }

  /// Después de cerrar una ventana abierta desde aquí (F3, F10…).
  void _volverAlCodigo() {
    if (mounted && _actual == 0) enfocarVentas();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_tecla);
    cambiosDatos.removeListener(_refrescar);
    _latido?.cancel();
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
    // + y − sostenidos en Ventas: siguen sumando o restando (no escriben).
    if (e is KeyRepeatEvent &&
        _actual == 0 &&
        esMasOMenos(e) != 0 &&
        codigoVentasVacio() &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      teclasVentas.value = e;
      return true;
    }
    if (e is! KeyDownEvent) return e.logicalKey == LogicalKeyboardKey.f10;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) {
      // F10 / Ctrl+F funciona también con cualquier ventana abierta (F3,
      // cobro, clientes…): el buscador se abre encima.
      if (buscar) {
        if (!buscadorAbierto) _buscarUniversal();
        return true;
      }
      return false;
    }
    final mapa = {
      LogicalKeyboardKey.f1: 0,
      LogicalKeyboardKey.f2: 1,
      LogicalKeyboardKey.f4: 3,
    };
    // F3: ventana rápida para agregar o eliminar productos.
    if (e.logicalKey == LogicalKeyboardKey.f3) {
      productosRapido(context).then((_) => _volverAlCodigo());
      return true;
    }
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
        (e.physicalKey == PhysicalKeyboardKey.numpadDecimal && k == LogicalKeyboardKey.delete) ||
        ((esMasOMenos(e) != 0 || k == LogicalKeyboardKey.delete) && codigoVentasVacio()) ||
        (ctrl && [LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyB, LogicalKeyboardKey.keyF, LogicalKeyboardKey.keyR].contains(k));
  }

  bool get _esEmpleado => sesion.cajero?.empleado ?? false;

  Future<void> _ir(int i) async {
    if (i != 0 && _esEmpleado) {
      aviso(context, 'Tu usuario de empleado solo tiene acceso a Ventas.');
      return;
    }
    final permiso = _secciones[i].permiso;
    if (permiso != null && !await autorizar(context, permiso)) return;
    setState(() {
      _actual = i;
      _visitadas.add(i);
    });
    ventasVisible = i == 0;
    // Al regresar a Ventas, el cursor queda listo en el campo de código.
    if (i == 0) enfocarVentas();
  }

  Future<void> _buscarUniversal() async {
    final h = await buscarUniversal(context);
    if (h == null || !mounted) return _volverAlCodigo();
    final p = h.producto, c = h.cliente, v = h.venta;
    final enInventario = elegirEnInventario;
    if (p != null && _actual == 3 && enInventario != null) {
      // En Inventario (agregar mercancía, ajuste o salida): el producto va al formulario.
      enInventario(p);
    } else if (p != null) {
      if (await autorizar(context, Permiso.productos) && mounted && await editarProducto(context, p)) avisarCambio();
    } else if (c != null) {
      clienteParaAbrir.value = c.id;
      await _ir(1);
    } else if (v != null) {
      await mostrarVentasDelDia(context, venta: v);
    }
    _volverAlCodigo();
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
    // Un empleado siempre está en Ventas.
    if (_esEmpleado && _actual != 0) {
      _actual = 0;
      ventasVisible = true;
    }
    return Scaffold(
      backgroundColor: ExEstilo.fondo,
      body: Row(children: [
        _menuLateral(),
        Expanded(
          child: Column(children: [
            const AvisoPrueba(),
        const AvisoActualizacion(),
            _barraSuperior(),
            Expanded(
              child: IndexedStack(
                index: _actual,
                children: [for (var i = 0; i < _secciones.length; i++) _pagina(i)],
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _barraSuperior() {
    final negocio = repos.ajustes.texto(Ajuste.nombreNegocio);
    final logo = repos.ajustes.texto(Ajuste.logoNegocio);
    final archivo = logo.isEmpty ? null : File(logo);
    final cajero = sesion.cajero;
    final turno = sesion.turno;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 8, 4),
      child: SizedBox(
        height: 54,
        child: Row(children: [
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
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(archivo, height: 40, width: 40, fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 10),
                ],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: NombreTienda(negocio, tamano: 26, oscuro: false),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: refrescoEncabezado,
              builder: (c, _, __) {
                final b = encabezadoVentas.value;
                if (_actual != 0 || b == null) return const SizedBox.shrink();
                return Align(alignment: Alignment.centerRight, child: b(c));
              },
            ),
          ),
          const SizedBox(width: 14),
          if (cajero != null)
            Tooltip(
              message: 'Cambiar de cajero',
              child: InkWell(
                onTap: _cambiarCajero,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    AvatarColor(cajero.nombre, tamano: 38, tono: Tono.coral, anillo: true),
                    const SizedBox(width: 12),
                    Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cajero.nombre, style: const TextStyle(color: ExColor.tinta, fontWeight: FontWeight.w600, fontSize: 15)),
                      Text(turno == null ? cajaLocal.nombreCaja : '${turno.caja} · Turno ${turno.numero}',
                          style: const TextStyle(color: ExEstilo.texto2, fontSize: 12.5)),
                    ]),
                  ]),
                ),
              ),
            ),
          const Align(alignment: Alignment.topCenter, child: BotonesVentana(oscuro: false)),
        ]),
      ),
    );
  }

  Widget _menuLateral() {
    return Container(
      width: 96,
      decoration: const BoxDecoration(
        color: ExEstilo.superficie,
        border: Border(right: BorderSide(color: ExEstilo.linea)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(children: [
        const ExMarca(tamano: 17),
        const SizedBox(height: 18),
        // Los empleados solo ven Ventas.
        for (var i = 0; i < _secciones.length - 1; i++)
          if (i == 0 || !_esEmpleado) _opcionMenu(i),
        const Spacer(),
        if (!_esEmpleado) _opcionMenu(_secciones.length - 1),
      ]),
    );
  }

  Widget _opcionMenu(int i) {
    final s = _secciones[i];
    final activa = i == _actual;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      child: Material(
        color: activa ? const Color(0xFFF0EEF9) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _ir(i),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(children: [
                Mosaico(s.icono, tono: s.tono, tamano: 38),
                const SizedBox(height: 4),
                Text(s.nombre,
                    style: TextStyle(
                        fontSize: 12, fontWeight: activa ? FontWeight.w700 : FontWeight.w500, color: activa ? ExEstilo.primarioOscuro : ExEstilo.texto2)),
                if (s.tecla != null) Text(s.tecla!, style: const TextStyle(fontSize: 10, color: ExEstilo.texto2)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
