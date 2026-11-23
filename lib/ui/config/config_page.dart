import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../../core/cajon.dart';
import '../../core/db.dart';
import '../../core/formato.dart';
import '../../core/tickets.dart';
import '../../data/ajustes_repo.dart';
import '../../data/importador.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_widgets.dart';
import '../comun/impresion.dart';
import '../sesion.dart';
import '../tema/tema.dart';
import '../zoom.dart';

const versionExBel = '0.3.3';

/// Configuración de la tienda.
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

const _secciones = [
  ('Tienda y ticket', Icons.storefront_outlined),
  ('Pantalla', Icons.zoom_in),
  ('Ventas y cobro', Icons.point_of_sale),
  ('Productos e impuestos', Icons.inventory_2_outlined),
  ('Cajeros y permisos', Icons.badge_outlined),
  ('Corte de caja', Icons.calculate_outlined),
  ('Báscula', Icons.scale_outlined),
  ('Cajón de dinero', Icons.inbox_outlined),
  ('Respaldos', Icons.backup_outlined),
  ('Acerca de exBel venta', Icons.info_outline),
];

class _ConfigPageState extends State<ConfigPage> {
  int _sec = 0;

  @override
  void initState() {
    super.initState();
    cambiosDatos.addListener(_refrescar);
  }

  @override
  void dispose() {
    cambiosDatos.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 260,
        color: ExColor.blanco,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text('Configuración', style: ExTexto.titulo(26)),
          ),
          for (var i = 0; i < _secciones.length; i++)
            ListTile(
              selected: _sec == i,
              selectedTileColor: ExColor.lavanda.withOpacity(0.5),
              selectedColor: ExColor.tinta,
              leading: Icon(_secciones[i].$2),
              title: Text(_secciones[i].$1),
              onTap: () => setState(() => _sec = i),
            ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: switch (_sec) {
              0 => const _Tienda(),
              1 => const _Pantalla(),
              2 => const _Ventas(),
              3 => const _Productos(),
              4 => const _Cajeros(),
              5 => const _Corte(),
              6 => const _Bascula(),
              7 => const _Cajon(),
              8 => const _Respaldos(),
              _ => const _Acerca(),
            },
          ),
        ),
      ),
    ]);
  }
}

// ---------- Piezas comunes ----------

class _Interruptor extends StatefulWidget {
  const _Interruptor(this.clave, this.titulo, [this.ayuda]);
  final String clave;
  final String titulo;
  final String? ayuda;

  @override
  State<_Interruptor> createState() => _InterruptorState();
}

class _InterruptorState extends State<_Interruptor> {
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(widget.titulo),
      subtitle: widget.ayuda == null ? null : Text(widget.ayuda!),
      value: repos.ajustes.si(widget.clave),
      onChanged: (v) async {
        await repos.ajustes.guardarSi(widget.clave, v);
        setState(() {});
        avisarCambio();
      },
    );
  }
}

/// Campo que se guarda al salir de él o con ENTER.
class _Campo extends StatefulWidget {
  const _Campo(this.clave, this.etiqueta, {this.ayuda, this.pesos = false, this.numero = false});
  final String clave;
  final String etiqueta;
  final String? ayuda;
  final bool pesos;
  final bool numero;

  @override
  State<_Campo> createState() => _CampoState();
}

class _CampoState extends State<_Campo> {
  late final _c = TextEditingController(
      text: widget.pesos
          ? (repos.ajustes.entero(widget.clave) / 100).toStringAsFixed(2)
          : repos.ajustes.texto(widget.clave));
  final _foco = FocusNode();

  @override
  void initState() {
    super.initState();
    _foco.addListener(() {
      if (!_foco.hasFocus) _guardar();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _foco.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    var v = _c.text.trim();
    if (widget.pesos) v = '${leerPesos(v) ?? 0}';
    if (widget.numero) v = formatoCantidad(leerCantidad(v) ?? 0);
    if (v == repos.ajustes.texto(widget.clave)) return;
    await repos.ajustes.guardar(widget.clave, v);
    avisarCambio();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: _c,
        focusNode: _foco,
        decoration: InputDecoration(labelText: widget.etiqueta, helperText: widget.ayuda),
        onSubmitted: (_) => _guardar(),
      ),
    );
  }
}

Widget _titulo(String t, [String? sub]) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: ExTexto.titulo(24)),
        if (sub != null) Text(sub, style: const TextStyle(color: ExColor.texto2)),
      ]),
    );

// ---------- Secciones ----------

class _Tienda extends StatefulWidget {
  const _Tienda();

  @override
  State<_Tienda> createState() => _TiendaState();
}

class _TiendaState extends State<_Tienda> {
  @override
  Widget build(BuildContext context) {
    final logo = repos.ajustes.texto(Ajuste.logoNegocio);
    final f = logo.isEmpty ? null : File(logo);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Tienda y ticket', 'Estos datos salen arriba en la pantalla y en los tickets.'),
      ExSeccion(
        child: Row(children: [
          if (f != null && f.existsSync())
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(f, height: 64, width: 64, fit: BoxFit.contain)),
            ),
          Expanded(child: Text(repos.ajustes.texto(Ajuste.nombreNegocio), style: ExTexto.titulo(26))),
          OutlinedButton(
            onPressed: () async {
              await editarNegocio(context);
              setState(() {});
            },
            child: const Text('Cambiar nombre y logotipo'),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      const _Campo(Ajuste.direccion, 'Dirección'),
      const _Campo(Ajuste.telefono, 'Teléfono'),
      const _Campo(Ajuste.rfc, 'RFC (opcional)'),
      const _Campo(Ajuste.ticketEncabezado, 'Texto extra arriba del ticket', ayuda: 'Ej. horario o redes sociales'),
      const _Campo(Ajuste.ticketPie, 'Mensaje al final del ticket'),
      const _Interruptor(Ajuste.ticketDesglosarImpuestos, 'Desglosar IVA e IEPS en el ticket'),
      const SizedBox(height: 8),
      Row(children: [
        const Text('Ancho del papel:  '),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '58', label: Text('58 mm')),
            ButtonSegment(value: '80', label: Text('80 mm')),
          ],
          selected: {repos.ajustes.texto(Ajuste.ticketAncho)},
          onSelectionChanged: (s) async {
            await repos.ajustes.guardar(Ajuste.ticketAncho, s.first);
            setState(() {});
          },
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        const Text('Al cobrar con F1:  '),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'preguntar', label: Text('Ver ticket antes')),
            ButtonSegment(value: 'siempre', label: Text('Imprimir directo')),
          ],
          selected: {repos.ajustes.texto(Ajuste.impresion) == 'siempre' ? 'siempre' : 'preguntar'},
          onSelectionChanged: (s) async {
            await repos.ajustes.guardar(Ajuste.impresion, s.first);
            setState(() {});
          },
        ),
      ]),
      const SizedBox(height: 16),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.print_outlined),
        title: const Text('Impresora de tickets'),
        subtitle: Text(impresoraElegida()),
        trailing: Wrap(spacing: 8, children: [
          OutlinedButton(
            onPressed: () async {
              await elegirImpresora(context);
              setState(() {});
            },
            child: const Text('Elegir'),
          ),
          OutlinedButton(
            onPressed: () async {
              final pdf = await ticketCorte(Corte(
                titulo: 'Ticket de prueba',
                fondoCentavos: 0, ventasCentavos: 0, gananciaCentavos: 0, numeroVentas: 0, efectivoCentavos: 0,
                tarjetaCentavos: 0, valesCentavos: 0, dolaresCentavos: 0, creditoCentavos: 0,
                abonosEfectivoCentavos: 0, abonosOtrosCentavos: 0, entradasCentavos: 0, salidasCentavos: 0,
                devolucionesCentavos: 0, devolucionesEfectivoCentavos: 0, ivaCentavos: 0, iepsCentavos: 0,
                porDepartamento: const [],
              ));
              if (context.mounted) await vistaPrevia(context, pdf, titulo: 'Ticket de prueba');
            },
            child: const Text('Imprimir prueba'),
          ),
        ]),
      ),
    ]);
  }
}

class _Ventas extends StatelessWidget {
  const _Ventas();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Ventas y cobro'),
      const _Interruptor(Ajuste.venderSinExistencia, 'Permitir vender aunque no haya existencia',
          'Si lo apagas, no deja vender más de lo que hay en inventario.'),
      const _Interruptor(Ajuste.permitirComun, 'Permitir artículo común (Ctrl+P)', 'Vender algo que no está en el catálogo.'),
      const _Interruptor(Ajuste.usarCredito, 'Vender a crédito (fiado)'),
      const _Interruptor(Ajuste.aceptarVales, 'Aceptar vales de despensa'),
      const _Interruptor(Ajuste.aceptarDolares, 'Aceptar dólares'),
      const _Campo(Ajuste.tipoCambio, 'Tipo de cambio (pesos por dólar)', pesos: true),
      const _Interruptor(Ajuste.permitirCobroMenor, 'Permitir cobrar en efectivo menos del total',
          'Normalmente apagado: así no se cobra de menos por error.'),
    ]);
  }
}

class _Productos extends StatefulWidget {
  const _Productos();

  @override
  State<_Productos> createState() => _ProductosState();
}

class _ProductosState extends State<_Productos> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Productos e impuestos'),
      const _Interruptor(Ajuste.usarInventario, 'Los productos nuevos usan inventario'),
      const _Campo(Ajuste.gananciaSugerida, 'Ganancia sugerida para productos nuevos (%)', numero: true),
      const SizedBox(height: 6),
      Row(children: [
        const Text('Al agregar mercancía, el costo es:  '),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '0', label: Text('El último costo')),
            ButtonSegment(value: '1', label: Text('Costo promedio')),
          ],
          selected: {repos.ajustes.texto(Ajuste.costoPromedio)},
          onSelectionChanged: (s) async {
            await repos.ajustes.guardar(Ajuste.costoPromedio, s.first);
            setState(() {});
          },
        ),
      ]),
      const SizedBox(height: 16),
      Row(children: [
        const Text('IVA por omisión en productos nuevos:  '),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: '0', label: Text('0%')),
            ButtonSegment(value: '8', label: Text('8%')),
            ButtonSegment(value: '16', label: Text('16%')),
          ],
          selected: {formatoCantidad(repos.ajustes.numero(Ajuste.ivaPorOmision))},
          onSelectionChanged: (s) async {
            await repos.ajustes.guardar(Ajuste.ivaPorOmision, s.first);
            setState(() {});
          },
        ),
      ]),
      const SizedBox(height: 10),
      const Text('La mayoría de los alimentos básicos llevan IVA 0%. Refrescos, botanas y dulces suelen llevar IEPS. '
          'Confírmalo con tu contador.', style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Corte extends StatelessWidget {
  const _Corte();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Corte de caja'),
      const _Campo(Ajuste.fondoSugerido, 'Fondo de caja sugerido al abrir turno', pesos: true),
      const _Interruptor(Ajuste.corteMostrarEsperado, 'Mostrar al cajero cuánto dinero debe haber',
          'Si lo apagas, el cajero cuenta "a ciegas" y solo el dueño ve la diferencia.'),
    ]);
  }
}

class _Bascula extends StatefulWidget {
  const _Bascula();

  @override
  State<_Bascula> createState() => _BasculaState();
}

class _BasculaState extends State<_Bascula> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Báscula con etiquetas', 'Para básculas que imprimen etiqueta con código de barras (salchichonería, cremería).'),
      const _Campo(Ajuste.basculaPrefijo, 'Prefijo de la etiqueta', ayuda: 'Normalmente 20. Vacío = desactivado'),
      Row(children: [
        const Text('La etiqueta trae:  '),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'peso', label: Text('El peso (gramos)')),
            ButtonSegment(value: 'precio', label: Text('El importe (centavos)')),
          ],
          selected: {repos.ajustes.texto(Ajuste.basculaModo)},
          onSelectionChanged: (s) async {
            await repos.ajustes.guardar(Ajuste.basculaModo, s.first);
            setState(() {});
          },
        ),
      ]),
      const SizedBox(height: 14),
      const Text('Formato: prefijo (2) + código del producto (5) + peso o importe (5) + dígito verificador.\n'
          'Ejemplo: 20 01020 00250 X  →  producto 01020 (o 1020), 0.250 kg.',
          style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Pantalla extends StatefulWidget {
  const _Pantalla();

  @override
  State<_Pantalla> createState() => _PantallaState();
}

class _PantallaState extends State<_Pantalla> {
  @override
  Widget build(BuildContext context) {
    const opciones = [(1.0, 'Normal'), (1.15, 'Grande'), (1.3, 'Más grande'), (1.5, 'Muy grande')];
    final actual = zoomPantalla.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Tamaño de la pantalla', 'Agranda letras, botones y tablas. "Grande" se parece al tamaño de Eleventa.'),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final o in opciones)
          ChoiceChip(
            label: Padding(padding: const EdgeInsets.all(6), child: Text('${o.$2} (${(o.$1 * 100).round()} %)')),
            selected: (actual - o.$1).abs() < 0.01,
            onSelected: (_) async {
              zoomPantalla.value = o.$1;
              await repos.ajustes.guardar(Ajuste.zoom, '${o.$1}');
              setState(() {});
            },
          ),
      ]),
      const SizedBox(height: 14),
      const Text('Si en tu monitor algo no cabe, elige un tamaño menor.', style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Cajon extends StatefulWidget {
  const _Cajon();

  @override
  State<_Cajon> createState() => _CajonState();
}

class _CajonState extends State<_Cajon> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Cajón de dinero', 'Para cajones conectados a la impresora de tickets con cable de teléfono (RJ11).'),
      const _Interruptor(Ajuste.cajonAbrir, 'Abrir el cajón al cobrar con efectivo',
          'También aparece el botón "Abrir cajón" en Ventas.'),
      const _Campo(Ajuste.cajonImpresora, 'Nombre compartido de la impresora de tickets',
          ayuda: 'Ej. TICKETS. Ver pasos abajo.'),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () async {
            final e = await abrirCajon();
            if (context.mounted) aviso(context, e ?? 'Listo: se mandó la orden de abrir el cajón.');
          },
          icon: const Icon(Icons.inbox_outlined),
          label: const Text('Probar: abrir cajón'),
        ),
      ),
      const SizedBox(height: 18),
      const Text('Cómo compartir la impresora en Windows', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const Text('1. Abre Configuración de Windows → Bluetooth y dispositivos → Impresoras y escáneres.\n'
          '2. Elige tu impresora de tickets → Propiedades de impresora → pestaña Compartir.\n'
          '3. Marca "Compartir esta impresora" y ponle un nombre corto sin espacios, por ejemplo TICKETS.\n'
          '4. Escribe ese mismo nombre aquí arriba y prueba.'),
    ]);
  }
}

class _Respaldos extends StatelessWidget {
  const _Respaldos();

  Future<void> _respaldar(BuildContext context) async {
    final carpeta = await FilePicker.platform.getDirectoryPath(dialogTitle: '¿Dónde guardo el respaldo? (ej. una USB)');
    if (carpeta == null) return;
    try {
      final r = await respaldarBase(repos.db, carpeta);
      if (context.mounted) aviso(context, 'Respaldo guardado: $r');
    } catch (e) {
      if (context.mounted) aviso(context, 'No se pudo respaldar: $e');
    }
  }

  Future<void> _restaurar(BuildContext context) async {
    if (!await confirmar(context, 'Restaurar respaldo',
        'Se reemplazan TODOS los datos actuales por los del respaldo. exBel venta se cerrará y deberás abrirlo de nuevo.',
        si: 'Elegir respaldo', peligro: true)) {
      return;
    }
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['db']);
    final origen = r?.files.single.path;
    if (origen == null) return;
    try {
      // Primero un respaldo de lo actual, por si acaso.
      await respaldoAutomatico(repos.db);
      final destino = await AppDb.rutaBase();
      await repos.db.close();
      await File(origen).copy(destino);
      await windowManager.setFullScreen(false);
      await windowManager.close();
      exit(0);
    } catch (e) {
      if (context.mounted) aviso(context, 'No se pudo restaurar: $e');
    }
  }

  Future<void> _borrar(BuildContext context) async {
    if (!sesion.puede(Permiso.configuracion)) return aviso(context, 'Solo el administrador puede borrar datos.');
    final r = await showDialog<(bool, bool, bool)>(context: context, builder: (_) => const _Borrar());
    if (r == null || !context.mounted) return;
    final ok = await intentar(context, () async {
      await borrarDatos(productos: r.$1, clientes: r.$2, ventas: r.$3, turnoActualId: sesion.turno?.id);
    });
    if (ok && context.mounted) {
      avisarCambio();
      aviso(context, 'Listo. Se guardó un respaldo antes de borrar.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Respaldos', 'exBel venta guarda un respaldo automático cada vez que se cierra un turno (los últimos 10).'),
      ExSeccion(
        titulo: 'Respaldo manual',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Guarda una copia de toda la información en una USB o carpeta. Hazlo al menos una vez por semana.'),
          const SizedBox(height: 12),
          Wrap(spacing: 10, children: [
            FilledButton.icon(
                onPressed: () => _respaldar(context), icon: const Icon(Icons.save_alt), label: const Text('Respaldar ahora')),
            OutlinedButton.icon(
                onPressed: () => _restaurar(context), icon: const Icon(Icons.restore), label: const Text('Restaurar un respaldo')),
            TextButton.icon(
              onPressed: () async {
                final c = p.join((await AppDb.carpeta()).path, 'respaldos');
                await Directory(c).create(recursive: true);
                if (Platform.isWindows) await Process.run('explorer', [c]);
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Ver respaldos automáticos'),
            ),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      ExSeccion(
        titulo: 'Empezar de cero',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Borra los productos de prueba, clientes o ventas antes de meter el inventario real '
              '(por ejemplo, el que traes de Eleventa). Los cajeros y la configuración se conservan.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: ExColor.rojo),
            onPressed: () => _borrar(context),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Borrar datos…'),
          ),
        ]),
      ),
    ]);
  }
}

class _Borrar extends StatefulWidget {
  const _Borrar();

  @override
  State<_Borrar> createState() => _BorrarState();
}

class _BorrarState extends State<_Borrar> {
  bool _productos = true;
  bool _clientes = true;
  bool _ventas = true;
  final _confirmar = TextEditingController();

  @override
  void dispose() {
    _confirmar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listo = _confirmar.text.trim().toUpperCase() == 'BORRAR' && (_productos || _clientes || _ventas);
    return AlertDialog(
      title: const Text('Borrar datos'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CheckboxListTile(
              value: _productos,
              onChanged: (v) => setState(() => _productos = v ?? false),
              title: const Text('Productos, departamentos e inventario')),
          CheckboxListTile(
              value: _clientes, onChanged: (v) => setState(() => _clientes = v ?? false), title: const Text('Clientes y créditos')),
          CheckboxListTile(
              value: _ventas,
              onChanged: (v) => setState(() => _ventas = v ?? false),
              title: const Text('Ventas, cortes y movimientos de caja')),
          const SizedBox(height: 10),
          const Text('Esto no se puede deshacer (solo restaurando el respaldo). Escribe BORRAR para confirmar.'),
          const SizedBox(height: 8),
          TextField(controller: _confirmar, autofocus: true, onChanged: (_) => setState(() {})),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: ExColor.rojo),
          onPressed: listo ? () => Navigator.pop(context, (_productos, _clientes, _ventas)) : null,
          child: const Text('Borrar'),
        ),
      ],
    );
  }
}

class _Cajeros extends StatefulWidget {
  const _Cajeros();

  @override
  State<_Cajeros> createState() => _CajerosState();
}

class _CajerosState extends State<_Cajeros> {
  List<Cajero> _l = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final l = await repos.cajeros.listar();
    if (mounted) setState(() => _l = l);
  }

  Future<void> _editar([Cajero? c]) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _FormCajero(c));
    if (ok == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: _titulo('Cajeros y permisos', 'Cada cajero entra con su usuario y contraseña.')),
        FilledButton.icon(onPressed: () => _editar(), icon: const Icon(Icons.add), label: const Text('Nuevo cajero')),
      ]),
      for (final c in _l)
        Card(
          child: ListTile(
            leading: ExAvatar(c.nombre),
            title: Text(c.nombre),
            subtitle: Text(c.administrador
                ? 'Usuario: ${c.usuario} · Administrador (todos los permisos)'
                : 'Usuario: ${c.usuario} · ${c.permisos.length} permisos'),
            trailing: Wrap(spacing: 4, children: [
              IconButton(onPressed: () => _editar(c), icon: const Icon(Icons.edit_outlined)),
              if (c.id != sesion.cajero?.id)
                IconButton(
                  onPressed: () async {
                    if (await confirmar(context, 'Eliminar cajero', '¿Eliminar a ${c.nombre}?', si: 'Eliminar', peligro: true) &&
                        context.mounted) {
                      await intentar(context, () => repos.cajeros.eliminar(c.id));
                      _cargar();
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                ),
            ]),
          ),
        ),
    ]);
  }
}

class _FormCajero extends StatefulWidget {
  const _FormCajero(this.c);
  final Cajero? c;

  @override
  State<_FormCajero> createState() => _FormCajeroState();
}

class _FormCajeroState extends State<_FormCajero> {
  late final _nombre = TextEditingController(text: widget.c?.nombre ?? '');
  late final _usuario = TextEditingController(text: widget.c?.usuario ?? '');
  final _clave = TextEditingController();
  late bool _admin = widget.c?.administrador ?? false;
  late final Set<String> _permisos = {...?widget.c?.permisos};

  @override
  void dispose() {
    _nombre.dispose();
    _usuario.dispose();
    _clave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.c == null ? 'Nuevo cajero' : 'Modificar cajero'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _nombre, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _usuario, decoration: const InputDecoration(labelText: 'Usuario'))),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _clave,
                  obscureText: true,
                  decoration: InputDecoration(
                      labelText: 'Contraseña', helperText: widget.c == null ? null : 'Vacío = no cambiarla'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _admin,
              onChanged: (v) => setState(() => _admin = v),
              title: const Text('Administrador (dueño)'),
              subtitle: const Text('Puede hacer todo, incluida la configuración.'),
            ),
            if (!_admin) ...[
              const Divider(),
              const Text('Permisos', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text('Lo que no tenga permitido le pedirá la contraseña de un supervisor.',
                  style: TextStyle(color: ExColor.texto2, fontSize: 12)),
              for (final e in Permiso.todos.entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _permisos.contains(e.key),
                  onChanged: (v) => setState(() => v == true ? _permisos.add(e.key) : _permisos.remove(e.key)),
                  title: Text(e.value),
                ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () async {
            final ok = await intentar(
              context,
              () => repos.cajeros.guardar(
                id: widget.c?.id,
                usuario: _usuario.text,
                nombre: _nombre.text,
                clave: _clave.text,
                administrador: _admin,
                permisos: _permisos,
              ),
            );
            if (ok && context.mounted) Navigator.pop(context, true);
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _Acerca extends StatelessWidget {
  const _Acerca();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const ExMarca(tamano: 30),
      const SizedBox(height: 6),
      Text('venta · versión $versionExBel', style: ExTexto.texto(16, color: ExColor.texto2)),
      const SizedBox(height: 20),
      const Text('Punto de venta para tiendas de abarrotes, misceláneas y comercios.\n'
          'Funciona sin internet. Tus datos se guardan en esta computadora.'),
      const SizedBox(height: 20),
      const Text('Atajos de teclado', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('F1 Ventas · F2 Clientes · F3 Productos · F4 Inventario\n'
          'En ventas: F5 cambiar ticket · F6 pendiente · F7 entradas · F8 salidas · F9 verificador · '
          'F10 buscador universal (productos, clientes y folios, en cualquier pantalla) · F11 mayoreo · F12 cobrar · INS varios · Ctrl+P artículo común · Ctrl+D descuento · '
          'Ctrl+B ventas del día · Supr borrar · + y − cambian la cantidad del artículo seleccionado\n'
          'Al cobrar: F1 cobrar e imprimir · F2 solo cobrar · Esc cancelar'),
    ]);
  }
}
