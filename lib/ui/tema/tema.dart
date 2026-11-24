import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colores de la marca exBel en tonos claros y suaves para estar muchas
/// horas frente a la pantalla: fondos blanco hueso (no blanco puro), texto
/// gris índigo muy oscuro (no negro puro), bloques grandes en lavanda claro
/// en lugar de oscuros, y el color fuerte solo en detalles.
abstract final class ExColor {
  /// Índigo casi negro: texto principal y paneles oscuros.
  static const tinta = Color(0xFF2B2845);
  static const tinta2 = Color(0xFF34315A);

  /// Índigo del logotipo.
  static const indigo = Color(0xFF4A4789);

  /// Lavanda del "ex" del logotipo.
  static const lavanda = Color(0xFFC7C4E0);

  /// Coral: botones principales y lo que está activo (texto en [tinta]).
  static const acento = Color(0xFFE09A8D);

  /// Barra superior y bandas de título (lavanda muy claro).
  static const barra = Color(0xFFECEAF5);
  static const banda = Color(0xFFDDDAF0);

  /// Texto sobre [barra] y [banda].
  static const bandaTexto = Color(0xFF34306A);

  /// Encabezado de tablas.
  static const encabezado = Color(0xFFE2DFF2);

  /// Botón principal (relleno suave).
  static const boton = Color(0xFFD3CFEC);

  static const concreto = Color(0xFFF4F3F8);
  static const blanco = Color(0xFFFBFBFC);
  static const linea = Color(0xFFBDB8D6);

  /// Contorno de botones, pestañas y recuadros (bien visible).
  static const borde = Color(0xFF7F79AE);
  static const lineaSuave = Color(0xFFDDDAEB);
  static const texto2 = Color(0xFF5A5675);
  static const textoClaro = Color(0xFFD2D0E2);
  static const textoClaro2 = Color(0xFF9C99B8);
  static const naranja = Color(0xFFD6A16A);
  static const rojo = Color(0xFFAE4A40);
  static const verde = Color(0xFF3D7A55);
  static const verdeSuave = Color(0xFFE7EFEA);
  static const amarillo = Color(0xFFD4B455);
  static const gris = Color(0xFFBDB9D4);
}

/// Tipografías: Space Grotesk (títulos y cifras), Inter (texto),
/// JetBrains Mono (claves y teclas).
abstract final class ExTexto {
  static TextStyle titulo(double tamano,
          {Color? color, FontWeight peso = FontWeight.w700}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: tamano,
        fontWeight: peso,
        color: color,
        letterSpacing: tamano >= 24 ? -0.5 : 0,
      );

  static TextStyle mono(double tamano,
          {Color? color, FontWeight peso = FontWeight.w700}) =>
      GoogleFonts.jetBrainsMono(fontSize: tamano, fontWeight: peso, color: color);

  /// Letra del logotipo exBel.
  static TextStyle marca(double tamano,
          {Color? color, FontWeight peso = FontWeight.w700}) =>
      GoogleFonts.poppins(fontSize: tamano, fontWeight: peso, color: color, height: 1);

  static TextStyle texto(double tamano,
          {Color? color, FontWeight peso = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: tamano, fontWeight: peso, color: color);
}

/// Tema de la app: todo cuadrado, salvo botones y avisos.
ThemeData temaExBel() {
  const cero = RoundedRectangleBorder(borderRadius: BorderRadius.zero);
  final boton = RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
  const bordeCampo = OutlineInputBorder(
    borderRadius: BorderRadius.zero,
    borderSide: BorderSide(color: ExColor.linea),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: ExColor.indigo).copyWith(
      primary: ExColor.tinta,
      onPrimary: ExColor.concreto,
      secondary: ExColor.acento,
      onSecondary: ExColor.tinta,
      surface: ExColor.blanco,
      onSurface: ExColor.tinta,
      error: ExColor.rojo,
      outline: ExColor.texto2,
      outlineVariant: ExColor.linea,
      primaryContainer: ExColor.acento,
      onPrimaryContainer: ExColor.tinta,
    ),
    scaffoldBackgroundColor: ExColor.concreto,
  );

  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: ExColor.tinta, displayColor: ExColor.tinta),
    appBarTheme: AppBarTheme(
      backgroundColor: ExColor.concreto,
      foregroundColor: ExColor.tinta,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: ExTexto.titulo(22, color: ExColor.tinta),
    ),
    cardTheme: const CardTheme(
      shape: cero,
      elevation: 0,
      color: ExColor.blanco,
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogTheme(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: ExColor.blanco,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      backgroundColor: ExColor.blanco,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: bordeCampo,
      enabledBorder: bordeCampo,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: ExColor.tinta, width: 2),
      ),
      filled: true,
      fillColor: ExColor.blanco,
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ExColor.boton,
        foregroundColor: ExColor.bandaTexto,
        side: const BorderSide(color: ExColor.borde, width: 1.4),
        shape: boton,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ExColor.tinta,
        side: const BorderSide(color: ExColor.borde, width: 1.4),
        shape: boton,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: ExColor.tinta, shape: boton),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ExColor.tinta,
      contentTextStyle: const TextStyle(color: ExColor.concreto),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dividerTheme: const DividerThemeData(
      color: ExColor.lineaSuave,
      space: 1,
      thickness: 1,
    ),
    listTileTheme: const ListTileThemeData(shape: cero),
    popupMenuTheme: const PopupMenuThemeData(shape: cero, color: ExColor.blanco),
    datePickerTheme: DatePickerThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
    progressIndicatorTheme:
        const ProgressIndicatorThemeData(color: ExColor.tinta),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(color: ExColor.tinta),
    ),
  );
}
