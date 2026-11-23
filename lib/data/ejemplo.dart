import '../core/ids.dart';
import '../models/modelos.dart';
import 'repos.dart';

/// Departamentos típicos de una tienda de abarrotes.
const departamentosAbarrotes = <String>[
  'Abarrotes',
  'Bebidas',
  'Botanas y dulces',
  'Lácteos y huevo',
  'Salchichonería',
  'Panadería',
  'Frutas y verduras',
  'Granos y semillas',
  'Limpieza',
  'Higiene personal',
  'Bebés',
  'Mascotas',
  'Cigarros',
  'Cervezas y vinos',
  'Papelería',
  'Varios',
];

/// (código, descripción, departamento, tipo, costo, precio, mayoreo, desde, existencia, mínimo)
const _productos = <(String, String, String, String, int, int, int, double, double, double)>[
  ('1001', 'Refresco de cola 600 ml', 'Bebidas', 'unidad', 1250, 1800, 1650, 12, 48, 12),
  ('1002', 'Refresco de cola 2 L', 'Bebidas', 'unidad', 2900, 3800, 0, 0, 24, 6),
  ('1003', 'Agua natural 1 L', 'Bebidas', 'unidad', 700, 1200, 1000, 12, 36, 12),
  ('1004', 'Jugo de naranja 1 L', 'Bebidas', 'unidad', 2100, 2900, 0, 0, 12, 4),
  ('1010', 'Leche entera 1 L', 'Lácteos y huevo', 'unidad', 2350, 2900, 0, 0, 30, 10),
  ('1011', 'Huevo blanco (kg)', 'Lácteos y huevo', 'granel', 3600, 4800, 0, 0, 20, 5),
  ('1012', 'Queso fresco (kg)', 'Lácteos y huevo', 'granel', 9500, 13000, 0, 0, 5, 1),
  ('1013', 'Yogur bebible 250 g', 'Lácteos y huevo', 'unidad', 950, 1400, 0, 0, 20, 6),
  ('1014', 'Crema 200 ml', 'Lácteos y huevo', 'unidad', 1900, 2500, 0, 0, 12, 4),
  ('1020', 'Jamón de pavo (kg)', 'Salchichonería', 'granel', 9800, 14000, 0, 0, 4, 1),
  ('1021', 'Salchicha de pavo (kg)', 'Salchichonería', 'granel', 6200, 8900, 0, 0, 5, 1),
  ('1030', 'Frijol negro (kg)', 'Granos y semillas', 'granel', 2800, 3800, 3500, 5, 40, 10),
  ('1031', 'Arroz (kg)', 'Granos y semillas', 'granel', 2200, 3000, 2800, 5, 40, 10),
  ('1032', 'Azúcar estándar (kg)', 'Granos y semillas', 'granel', 2400, 3200, 3000, 5, 50, 10),
  ('1033', 'Lenteja (kg)', 'Granos y semillas', 'granel', 3100, 4200, 0, 0, 10, 3),
  ('1040', 'Aceite vegetal 1 L', 'Abarrotes', 'unidad', 3300, 4300, 4000, 6, 24, 6),
  ('1041', 'Atún en agua 140 g', 'Abarrotes', 'unidad', 1500, 2200, 2000, 6, 30, 10),
  ('1042', 'Sopa de pasta 200 g', 'Abarrotes', 'unidad', 650, 1000, 900, 10, 60, 15),
  ('1043', 'Chiles en lata 220 g', 'Abarrotes', 'unidad', 1300, 1900, 0, 0, 20, 5),
  ('1044', 'Café soluble 120 g', 'Abarrotes', 'unidad', 6100, 7900, 0, 0, 10, 3),
  ('1045', 'Harina de maíz 1 kg', 'Abarrotes', 'unidad', 1800, 2400, 0, 0, 30, 8),
  ('1046', 'Sal 1 kg', 'Abarrotes', 'unidad', 900, 1500, 0, 0, 15, 4),
  ('1047', 'Mayonesa 390 g', 'Abarrotes', 'unidad', 3400, 4400, 0, 0, 12, 3),
  ('1050', 'Pan de caja grande', 'Panadería', 'unidad', 4000, 5200, 0, 0, 10, 3),
  ('1051', 'Galletas surtidas 500 g', 'Botanas y dulces', 'unidad', 3300, 4500, 0, 0, 12, 3),
  ('1052', 'Papas fritas 45 g', 'Botanas y dulces', 'unidad', 1300, 1900, 0, 0, 40, 10),
  ('1053', 'Chocolate en barra', 'Botanas y dulces', 'unidad', 1000, 1500, 0, 0, 30, 10),
  ('1054', 'Chicle (pieza)', 'Botanas y dulces', 'unidad', 80, 200, 0, 0, 200, 50),
  ('1060', 'Jitomate (kg)', 'Frutas y verduras', 'granel', 1800, 2900, 0, 0, 15, 5),
  ('1061', 'Cebolla (kg)', 'Frutas y verduras', 'granel', 1600, 2600, 0, 0, 15, 5),
  ('1062', 'Plátano (kg)', 'Frutas y verduras', 'granel', 1400, 2200, 0, 0, 15, 5),
  ('1063', 'Limón (kg)', 'Frutas y verduras', 'granel', 2200, 3500, 0, 0, 10, 3),
  ('1070', 'Detergente en polvo 1 kg', 'Limpieza', 'unidad', 3200, 4200, 0, 0, 12, 3),
  ('1071', 'Cloro 1 L', 'Limpieza', 'unidad', 1300, 1900, 0, 0, 15, 4),
  ('1072', 'Jabón de barra lavandería', 'Limpieza', 'unidad', 1500, 2100, 0, 0, 15, 4),
  ('1073', 'Papel higiénico 4 rollos', 'Higiene personal', 'unidad', 2700, 3600, 0, 0, 20, 5),
  ('1074', 'Jabón de tocador', 'Higiene personal', 'unidad', 1300, 1900, 0, 0, 20, 5),
  ('1075', 'Pasta dental 100 ml', 'Higiene personal', 'unidad', 2400, 3300, 0, 0, 12, 3),
  ('1080', 'Pañal etapa 3 (paquete 40)', 'Bebés', 'unidad', 19000, 23500, 0, 0, 5, 2),
  ('1090', 'Croquetas para perro (kg)', 'Mascotas', 'granel', 3000, 4500, 0, 0, 20, 5),
  ('1100', 'Cerveza clara 355 ml', 'Cervezas y vinos', 'unidad', 1600, 2200, 2000, 12, 48, 12),
  ('1110', 'Cuaderno profesional', 'Papelería', 'unidad', 2600, 3800, 0, 0, 10, 3),
  ('1111', 'Bolígrafo', 'Papelería', 'unidad', 400, 800, 0, 0, 30, 10),
];

/// Carga departamentos y productos de muestra (para probar el sistema).
Future<void> cargarEjemplo({String? cajeroId}) async {
  final deps = <String, String>{};
  for (final d in await repos.productos.departamentos()) {
    deps[d.nombre] = d.id;
  }
  for (final n in departamentosAbarrotes) {
    deps[n] ??= (await repos.productos.guardarDepartamento(nombre: n)).id;
  }
  for (final x in _productos) {
    if (await repos.productos.porCodigo(x.$1) != null) continue;
    await repos.productos.guardar(
      Producto(
        id: nuevoId(),
        codigo: x.$1,
        descripcion: x.$2,
        departamentoId: deps[x.$3],
        tipo: x.$4,
        costoCentavos: x.$5,
        precioCentavos: x.$6,
        mayoreoCentavos: x.$7,
        mayoreoDesde: x.$8,
        minimo: x.$10,
        iva: 0,
        favorito: x.$1 == '1001' || x.$1 == '1010' || x.$1 == '1011' || x.$1 == '1031' || x.$1 == '1050',
      ),
      existenciaInicial: x.$9,
      cajeroId: cajeroId,
    );
  }
  // Un paquete de ejemplo.
  if (await repos.productos.porCodigo('2001') == null) {
    final refresco = await repos.productos.porCodigo('1001');
    final papas = await repos.productos.porCodigo('1052');
    if (refresco != null && papas != null) {
      final kit = await repos.productos.guardar(Producto(
        id: nuevoId(),
        codigo: '2001',
        descripcion: 'Combo refresco + papas',
        departamentoId: deps['Botanas y dulces'],
        tipo: 'kit',
        precioCentavos: 3300,
        costoCentavos: refresco.costoCentavos + papas.costoCentavos,
        usaInventario: false,
        iva: 0,
      ));
      await repos.productos.guardarComponentes(kit.id, [
        Componente(productoId: refresco.id, descripcion: refresco.descripcion, cantidad: 1),
        Componente(productoId: papas.id, descripcion: papas.descripcion, cantidad: 1),
      ]);
    }
  }
}
