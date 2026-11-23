import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Versión personalizada para esta tienda.
const tiendaPersonalizada = 'Miscelánea Karina';

/// Claves de configuración y su valor por omisión.
abstract final class Ajuste {
  // Negocio y ticket.
  static const nombreNegocio = 'nombre_negocio';
  static const logoNegocio = 'logo_negocio';
  static const direccion = 'direccion';
  static const telefono = 'telefono';
  static const rfc = 'rfc';
  static const ticketEncabezado = 'ticket_encabezado';
  static const ticketPie = 'ticket_pie';
  static const ticketDesglosarImpuestos = 'ticket_desglosar_impuestos';
  static const ticketAncho = 'ticket_ancho'; // 58 u 80 (mm)

  // Venta.
  static const usarInventario = 'usar_inventario';
  static const venderSinExistencia = 'vender_sin_existencia';
  static const permitirComun = 'permitir_comun';
  static const usarCredito = 'usar_credito';
  static const permitirCobroMenor = 'permitir_cobro_menor';
  static const impresion = 'impresion'; // preguntar | siempre | nunca
  static const tipoCambio = 'tipo_cambio_centavos';
  static const aceptarDolares = 'aceptar_dolares';
  static const aceptarVales = 'aceptar_vales';

  // Productos.
  static const gananciaSugerida = 'ganancia_sugerida';
  static const costoPromedio = 'costo_promedio'; // 1 promedio, 0 último costo
  static const ivaPorOmision = 'iva_por_omision';

  // Corte.
  static const corteMostrarEsperado = 'corte_mostrar_esperado';
  static const fondoSugerido = 'fondo_sugerido_centavos';

  // Báscula (código de etiqueta con peso o precio).
  static const basculaPrefijo = 'bascula_prefijo';
  static const basculaModo = 'bascula_modo'; // peso | precio

  // Folios y moneda.
  static const folioMinimo = 'folio_minimo';
  static const simboloMoneda = 'simbolo_moneda';

  // Pantalla: tamaño de todo (1 = 100 %).
  static const zoom = 'zoom';

  // Cajón de dinero conectado a la impresora de tickets.
  static const cajonAbrir = 'cajon_abrir';
  static const cajonImpresora = 'cajon_impresora';

  static const omision = <String, String>{
    nombreNegocio: tiendaPersonalizada,
    logoNegocio: '',
    direccion: '',
    telefono: '',
    rfc: '',
    ticketEncabezado: '',
    ticketPie: '¡Gracias por su compra!',
    ticketDesglosarImpuestos: '0',
    ticketAncho: '58',
    usarInventario: '1',
    venderSinExistencia: '1',
    permitirComun: '1',
    usarCredito: '1',
    permitirCobroMenor: '0',
    impresion: 'preguntar',
    tipoCambio: '1800',
    aceptarDolares: '1',
    aceptarVales: '1',
    gananciaSugerida: '25',
    costoPromedio: '0',
    ivaPorOmision: '0',
    corteMostrarEsperado: '1',
    fondoSugerido: '50000',
    basculaPrefijo: '20',
    basculaModo: 'peso',
    zoom: '1.15',
    folioMinimo: '0',
    simboloMoneda: '\$',
    cajonAbrir: '0',
    cajonImpresora: '',
  };
}

class AjustesRepo {
  AjustesRepo(this.db);
  final Database db;

  final _cache = <String, String>{};

  Future<void> cargar() async {
    _cache
      ..clear()
      ..addAll(Ajuste.omision);
    for (final f in await db.query('ajustes')) {
      _cache[f['clave'] as String] = f['valor'] as String;
    }
  }

  String texto(String clave) => _cache[clave] ?? Ajuste.omision[clave] ?? '';
  bool si(String clave) => texto(clave) == '1';
  int entero(String clave) => int.tryParse(texto(clave)) ?? 0;
  double numero(String clave) => double.tryParse(texto(clave)) ?? 0;

  Future<void> guardar(String clave, String valor) async {
    _cache[clave] = valor;
    await db.insert('ajustes', {'clave': clave, 'valor': valor},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> guardarSi(String clave, bool valor) => guardar(clave, valor ? '1' : '0');
}
