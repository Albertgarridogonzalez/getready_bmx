import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ColorPalette { blue, red, green, purple, orange }

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = true; // por defecto modo oscuro
  ColorPalette _palette = ColorPalette.blue; // por defecto paleta azul

  bool get isDarkMode => _isDarkMode;
  ColorPalette get palette => _palette;

  // Cambia el modo (oscuro o claro)
  void setDarkMode(bool isDark, {bool save = true}) {
    _isDarkMode = isDark;
    notifyListeners();
  }

  // Cambia la paleta de colores
  void setPalette(ColorPalette newPalette, {bool save = true}) {
    _palette = newPalette;
    notifyListeners();
  }

  // Devuelve un color representativo para cada paleta
  Color getSampleColorForPalette(ColorPalette palette) {
    switch (palette) {
      case ColorPalette.red:
        return const Color(0xFFFF4B4B);
      case ColorPalette.green:
        return const Color(0xFF00E676);
      case ColorPalette.purple:
        return const Color(0xFFD500F9);
      case ColorPalette.orange:
        return const Color(0xFFFF9100);
      case ColorPalette.blue:
        return const Color(0xFF2979FF);
    }
  }

  Color get primaryColor => getSampleColorForPalette(_palette);

  // Genera el ThemeData según el modo y la paleta usando Material 3
  ThemeData get themeData {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: _isDarkMode ? Brightness.dark : Brightness.light,
      primary: primaryColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: _isDarkMode ? Brightness.dark : Brightness.light,

      // Tipografía moderna
      textTheme: GoogleFonts.interTextTheme(
        _isDarkMode ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),

      // Estilos específicos para títulos deportivos
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.orbitron(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: _isDarkMode ? Colors.white : Colors.black,
        ),
      ),

      cardTheme: CardThemeData(
        elevation: 8,
        shadowColor: primaryColor.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.orbitron(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
