import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:getready_bmx/widgets/bottom_nav.dart';
import 'package:getready_bmx/screens/live_screen.dart';
import 'package:getready_bmx/screens/records_screen.dart';
import 'package:getready_bmx/screens/leaderboard_screen.dart';
import 'package:getready_bmx/screens/settings_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<String> _pageTitles = [
    'GateReady BMX',
    'Live',
    'Historial',
    'Leaderboard',
    'Ajustes'
  ];

  final List<Widget> _pages = [
    _NewsFeedWidget(),
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = themeProvider.primaryColor;

    return Scaffold(
      extendBody: true, // Allows content to be visible behind the floating nav
      appBar: AppBar(
        title: Text(
          _pageTitles[_selectedIndex],
          style: GoogleFonts.orbitron(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      floatingActionButton: Container(
        height: 64,
        width: 64,
        child: FloatingActionButton(
          elevation: 4,
          shape: const CircleBorder(),
          backgroundColor: primary,
          child: const Icon(Icons.home_rounded, color: Colors.white, size: 32),
          onPressed: () => _onItemTapped(0),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomNav(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class _NewsFeedWidget extends StatelessWidget {
  const _NewsFeedWidget({Key? key}) : super(key: key);

  String _convertDriveLink(String rawUrl) {
    if (!rawUrl.contains("drive.google.com/file/d/")) return rawUrl;
    final parts = rawUrl.split('/');
    if (parts.length < 6) return rawUrl;
    String fileId = parts[5].split('?')[0];
    return "https://drive.google.com/uc?export=view&id=$fileId";
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = themeProvider.primaryColor;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('news')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No hay publicaciones disponibles.'));
        }

        final newsDocs = snapshot.data!.docs;
        return ListView.builder(
          padding: const EdgeInsets.only(
              bottom: 120), // Extra padding for the floating nav
          itemCount: newsDocs.length,
          itemBuilder: (context, index) {
            final data = newsDocs[index].data() as Map<String, dynamic>;
            final finalUrl = _convertDriveLink(data['imageUrl'] ?? '');

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Card(
                clipBehavior: Clip.antiAlias,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (finalUrl.isNotEmpty)
                      Stack(
                        children: [
                          Image.network(
                            finalUrl,
                            fit: BoxFit.cover,
                            height: 280,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => Container(
                              height: 200,
                              color: Colors.grey.withOpacity(0.2),
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 80,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    (themeProvider.isDarkMode
                                            ? Colors.black
                                            : Colors.white)
                                        .withOpacity(0.8),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['title'] ?? 'Sin título',
                            style: GoogleFonts.orbitron(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            data['content'] ?? 'Sin contenido',
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
