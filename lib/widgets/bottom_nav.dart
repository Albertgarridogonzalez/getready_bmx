// widgets/bottom_nav.dart
import 'package:flutter/material.dart';

class BottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const BottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      shape: CircularNotchedRectangle(),
      notchMargin: 8.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(Icons.live_tv, color: Colors.black),
            onPressed: () => onTap(1),
          ),
          IconButton(
            icon: Icon(Icons.history, color: Colors.black),
            onPressed: () => onTap(2),
          ),
          SizedBox(width: 40), // Espacio para centrar el botón de Home
          IconButton(
            icon: Icon(Icons.leaderboard, color: Colors.black),
            onPressed: () => onTap(3),
          ),
          IconButton(
            icon: Icon(Icons.settings, color: Colors.black),
            onPressed: () => onTap(4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
    );
  }
}