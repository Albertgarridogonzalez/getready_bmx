import 'package:flutter/material.dart';
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
