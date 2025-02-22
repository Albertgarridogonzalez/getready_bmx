import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNav({required this.currentIndex, required this.onTap});

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
                onTap: () => onTap(1),
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
                onTap: () => onTap(2),
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
                onTap: () => onTap(3),
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
                onTap: () => onTap(4),
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
