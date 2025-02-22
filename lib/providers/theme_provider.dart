import 'package:flutter/material.dart';

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
    // Aquí se podría agregar lógica para guardar la configuración de forma centralizada
  }

  // Cambia la paleta de colores
  void setPalette(ColorPalette newPalette, {bool save = true}) {
    _palette = newPalette;
    notifyListeners();
  }

  // Devuelve un color representativo para cada paleta (para mostrar la opción)
  Color getSampleColorForPalette(ColorPalette palette) {
    switch (palette) {
      case ColorPalette.red:
        return const Color.fromARGB(185, 244, 67, 54);
      case ColorPalette.green:
        return const Color.fromARGB(179, 76, 175, 79);
      case ColorPalette.purple:
        return const Color.fromARGB(179, 155, 39, 176);
      case ColorPalette.orange:
        return const Color.fromARGB(167, 255, 153, 0);
      case ColorPalette.blue:
      default:
        return const Color.fromARGB(167, 33, 149, 243);
    }
  }

  // Devuelve el color primario actual
  Color get primaryColor => getSampleColorForPalette(_palette);

  // Genera el ThemeData según el modo y la paleta
  ThemeData get themeData {
    return ThemeData(
      brightness: _isDarkMode ? Brightness.dark : Brightness.light,
      primaryColor: primaryColor,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
      ),
      // Puedes personalizar otros aspectos del tema aquí
    );
  }
}
