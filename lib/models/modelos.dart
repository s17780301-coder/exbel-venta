import 'dart:math';

import '../core/formato.dart';

class Departamento {
  Departamento({required this.id, required this.nombre});
  final String id;
  final String nombre;

  factory Departamento.desdeMapa(Map<String, Object?> m) =>
      Departamento(id: m['id'] as String, nombre: m['nombre'] as String);
}

/// 'unidad' (pieza), 'granel' (kilo, litro…) o 'kit' (paquete de productos).
class Producto {
  Producto({
    required this.id,
    this.codigo = '',
    required this.descripcion,
    this.tipo = 'unidad',
    this.departamentoId,
    this.departamentoNombre,
    this.costoCentavos = 0,
    this.precioCentavos = 0,
    this.mayoreoCentavos = 0,
    this.mayoreoDesde = 0,
    this.usaInventario = true,
    this.existencia = 0,
    this.minimo = 0,
    this.maximo = 0,
    this.iva = 16,
    this.ieps = 0,
    this.favorito = false,
    this.kitDescuentaComponentes = true,
    this.activo = true,
  });

  final String id;
  final String codigo;
  final String descripcion;
  final String tipo;
  final String? departamentoId;
  final String? departamentoNombre;
  final int costoCentavos;

  /// Precio de venta con impuestos incluidos.
  final int precioCentavos;

  /// 0 = sin precio de mayoreo.
  final int mayoreoCentavos;

  /// Cantidad a partir de la cual se aplica el mayoreo solo (0 = solo con F11).
  final double mayoreoDesde;
  final bool usaInventario;
  final double existencia;
  final double minimo;
  final double maximo;
  final double iva;
  final double ieps;
  final bool favorito;
  final bool kitDescuentaComponentes;
  final bool activo;

  bool get esGranel => tipo == 'granel';
  bool get esKit => tipo == 'kit';
  bool get tieneMayoreo => mayoreoCentavos > 0;
  bool get bajoMinimo => usaInventario && minimo > 0 && existencia <= minimo;

  /// Ganancia sobre el precio de venta (0–1).
  double get margen =>
      precioCentavos <= 0 || costoCentavos <= 0 ? 0 : (precioCentavos - costoCentavos) / precioCentavos;

  factory Producto.desdeMapa(Map<String, Object?> m) => Producto(
        id: m['id'] as String,
        codigo: m['codigo'] as String,
        descripcion: m['descripcion'] as String,
        tipo: m['tipo'] as String,
        departamentoId: m['departamento_id'] as String?,
        departamentoNombre: m['departamento_nombre'] as String?,
        costoCentavos: m['costo_centavos'] as int,
        precioCentavos: m['precio_centavos'] as int,
        mayoreoCentavos: m['mayoreo_centavos'] as int,
        mayoreoDesde: (m['mayoreo_desde'] as num).toDouble(),
        usaInventario: m['usa_inventario'] == 1,
        existencia: (m['existencia'] as num).toDouble(),
        minimo: (m['minimo'] as num).toDouble(),
        maximo: (m['maximo'] as num).toDouble(),
        iva: (m['iva'] as num).toDouble(),
        ieps: (m['ieps'] as num).toDouble(),
        favorito: m['favorito'] == 1,
        kitDescuentaComponentes: m['kit_descuenta_componentes'] == 1,
        activo: m['activo'] == 1,
      );

  /// Sin `existencia`: solo cambia con movimientos de inventario.
  Map<String, Object?> aMapa() => {
        'id': id,
        'codigo': codigo,
        'descripcion': descripcion,
        'tipo': tipo,
        'departamento_id': departamentoId,
        'costo_centavos': costoCentavos,
        'precio_centavos': precioCentavos,
        'mayoreo_centavos': mayoreoCentavos,
        'mayoreo_desde': mayoreoDesde,
        'usa_inventario': usaInventario ? 1 : 0,
        'minimo': minimo,
        'maximo': maximo,
        'iva': iva,
        'ieps': ieps,
        'favorito': favorito ? 1 : 0,
        'kit_descuenta_componentes': kitDescuentaComponentes ? 1 : 0,
        'activo': activo ? 1 : 0,
      };

  Producto copiarCon({String? id, double? existencia}) => Producto(
        id: id ?? this.id,
        codigo: codigo,
        descripcion: descripcion,
        tipo: tipo,
        departamentoId: departamentoId,
        departamentoNombre: departamentoNombre,
        costoCentavos: costoCentavos,
        precioCentavos: precioCentavos,
        mayoreoCentavos: mayoreoCentavos,
        mayoreoDesde: mayoreoDesde,
        usaInventario: usaInventario,
        existencia: existencia ?? this.existencia,
        minimo: minimo,
        maximo: maximo,
        iva: iva,
        ieps: ieps,
        favorito: favorito,
        kitDescuentaComponentes: kitDescuentaComponentes,
        activo: activo,
      );
}

class Componente {
  Componente({required this.productoId, required this.descripcion, required this.cantidad, this.precioCentavos = 0});
  final String productoId;
  final String descripcion;
  final double cantidad;
  final int precioCentavos;
}

/// "N por $X": 3 por $20.
class Promocion {
  Promocion({required this.id, required this.productoId, required this.nombre,
      required this.cantidad, required this.precioCentavos, this.activa = true});
  final String id;
  final String productoId;
  final String nombre;
  final double cantidad;
  final int precioCentavos;
  final bool activa;

  factory Promocion.desdeMapa(Map<String, Object?> m) => Promocion(
        id: m['id'] as String,
        productoId: m['producto_id'] as String,
        nombre: m['nombre'] as String,
        cantidad: (m['cantidad'] as num).toDouble(),
        precioCentavos: m['precio_centavos'] as int,
        activa: m['activa'] == 1,
      );
}

/// Permisos que se le pueden dar a un cajero. El administrador tiene todos.
abstract final class Permiso {
  static const descuentos = 'descuentos';
  static const cancelar = 'cancelar';
  static const devoluciones = 'devoluciones';
  static const entradasSalidas = 'entradas_salidas';
  static const clientes = 'clientes';
  static const abonos = 'abonos';
  static const productos = 'productos';
  static const inventario = 'inventario';
  static const reportes = 'reportes';
  static const corteDia = 'corte_dia';
  static const configuracion = 'configuracion';

  static const todos = <String, String>{
    descuentos: 'Dar descuentos y cambiar precios en la venta',
    cancelar: 'Cancelar ventas',
    devoluciones: 'Hacer devoluciones',
    entradasSalidas: 'Registrar entradas y salidas de efectivo',
    clientes: 'Dar de alta y modificar clientes',
    abonos: 'Recibir abonos y liquidar créditos',
    productos: 'Crear y modificar productos',
    inventario: 'Agregar y ajustar inventario',
    reportes: 'Ver reportes y ganancias',
    corteDia: 'Ver el corte del día y de otros cajeros',
    configuracion: 'Cambiar la configuración',
  };
}

class Cajero {
  Cajero({required this.id, required this.usuario, required this.nombre,
      this.administrador = false, Set<String>? permisos, this.activo = true})
      : permisos = permisos ?? {};
  final String id;
  final String usuario;
  final String nombre;
  final bool administrador;
  final Set<String> permisos;
  final bool activo;

  bool puede(String permiso) => administrador || permisos.contains(permiso);

  factory Cajero.desdeMapa(Map<String, Object?> m) => Cajero(
        id: m['id'] as String,
        usuario: m['usuario'] as String,
        nombre: m['nombre'] as String,
        administrador: m['administrador'] == 1,
        permisos: (m['permisos'] as String).split(',').where((x) => x.isNotEmpty).toSet(),
        activo: m['activo'] == 1,
      );
}

class Turno {
  Turno({required this.id, required this.numero, required this.cajeroId, required this.abierto,
      required this.fondoCentavos, required this.estado, this.cajeroNombre, this.cerrado,
      this.contadoCentavos, this.esperadoCentavos});
  final String id;
  final int numero;
  final String cajeroId;
  final String? cajeroNombre;
  final DateTime abierto;
  final DateTime? cerrado;
  final int fondoCentavos;
  final int? contadoCentavos;
  final int? esperadoCentavos;
  final String estado;

  bool get estaAbierto => estado == 'abierto';

  factory Turno.desdeMapa(Map<String, Object?> m) => Turno(
        id: m['id'] as String,
        numero: m['numero'] as int,
        cajeroId: m['cajero_id'] as String,
        cajeroNombre: m['cajero_nombre'] as String?,
        abierto: DateTime.parse(m['abierto'] as String),
        cerrado: m['cerrado'] == null ? null : DateTime.parse(m['cerrado'] as String),
        fondoCentavos: m['fondo_centavos'] as int,
        contadoCentavos: m['contado_centavos'] as int?,
        esperadoCentavos: m['esperado_centavos'] as int?,
        estado: m['estado'] as String,
      );
}

class Cliente {
  Cliente({required this.id, this.numero = 0, required this.nombre, this.direccion = '',
      this.telefono = '', this.limiteCentavos = 0, this.saldoCentavos = 0});
  final String id;
  final int numero;
  final String nombre;
  final String direccion;
  final String telefono;

  /// 0 = sin límite.
  final int limiteCentavos;
  final int saldoCentavos;

  bool get tieneLimite => limiteCentavos > 0;
  int get disponibleCentavos => tieneLimite ? max(0, limiteCentavos - saldoCentavos) : 0;

  factory Cliente.desdeMapa(Map<String, Object?> m) => Cliente(
        id: m['id'] as String,
        numero: m['numero'] as int,
        nombre: m['nombre'] as String,
        direccion: m['direccion'] as String,
        telefono: m['telefono'] as String,
        limiteCentavos: m['limite_centavos'] as int,
        saldoCentavos: m['saldo_centavos'] as int,
      );

  /// Sin saldo: solo cambia con ventas a crédito, abonos y devoluciones.
  Map<String, Object?> aMapa() => {
        'id': id,
        'numero': numero,
        'nombre': nombre,
        'direccion': direccion,
        'telefono': telefono,
        'limite_centavos': limiteCentavos,
      };
}

/// Un artículo en la venta en curso.
class Renglon {
  Renglon({
    required this.descripcion,
    required this.cantidad,
    required this.precioNormalCentavos,
    this.producto,
    this.codigo = '',
    this.mayoreoCentavos = 0,
    this.mayoreoDesde = 0,
    this.costoCentavos = 0,
    this.iva = 0,
    this.ieps = 0,
    this.departamentoId,
    this.existencia,
    this.promocion,
  });

  /// null = artículo común (no está en el catálogo).
  final Producto? producto;
  final String codigo;
  final String descripcion;
  double cantidad;
  final int precioNormalCentavos;
  final int mayoreoCentavos;
  final double mayoreoDesde;
  final int costoCentavos;
  final double iva;
  final double ieps;
  final String? departamentoId;
  final double? existencia;
  final Promocion? promocion;

  /// F11: forzar precio de mayoreo.
  bool mayoreoManual = false;

  /// Precio fijado a mano (descuento o cambio de precio).
  int? precioManualCentavos;

  factory Renglon.deProducto(Producto p, {double cantidad = 1, Promocion? promocion}) => Renglon(
        producto: p,
        codigo: p.codigo,
        descripcion: p.descripcion,
        cantidad: cantidad,
        precioNormalCentavos: p.precioCentavos,
        mayoreoCentavos: p.mayoreoCentavos,
        mayoreoDesde: p.mayoreoDesde,
        costoCentavos: p.costoCentavos,
        iva: p.iva,
        ieps: p.ieps,
        departamentoId: p.departamentoId,
        existencia: p.usaInventario ? p.existencia : null,
        promocion: promocion,
      );

  bool get esComun => producto == null;

  bool get conMayoreo =>
      precioManualCentavos == null &&
      mayoreoCentavos > 0 &&
      (mayoreoManual || (mayoreoDesde > 0 && cantidad >= mayoreoDesde));

  bool get conPromocion =>
      precioManualCentavos == null && !conMayoreo && promocion != null &&
      promocion!.cantidad > 0 && cantidad >= promocion!.cantidad;

  int get importeCentavos {
    if (precioManualCentavos != null) return calcularImporte(cantidad, precioManualCentavos!);
    if (conMayoreo) return calcularImporte(cantidad, mayoreoCentavos);
    if (conPromocion) {
      final p = promocion!;
      final grupos = (cantidad / p.cantidad).floor();
      final resto = cantidad - grupos * p.cantidad;
      return grupos * p.precioCentavos + calcularImporte(resto, precioNormalCentavos);
    }
    return calcularImporte(cantidad, precioNormalCentavos);
  }

  /// Precio por unidad que se cobra (para el ticket).
  int get precioUnitarioCentavos =>
      cantidad == 0 ? precioNormalCentavos : (importeCentavos / cantidad).round();

  int get descuentoCentavos => calcularImporte(cantidad, precioNormalCentavos) - importeCentavos;

  bool get faltaExistencia => existencia != null && cantidad > existencia!;
}

/// Cómo se pagó una venta. Los montos suman el total (el efectivo ya sin
/// el cambio).
class Pago {
  Pago({this.efectivoCentavos = 0, this.tarjetaCentavos = 0, this.transferenciaCentavos = 0, this.valesCentavos = 0,
      this.dolaresCentavos = 0, this.creditoCentavos = 0, this.recibidoCentavos = 0,
      this.referencia = ''});
  final int efectivoCentavos;
  final int tarjetaCentavos;
  final int transferenciaCentavos;
  final int valesCentavos;

  /// En pesos (ya convertidos con el tipo de cambio).
  final int dolaresCentavos;
  final int creditoCentavos;

  /// Lo que entregó el cliente en efectivo (para el cambio).
  final int recibidoCentavos;
  final String referencia;

  int get totalCentavos =>
      efectivoCentavos + tarjetaCentavos + transferenciaCentavos + valesCentavos + dolaresCentavos + creditoCentavos;

  String get descripcion {
    final partes = <String>[
      if (efectivoCentavos > 0) 'Efectivo',
      if (tarjetaCentavos > 0) 'Tarjeta',
      if (transferenciaCentavos > 0) 'Transferencia',
      if (valesCentavos > 0) 'Vales',
      if (dolaresCentavos > 0) 'Dólares',
      if (creditoCentavos > 0) 'Crédito',
    ];
    return partes.length > 1 ? 'Mixto (${partes.join(', ')})' : (partes.isEmpty ? '—' : partes.first);
  }
}

class Venta {
  Venta({required this.id, required this.folio, required this.fecha, required this.totalCentavos,
      required this.estado, required this.pago, required this.cajeroId, required this.turnoId,
      this.cajeroNombre, this.clienteId, this.clienteNombre, this.notas = '', this.articulos = 0});
  final String id;
  final int folio;
  final DateTime fecha;
  final int totalCentavos;
  final String estado;
  final Pago pago;
  final String cajeroId;
  final String? cajeroNombre;
  final String turnoId;
  final String? clienteId;
  final String? clienteNombre;
  final String notas;
  final double articulos;

  bool get cancelada => estado == 'cancelada';
  bool get aCredito => pago.creditoCentavos > 0;

  factory Venta.desdeMapa(Map<String, Object?> m) => Venta(
        id: m['id'] as String,
        folio: m['folio'] as int,
        fecha: DateTime.parse(m['fecha'] as String),
        totalCentavos: m['total_centavos'] as int,
        estado: m['estado'] as String,
        cajeroId: m['cajero_id'] as String,
        cajeroNombre: m['cajero_nombre'] as String?,
        turnoId: m['turno_id'] as String,
        clienteId: m['cliente_id'] as String?,
        clienteNombre: m['cliente_nombre'] as String?,
        notas: (m['notas'] as String?) ?? '',
        articulos: ((m['articulos'] as num?) ?? 0).toDouble(),
        pago: Pago(
          efectivoCentavos: m['efectivo_centavos'] as int,
          tarjetaCentavos: m['tarjeta_centavos'] as int,
          transferenciaCentavos: (m['transferencia_centavos'] as int?) ?? 0,
          valesCentavos: m['vales_centavos'] as int,
          dolaresCentavos: m['dolares_centavos'] as int,
          creditoCentavos: m['credito_centavos'] as int,
          recibidoCentavos: m['recibido_centavos'] as int,
          referencia: (m['referencia'] as String?) ?? '',
        ),
      );
}

class LineaVendida {
  LineaVendida({required this.id, required this.descripcion, required this.cantidad,
      required this.precioCentavos, required this.importeCentavos, required this.devuelto,
      this.productoId, this.codigo = ''});
  final String id;
  final String? productoId;
  final String codigo;
  final String descripcion;
  final double cantidad;
  final int precioCentavos;
  final int importeCentavos;
  final double devuelto;

  double get devolvible => cantidad - devuelto;

  factory LineaVendida.desdeMapa(Map<String, Object?> m) => LineaVendida(
        id: m['id'] as String,
        productoId: m['producto_id'] as String?,
        codigo: m['codigo'] as String,
        descripcion: m['descripcion'] as String,
        cantidad: (m['cantidad'] as num).toDouble(),
        precioCentavos: m['precio_centavos'] as int,
        importeCentavos: m['importe_centavos'] as int,
        devuelto: (m['devuelto'] as num).toDouble(),
      );
}

class MovimientoCaja {
  MovimientoCaja({required this.id, required this.fecha, required this.tipo,
      required this.montoCentavos, required this.concepto, this.cancelado = false});
  final String id;
  final DateTime fecha;
  final String tipo;
  final int montoCentavos;
  final String concepto;
  final bool cancelado;

  factory MovimientoCaja.desdeMapa(Map<String, Object?> m) => MovimientoCaja(
        id: m['id'] as String,
        fecha: DateTime.parse(m['fecha'] as String),
        tipo: m['tipo'] as String,
        montoCentavos: m['monto_centavos'] as int,
        concepto: m['concepto'] as String,
        cancelado: m['cancelado'] == 1,
      );
}

/// Corte de un turno o de un día.
class Corte {
  Corte({
    required this.titulo,
    required this.fondoCentavos,
    required this.ventasCentavos,
    required this.gananciaCentavos,
    required this.numeroVentas,
    required this.efectivoCentavos,
    required this.tarjetaCentavos,
    this.transferenciaCentavos = 0,
    required this.valesCentavos,
    required this.dolaresCentavos,
    required this.creditoCentavos,
    required this.abonosEfectivoCentavos,
    required this.abonosOtrosCentavos,
    required this.entradasCentavos,
    required this.salidasCentavos,
    required this.devolucionesCentavos,
    required this.devolucionesEfectivoCentavos,
    required this.ivaCentavos,
    required this.iepsCentavos,
    required this.porDepartamento,
    this.turno,
  });

  final String titulo;
  final Turno? turno;
  final int fondoCentavos;
  final int ventasCentavos;
  final int gananciaCentavos;
  final int numeroVentas;
  final int efectivoCentavos;
  final int tarjetaCentavos;
  final int transferenciaCentavos;
  final int valesCentavos;
  final int dolaresCentavos;
  final int creditoCentavos;
  final int abonosEfectivoCentavos;
  final int abonosOtrosCentavos;
  final int entradasCentavos;
  final int salidasCentavos;
  final int devolucionesCentavos;
  final int devolucionesEfectivoCentavos;
  final int ivaCentavos;
  final int iepsCentavos;

  /// (departamento, ventas, ganancia)
  final List<(String, int, int)> porDepartamento;

  /// Fondo + ventas en efectivo + abonos en efectivo + entradas − salidas −
  /// devoluciones en efectivo.
  int get esperadoCentavos =>
      fondoCentavos + efectivoCentavos + abonosEfectivoCentavos + entradasCentavos -
      salidasCentavos - devolucionesEfectivoCentavos;
}

/// Desglose de impuestos de un importe con impuestos incluidos.
(int, int) desgloseImpuestos(int importeCentavos, double iva, double ieps) {
  final sinIva = importeCentavos / (1 + iva / 100);
  final base = sinIva / (1 + ieps / 100);
  return ((importeCentavos - sinIva).round(), (sinIva - base).round());
}
