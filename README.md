# exBel™ venta

Punto de venta para tiendas de abarrotes, misceláneas y comercios. Windows, pantalla completa, funciona sin internet.

## Descargar

En **Releases → ultima**:

- `exBel-venta-instalador.exe`: instalador. Crea accesos directos en el escritorio y en el menú Inicio.
- `exBel-venta-portable.zip`: versión sin instalar.

## Funciones

- **Ventas (F1):**
  - Lector de código de barras, `3*código` para varias piezas, granel por peso o por importe y etiquetas de báscula.
  - Artículo común (Ctrl+P), Varios (INS), mayoreo (F11, o automático desde N piezas) y promociones "N por $X".
  - Descuentos (Ctrl+D), tickets pendientes (F6/F5), verificador de precios (F9), buscador (F10) y botones de favoritos.
  - Cobro (F12) en efectivo con cambio, tarjeta, vales, dólares con tipo de cambio, crédito o pago mixto.
  - Ticket con vista previa e impresión directa.
  - Entradas y salidas de efectivo (F7/F8).
  - Ventas del día, reimpresión, devoluciones parciales y cancelaciones.
- **Clientes (F2):** crédito con límite, estado de cuenta, abonos, liquidar, antigüedad del adeudo y saldo total por cobrar.
- **Productos (F3):**
  - Departamentos y productos por unidad, granel o paquete (kit que descuenta sus componentes).
  - Costo, ganancia, precio y mayoreo; IVA e IEPS; mínimos y máximos.
  - Promociones, cambio masivo de precios e importar/exportar CSV (Excel).
- **Inventario (F4):** entradas con costo último o promedio, ajustes por conteo, mermas, productos bajos, pedido sugerido, valor del inventario y kardex.
- **Corte:**
  - Corte del turno y corte del día, con dinero esperado y conteo por billetes y monedas.
  - Faltante o sobrante, ventas por forma de pago, por departamento e impuestos.
  - Historial de turnos.
- **Reportes:** por día, producto, departamento, cajero, cliente, hora y forma de pago, más productos sin venta. Todos se exportan a Excel.
- **Configuración:**
  - Tienda y ticket (logotipo, 58/80 mm, impresora).
  - Cajeros con contraseña y permisos (o autorización de supervisor), báscula y respaldos (automáticos y manuales).

## Desarrollo

Flutter 3.24. La carpeta `windows/` se genera en GitHub Actions (`.github/workflows/compilar.yml`). El dinero se guarda en centavos y las cantidades en decimales.
