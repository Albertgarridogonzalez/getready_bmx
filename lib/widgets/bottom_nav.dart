import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNav({required this.currentIndex, required this.onTap});

  // Función para manejar el tap con comprobación de autenticación.
  void handleTap(BuildContext context, int index) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated) {
      // Redirige a la pantalla de login si no hay usuario autenticado.
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      return;
    }
    onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final iconColor = themeProvider.isDarkMode ? Colors.white : Colors.black;
    return BottomAppBar(
      shape: CircularNotchedRectangle(),
      notchMargin: 8.0,
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10.0),
                onTap: () => handleTap(context, 1),
                child: Container(
                  height: 56.0,
                  alignment: Alignment.center,
                  child: Icon(Icons.live_tv, color: iconColor),
                ),
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10.0),
                onTap: () => handleTap(context, 2),
                child: Container(
                  height: 56.0,
                  alignment: Alignment.center,
                  child: Icon(Icons.history, color: iconColor),
                ),
              ),
            ),
          ),
          SizedBox(width: 40), // Espacio para centrar el botón de Home
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10.0),
                onTap: () => handleTap(context, 3),
                child: Container(
                  height: 56.0,
                  alignment: Alignment.center,
                  child: Icon(Icons.leaderboard, color: iconColor),
                ),
              ),
            ),
          ),
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10.0),
                onTap: () => handleTap(context, 4),
                child: Container(
                  height: 56.0,
                  alignment: Alignment.center,
                  child: Icon(Icons.settings, color: iconColor),
                ),
              ),
            ),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
    );
  }
}
