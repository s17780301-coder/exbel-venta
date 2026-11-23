import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../../core/bascula.dart';
import '../../core/cajon.dart';
import '../../core/db.dart';
import '../../core/formato.dart';
import '../../core/tickets.dart';
import '../../data/ajustes_repo.dart';
import '../../data/ejemplo.dart';
import '../../data/importador.dart';
import '../../data/repos.dart';
import '../../models/modelos.dart';
import '../comun/dialogos.dart';
import '../comun/ex_widgets.dart';
import '../comun/impresion.dart';
import '../comun/multicaja_ui.dart';
import '../comun/importar_dialogo.dart';

import '../sesion.dart';
import '../tema/tema.dart';
import '../zoom.dart';

const versionExBel = '0.6.2';

/// Configuración de la tienda.
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

/// Una opción de la pantalla de Configuración (ícono + nombre).
class _Opcion {
  const _Opcion(this.nombre, this.icono, this.color, this.pagina);
  final String nombre;
  final IconData icono;
  final Color color;
  final Widget pagina;
}

const _verde = Color(0xFF3D7A55);
const _naranja = Color(0xFFB9824A);
const _azul = Color(0xFF4F6E9E);

/// Como en Eleventa: íconos por grupo.
final _grupos = <(String, List<_Opcion>)>[
  (
    'General',
    const [
      _Opcion('Opciones habilitadas', Icons.settings_suggest_outlined, ExColor.texto2, _Opciones()),
      _Opcion('Cajeros', Icons.badge_outlined, _azul, _Cajeros()),
      _Opcion('Base de Datos', Icons.storage_outlined, ExColor.indigo, _Respaldos()),
      _Opcion('Artículos Precargados', Icons.inventory_outlined, ExColor.rojo, _Precargados()),
      _Opcion('Facturación', Icons.receipt_long_outlined, ExColor.texto2, _Proximamente('Facturación',
          'Facturar (CFDI 4.0) requiere contratar un PAC que timbre las facturas. Se agregará en una próxima versión.')),
      _Opcion('Modificar Folios', Icons.format_list_numbered, ExColor.indigo, _Folios()),
      _Opcion('Multicaja', Icons.lan_outlined, _verde, SeccionMulticaja()),
    ]
  ),
  (
    'Personalización',
    const [
      _Opcion('Logotipo del Programa', Icons.image_outlined, _azul, _Logotipo()),
      _Opcion('Ticket', Icons.receipt_outlined, ExColor.texto2, _TicketCfg()),
      _Opcion('Formas de Pago', Icons.payments_outlined, ExColor.rojo, _FormasPago()),
      _Opcion('Impuestos', Icons.account_balance_outlined, _naranja, _Impuestos()),
      _Opcion('Corte', Icons.content_cut, ExColor.indigo, _Corte()),
      _Opcion('Símbolo de Moneda', Icons.attach_money, _verde, _Moneda()),
      _Opcion('Unidades de Medida', Icons.straighten, _azul, _Unidades()),
      _Opcion('Tamaño de Pantalla', Icons.zoom_in, ExColor.indigo, _Pantalla()),
    ]
  ),
  (
    'Dispositivos',
    const [
      _Opcion('Impresora de Tickets', Icons.print_outlined, ExColor.texto2, _Impresora()),
      _Opcion('Lector de Códigos', Icons.qr_code_scanner, ExColor.indigo, _Lector()),
      _Opcion('Cajón de Dinero', Icons.inbox_outlined, ExColor.texto2, _Cajon()),
      _Opcion('Báscula', Icons.scale_outlined, ExColor.rojo, _Bascula()),
      _Opcion('Terminal TPV', Icons.credit_card, ExColor.tinta, _Proximamente('Terminal TPV',
          'Por ahora, cobra en tu terminal (Clip, Mercado Pago, banco) y en exBel elige "Tarjeta" al cobrar. '
          'La conexión directa con terminales llegará en una próxima versión.')),
    ]
  ),
  (
    'Servicios',
    const [
      _Opcion('Recargas Electrónicas', Icons.phone_android, ExColor.texto2, _Proximamente('Recargas electrónicas',
          'Requiere contrato con un proveedor de recargas. Se agregará en una próxima versión.')),
      _Opcion('Pago de Servicios', Icons.request_quote_outlined, _verde, _Proximamente('Pago de servicios',
          'Requiere contrato con un proveedor de pago de servicios. Se agregará en una próxima versión.')),
      _Opcion('Compras / Proveedores', Icons.local_shipping_outlined, ExColor.rojo, _Proximamente('Compras y proveedores',
          'Mientras tanto, registra la mercancía que llega en F4 Inventario → Agregar mercancía, y los pagos al proveedor con F8 Salidas.')),
      _Opcion('Nube exBel', Icons.cloud_outlined, _azul, _Proximamente('Nube exBel',
          'Para ver tus ventas desde el celular y respaldar en internet. Se agregará en una próxima versión.')),
      _Opcion('Notificaciones por Correo', Icons.email_outlined, _azul, _Proximamente('Notificaciones por correo',
          'Para recibir el corte del día en tu correo. Se agregará en una próxima versión.')),
    ]
  ),
  (
    'Mantenimiento',
    const [
      _Opcion('Respaldo Automático', Icons.backup_outlined, _verde, _Respaldos()),
      _Opcion('Licencia', Icons.vpn_key_outlined, _naranja, _Licencia()),
      _Opcion('Actualizaciones', Icons.system_update_alt, _azul, _Actualizaciones()),
      _Opcion('Atajos y Acerca de', Icons.info_outline, ExColor.indigo, _Acerca()),
    ]
  ),
];

class _ConfigPageState extends State<ConfigPage> {
  _Opcion? _abierta;

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
    final abierta = _abierta;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        color: ExColor.indigo,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Text(abierta == null ? 'CONFIGURACIÓN' : 'CONFIGURACIÓN - ${abierta.nombre.toUpperCase()}',
            style: ExTexto.titulo(19, color: ExColor.blanco)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(backgroundColor: ExColor.blanco, side: const BorderSide(color: ExColor.borde, width: 1.4)),
            onPressed: abierta == null ? null : () => setState(() => _abierta = null),
            icon: const Icon(Icons.home_outlined, color: ExColor.acento),
            label: const Text('Mostrar todas las opciones'),
          ),
        ]),
      ),
      const Divider(),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: abierta == null
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final g in _grupos) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Text(g.$1, style: ExTexto.titulo(18, color: ExColor.indigo)),
                    ),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final o in g.$2) _icono(o)]),
                    const Divider(height: 18),
                  ],
                ])
              : Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 860), child: abierta.pagina),
                ),
        ),
      ),
    ]);
  }

  Widget _icono(_Opcion o) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => _abierta = o),
      child: SizedBox(
        width: 150,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(children: [
            Icon(o.icono, size: 38, color: o.color),
            const SizedBox(height: 6),
            Text(o.nombre, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15)),
          ]),
        ),
      ),
    );
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

class _Logotipo extends StatefulWidget {
  const _Logotipo();

  @override
  State<_Logotipo> createState() => _LogotipoState();
}

class _LogotipoState extends State<_Logotipo> {
  @override
  Widget build(BuildContext context) {
    final logo = repos.ajustes.texto(Ajuste.logoNegocio);
    final f = logo.isEmpty ? null : File(logo);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Nombre y logotipo de la tienda', 'Salen arriba a la izquierda y en los tickets.'),
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
    ]);
  }
}

class _TicketCfg extends StatefulWidget {
  const _TicketCfg();

  @override
  State<_TicketCfg> createState() => _TicketCfgState();
}

class _TicketCfgState extends State<_TicketCfg> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Ticket', 'El nombre, dirección y logotipo se cambian en "Logotipo del Programa".'),
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
    ]);
  }
}

class _Impresora extends StatefulWidget {
  const _Impresora();

  @override
  State<_Impresora> createState() => _ImpresoraState();
}

class _ImpresoraState extends State<_Impresora> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Impresora de tickets'),
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.print_outlined, size: 32),
        title: const Text('Impresora'),
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
      const SizedBox(height: 12),
      const Text('El ancho del papel (58 u 80 mm) se cambia en "Ticket".', style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Opciones extends StatelessWidget {
  const _Opciones();

  @override
  Widget build(BuildContext context) {
    return const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_Ventas(), SizedBox(height: 20), _Productos()]);
  }
}

class _FormasPago extends StatelessWidget {
  const _FormasPago();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Formas de pago', 'Efectivo, tarjeta, transferencia y pago mixto siempre están disponibles.'),
      const _Interruptor(Ajuste.usarCredito, 'Crédito (fiado)'),
      const _Campo(Ajuste.avisoCredito, 'Avisar al llegar a este % del tope de crédito', ayuda: 'Ej. 80 = avisa cuando el cliente ya usó el 80 % de su tope', numero: true),
      const _Interruptor(Ajuste.aceptarVales, 'Vales de despensa'),
      const _Interruptor(Ajuste.aceptarDolares, 'Dólares'),
      const _Campo(Ajuste.tipoCambio, 'Tipo de cambio (pesos por dólar)', pesos: true),
      const _Interruptor(Ajuste.permitirCobroMenor, 'Permitir cobrar en efectivo menos del total',
          'Normalmente apagado: así no se cobra de menos por error.'),
    ]);
  }
}

class _Impuestos extends StatefulWidget {
  const _Impuestos();

  @override
  State<_Impuestos> createState() => _ImpuestosState();
}

class _ImpuestosState extends State<_Impuestos> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Impuestos', 'Los precios de venta siempre incluyen los impuestos.'),
      Row(children: [
        const Text('IVA de los productos nuevos:  '),
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
      const SizedBox(height: 8),
      const _Interruptor(Ajuste.ticketDesglosarImpuestos, 'Desglosar IVA e IEPS en el ticket'),
      const SizedBox(height: 8),
      const Text('La mayoría de los alimentos básicos llevan IVA 0%. Refrescos, botanas y dulces suelen llevar IEPS. '
          'El IVA e IEPS de cada producto se cambia en el producto. Confírmalo con tu contador.',
          style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Folios extends StatelessWidget {
  const _Folios();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Modificar folios', 'Útil si vienes de otro sistema y quieres seguir con tu numeración.'),
      const _Campo(Ajuste.folioMinimo, 'El siguiente ticket empieza en el folio', numero: true,
          ayuda: 'Ej. 341572. Si ya hay folios mayores, se sigue con el siguiente.'),
    ]);
  }
}

class _Moneda extends StatelessWidget {
  const _Moneda();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Símbolo de moneda', 'Se usa en pantallas, tickets y reportes.'),
      const _Campo(Ajuste.simboloMoneda, 'Símbolo', ayuda: 'Normalmente \$'),
      const Text('El cambio se ve completo al volver a abrir exBel venta.', style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Unidades extends StatelessWidget {
  const _Unidades();

  @override
  Widget build(BuildContext context) {
    Widget fila(IconData i, String t, String d) => ListTile(
          leading: Icon(i, color: ExColor.indigo, size: 30),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(d),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Unidades de medida', 'Cada producto se vende de una de estas formas (se elige en el producto).'),
      fila(Icons.looks_one_outlined, 'Por unidad / pieza', 'Se cuenta en piezas enteras: refrescos, latas, paquetes.'),
      fila(Icons.scale_outlined, 'A granel (usa decimales)', 'Por kilo, litro o metro: 0.250 = 250 gramos. Se puede vender por importe (\$20 de jamón).'),
      fila(Icons.inventory_2_outlined, 'Como paquete (kit)', 'Un producto que lleva otros: al venderlo descuenta del inventario lo que contiene.'),
    ]);
  }
}

class _Lector extends StatefulWidget {
  const _Lector();

  @override
  State<_Lector> createState() => _LectorState();
}

class _LectorState extends State<_Lector> {
  final _c = TextEditingController();
  String _leido = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Lector de códigos', 'Los lectores USB funcionan como teclado: no hay que instalar nada.'),
      const Text('Prueba: haz clic en el cuadro y escanea un producto.'),
      const SizedBox(height: 8),
      TextField(
        controller: _c,
        autofocus: true,
        style: ExTexto.mono(22),
        decoration: const InputDecoration(labelText: 'Escanea aquí'),
        onSubmitted: (v) => setState(() {
          _leido = v;
          _c.clear();
        }),
      ),
      const SizedBox(height: 12),
      if (_leido.isNotEmpty)
        Text('Leído: $_leido  ✓  (el lector manda ENTER al final, así debe ser)',
            style: const TextStyle(color: ExColor.verde, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      const Text('Si el código no sale completo o no se agrega solo, configura el lector para que mande "Enter" (CR) al final; '
          'viene en el manual del lector.', style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Precargados extends StatelessWidget {
  const _Precargados();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Artículos precargados'),
      ExSeccion(
        titulo: 'Traer tu catálogo de Eleventa',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Exporta tu catálogo desde Eleventa (F3 Productos → Catálogo → Exportar) e impórtalo aquí. '
              'Se reconocen las columnas solas.'),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () async {
              if (await autorizar(context, Permiso.productos) && context.mounted) await importarDesdeArchivo(context);
            },
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Importar productos (Excel)'),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      ExSeccion(
        titulo: 'Productos de ejemplo',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Unos 40 productos típicos de abarrotes con sus departamentos, para practicar.'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              if (!await autorizar(context, Permiso.productos) || !context.mounted) return;
              await cargarEjemplo(cajeroId: sesion.cajero?.id);
              avisarCambio();
              if (context.mounted) aviso(context, 'Productos de ejemplo cargados.');
            },
            icon: const Icon(Icons.science_outlined),
            label: const Text('Cargar productos de ejemplo'),
          ),
        ]),
      ),
    ]);
  }
}

class _Proximamente extends StatelessWidget {
  const _Proximamente(this.nombre, this.texto);
  final String nombre;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo(nombre),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: ExColor.lavanda.withOpacity(0.35), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.schedule, color: ExColor.indigo, size: 30),
          const SizedBox(width: 14),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 16))),
        ]),
      ),
    ]);
  }
}

class _Licencia extends StatelessWidget {
  const _Licencia();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Licencia'),
      ListTile(leading: const Icon(Icons.storefront), title: Text(repos.ajustes.texto(Ajuste.nombreNegocio)), subtitle: const Text('Tienda')),
      const ListTile(leading: Icon(Icons.verified_outlined), title: Text('exBel venta'), subtitle: Text('Licencia de prueba')),
      const Text('La activación de licencias llegará en una próxima versión.', style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Actualizaciones extends StatelessWidget {
  const _Actualizaciones();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Actualizaciones'),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('Versión instalada'), subtitle: Text(versionExBel)),
      const Text('Para actualizar, abre el instalador nuevo de exBel venta: se instala encima y tus datos se conservan. '
          'La actualización automática llegará en una próxima versión.', style: TextStyle(color: ExColor.texto2)),
    ]);
  }
}

class _Ventas extends StatelessWidget {
  const _Ventas();

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Opciones habilitadas'),
      const _Interruptor(Ajuste.venderSinExistencia, 'Permitir vender aunque no haya existencia',
          'Si lo apagas, no deja vender más de lo que hay en inventario.'),
      const _Interruptor(Ajuste.permitirComun, 'Permitir artículo común (Ctrl+P)', 'Vender algo que no está en el catálogo.'),
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
      _titulo('Productos'),
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
  List<(String, String)> _puertos = [];
  bool _cargando = true;
  bool _buscando = false;
  String _avance = '';
  ConfigBascula? _config;
  final _lector = LectorBascula.instancia;
  bool _leyendo = false;

  @override
  void initState() {
    super.initState();
    _config = configBascula(repos.ajustes);
    _cargarPuertos();
  }

  @override
  void dispose() {
    if (_leyendo) _lector.soltar();
    super.dispose();
  }

  Future<void> _cargarPuertos() async {
    setState(() => _cargando = true);
    final l = await puertosCom();
    if (mounted) {
      setState(() {
        _puertos = l;
        _cargando = false;
      });
    }
  }

  Future<void> _usar(ConfigBascula? c) async {
    await guardarConfigBascula(repos.ajustes, c);
    setState(() => _config = c);
    if (_leyendo) {
      _lector.soltar();
      _leyendo = false;
    }
    if (c != null) {
      _leyendo = true;
      await _lector.usar(c);
    }
    if (mounted) setState(() {});
  }

  Future<void> _buscar() async {
    if (_puertos.isEmpty) await _cargarPuertos();
    if (_puertos.isEmpty) return;
    if (_leyendo) {
      _lector.soltar();
      _leyendo = false;
    }
    setState(() {
      _buscando = true;
      _avance = 'Buscando…';
    });
    final r = await buscarBascula([for (final x in _puertos) x.$1], avance: (t) {
      if (mounted) setState(() => _avance = t);
    });
    if (!mounted) return;
    setState(() => _buscando = false);
    if (r == null) {
      setState(() => _avance = 'No contestó ninguna báscula. Revisa que esté prendida y conectada, pon algo encima y '
          'vuelve a buscar. Si sigue igual, configúrala a mano con los datos de su manual.');
      return;
    }
    setState(() => _avance = 'Báscula encontrada en ${r.$1.puerto}. Respondió: "${r.$2}"');
    await _usar(r.$1);
  }

  Widget _desplegable<T>(String etiqueta, T valor, List<(T, String)> opciones, void Function(T) cambio) => SizedBox(
        width: 230,
        child: DropdownButtonFormField<T>(
          value: opciones.any((o) => o.$1 == valor) ? valor : null,
          decoration: InputDecoration(labelText: etiqueta),
          items: [for (final o in opciones) DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null) cambio(v);
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = _config;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('Báscula conectada (USB)', 'Para pesar en el mostrador: al vender un producto a granel se llena solo el peso.'),
      Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilledButton.icon(
          onPressed: _buscando || _cargando ? null : _buscar,
          icon: const Icon(Icons.search),
          label: const Text('Buscar báscula automáticamente'),
        ),
        OutlinedButton.icon(
          onPressed: _cargando || _buscando ? null : _cargarPuertos,
          icon: const Icon(Icons.refresh),
          label: const Text('Volver a revisar puertos'),
        ),
        if (c != null)
          OutlinedButton.icon(
            onPressed: _buscando ? null : () => _usar(null),
            icon: const Icon(Icons.link_off),
            label: const Text('Quitar báscula'),
          ),
      ]),
      const SizedBox(height: 10),
      if (_cargando) const LinearProgressIndicator(),
      if (_buscando) const LinearProgressIndicator(),
      if (_avance.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_avance)),
      if (!_cargando && _puertos.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
              'Windows no muestra ningún puerto COM. Conecta la báscula por USB y préndela. Si aun así no aparece, le falta su '
              'controlador (driver): viene en el disco o en la página del fabricante, normalmente "CH340", "Prolific" o "FTDI".',
              style: TextStyle(color: ExColor.rojo)),
        ),
      if (_puertos.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('Puertos en esta computadora: ${_puertos.map((x) => x.$2).join(', ')}', style: const TextStyle(color: ExColor.texto2)),
      ],
      const SizedBox(height: 16),
      if (c != null)
        ExSeccionSimple(
          child: Row(children: [
            const Icon(Icons.scale_outlined, size: 36, color: ExColor.indigo),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ValueListenableBuilder<double?>(
                  valueListenable: _lector.peso,
                  builder: (_, v, __) =>
                      Text(_leyendo ? (v == null ? '— kg' : '${v.toStringAsFixed(3)} kg') : 'Configurada', style: ExTexto.mono(28)),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: _lector.estado,
                  builder: (_, e, __) => Text(e.isEmpty ? c.toString() : e,
                      style: TextStyle(color: e.isEmpty ? ExColor.texto2 : ExColor.rojo)),
                ),
              ]),
            ),
            if (!_leyendo)
              OutlinedButton(
                onPressed: () async {
                  _leyendo = true;
                  await _lector.usar(c);
                  if (mounted) setState(() {});
                },
                child: const Text('Probar lectura'),
              ),
          ]),
        ),
      const SizedBox(height: 14),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Configurar a mano', style: TextStyle(fontWeight: FontWeight.w600)),
        children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _desplegable<String>('Puerto', c?.puerto ?? '', [for (final x in _puertos) (x.$1, x.$2)],
                (v) => _usar(ConfigBascula(puerto: v, baudios: c?.baudios ?? 9600, formato: c?.formato ?? '8N1', pedido: c?.pedido ?? 'P'))),
            if (c != null) ...[
              _desplegable<int>('Velocidad', c.baudios, [for (final b in const [1200, 2400, 4800, 9600, 19200, 38400]) (b, '$b')],
                  (v) => _usar(ConfigBascula(puerto: c.puerto, baudios: v, formato: c.formato, pedido: c.pedido))),
              _desplegable<String>('Datos', c.formato, const [('8N1', '8 bits, sin paridad'), ('7E1', '7 bits, paridad par')],
                  (v) => _usar(ConfigBascula(puerto: c.puerto, baudios: c.baudios, formato: v, pedido: c.pedido))),
              _desplegable<String>(
                  'Pedir el peso con',
                  c.pedido,
                  const [('P', 'P (Torrey, Rhino, Noval)'), ('W', 'W (CAS, Toledo)'), ('ENQ', 'ENQ'), ('', 'Nada: manda sola')],
                  (v) => _usar(ConfigBascula(puerto: c.puerto, baudios: c.baudios, formato: c.formato, pedido: v))),
            ],
          ]),
          const SizedBox(height: 8),
        ],
      ),
      const Divider(height: 36),
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
    if (esCajaConectada) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _titulo('Respaldos'),
        const Text('Esta es una caja conectada: la información y los respaldos están en la caja principal.',
            style: TextStyle(fontSize: 16)),
      ]);
    }
    return _construir(context);
  }

  Widget _construir(BuildContext context) {
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
