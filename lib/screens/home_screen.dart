import 'package:flutter/material.dart';
import 'package:getready_bmx/widgets/bottom_nav.dart';
import 'package:getready_bmx/screens/live_screen.dart';
import 'package:getready_bmx/screens/records_screen.dart';
import 'package:getready_bmx/screens/leaderboard_screen.dart';
import 'package:getready_bmx/screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final List<String> _pageTitles = [
    'Inicio',
    'Live',
    'Historial',
    'Leaderboard',
    'Ajustes'
  ];
  final List<Widget> _pages = [
    Center(child: Text('Pantalla de Inicio')), // Página de inicio
    LiveScreen(),
    RecordsScreen(),
    LeaderboardScreen(),
    SettingsScreen(),
  ];

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('GetReady BMX'),
            Text(_pageTitles[_selectedIndex]),
          ],
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        child: Icon(Icons.home, color: Colors.white),
        onPressed: () => _onItemTapped(0),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomNav(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
