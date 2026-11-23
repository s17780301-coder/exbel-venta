import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/ajustes_repo.dart';
import '../data/repos.dart';
import '../models/modelos.dart';
import 'acceso/acceso_page.dart';
import 'clientes/clientes_page.dart';
import 'comun/dialogos.dart';
import 'comun/ex_widgets.dart';
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
    if (e is! KeyDownEvent) return false;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
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
          LogicalKeyboardKey.insert, LogicalKeyboardKey.delete, LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.numpadAdd, LogicalKeyboardKey.numpadSubtract,
        ].contains(k) ||
        (ctrl && [LogicalKeyboardKey.keyP, LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyB].contains(k));
  }

  Future<void> _ir(int i) async {
    final permiso = _secciones[i].permiso;
    if (permiso != null && !await autorizar(context, permiso)) return;
    setState(() {
      _actual = i;
      _visitadas.add(i);
    });
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

  Widget _barraSuperior() {
    final negocio = repos.ajustes.texto(Ajuste.nombreNegocio);
    final logo = repos.ajustes.texto(Ajuste.logoNegocio);
    final archivo = logo.isEmpty ? null : File(logo);
    final cajero = sesion.cajero;
    final turno = sesion.turno;
    return Container(
      height: 66,
      color: ExColor.tinta,
      padding: const EdgeInsets.only(left: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Extremo superior izquierdo: exBel™ chiquito y la tienda.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            const ExMarca(oscuro: true, tamano: 10),
            const SizedBox(height: 3),
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
                      child: Image.file(archivo, height: 26, width: 26, fit: BoxFit.contain),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: Text(negocio,
                        overflow: TextOverflow.ellipsis, style: ExTexto.titulo(20, color: ExColor.concreto)),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 20),
        for (var i = 0; i < _secciones.length; i++) _pestana(i),
        const Spacer(),
        if (cajero != null)
          InkWell(
            onTap: _cambiarCajero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                ExAvatar(cajero.nombre, size: 30),
                const SizedBox(width: 8),
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cajero.nombre, style: const TextStyle(color: ExColor.concreto, fontWeight: FontWeight.w600)),
                  Text(turno == null ? 'Sin turno' : 'Turno ${turno.numero}',
                      style: const TextStyle(color: ExColor.textoClaro2, fontSize: 12)),
                ]),
              ]),
            ),
          ),
        const Align(alignment: Alignment.topCenter, child: BotonesVentana(oscuro: true)),
      ]),
    );
  }

  Widget _pestana(int i) {
    final s = _secciones[i];
    final activa = i == _actual;
    return InkWell(
      onTap: () => _ir(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: activa ? ExColor.concreto : Colors.transparent,
          border: Border(top: BorderSide(color: activa ? ExColor.acento : Colors.transparent, width: 3)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(s.icono, size: 22, color: activa ? ExColor.tinta : ExColor.textoClaro),
          const SizedBox(height: 3),
          Text(
            s.tecla == null ? s.nombre : '${s.tecla} ${s.nombre}',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: activa ? FontWeight.w700 : FontWeight.w500,
              color: activa ? ExColor.tinta : ExColor.textoClaro,
            ),
          ),
        ]),
      ),
    );
  }
}
