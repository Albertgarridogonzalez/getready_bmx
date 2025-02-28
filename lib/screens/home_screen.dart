import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:getready_bmx/widgets/bottom_nav.dart';
import 'package:getready_bmx/screens/live_screen.dart';
import 'package:getready_bmx/screens/records_screen.dart';
import 'package:getready_bmx/screens/leaderboard_screen.dart';
import 'package:getready_bmx/screens/settings_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    // Obtenemos el provider para usar el color que el usuario eligió
    final themeProvider = Provider.of<ThemeProvider>(context);
    final baseColor = themeProvider.primaryColor;
    final darker = darkenColor(baseColor, 0.15);
    final lighter = lightenColor(baseColor, 0.15);
    return Scaffold(
      appBar: AppBar(
        // Texto a la izquierda
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Center(
            child: Text(
              "GateReady BMX",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        leadingWidth: 140, // Ajusta el espacio para tu texto a la izquierda

        centerTitle: true,
        elevation: 0,

        // Título (centrado) con el nombre de la sección actual
        title: Text(
          _pageTitles[_selectedIndex],
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        // Aplicamos gradiente en flexibleSpace
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                darker,   // Más oscuro
              lighter,  // Más claro
              ],
            ),
          ),
        ),
        //shape: RoundedRectangleBorder(
        //  borderRadius: BorderRadius.vertical(
        //    bottom: Radius.circular(25),
        //  ),
        //),
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

Color lightenColor(Color color, [double amount = .1]) {
  final hsl = HSLColor.fromColor(color);
  // Aumentamos la lightness (clamp mantiene el valor entre 0 y 1)
  final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
  return hslLight.toColor();
}

Color darkenColor(Color color, [double amount = .1]) {
  final hsl = HSLColor.fromColor(color);
  final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
  return hslDark.toColor();
}

// ----------------------------------------------------------------------
// Widget que construye la lista de publicaciones (noticias) desde Firestore
// ----------------------------------------------------------------------
class _NewsFeedWidget extends StatelessWidget {
  const _NewsFeedWidget({Key? key}) : super(key: key);

  String _convertDriveLink(String rawUrl) {
    if (!rawUrl.contains("drive.google.com/file/d/")) {
      return rawUrl;
    }
    final parts = rawUrl.split('/');
    if (parts.length < 6) {
      return rawUrl;
    }
    String fileId = parts[5];
    if (fileId.contains('?')) {
      fileId = fileId.split('?')[0];
    }
    final directUrl = "https://drive.google.com/uc?export=view&id=$fileId";
    return directUrl;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('news')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('No hay publicaciones disponibles.'));
        }

        final newsDocs = snapshot.data!.docs;
        return ListView.builder(
          itemCount: newsDocs.length,
          itemBuilder: (context, index) {
            final doc = newsDocs[index];
            final data = doc.data() as Map<String, dynamic>;

            final title = data['title'] ?? 'Sin título';
            final content = data['content'] ?? 'Sin contenido';
            final rawImageUrl = data['imageUrl'] ?? '';

            final finalUrl = _convertDriveLink(rawImageUrl);

            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Para redondear la parte superior de la imagen
                  if (finalUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      child: Image.network(
                        finalUrl,
                        fit: BoxFit.cover,
                        height: 350,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 250,
                            color: Colors.grey,
                            alignment: Alignment.center,
                            child: Text(
                              'No se pudo cargar la imagen',
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        },
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.all(12.0),
                    child: ListTile(
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Padding(
                        padding: EdgeInsets.only(top: 6.0),
                        child: Text(
                          content,
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
