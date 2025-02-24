import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';

/// Convierte milisegundos en un string con 3 decimales de segundos.
String formatMs(int ms) {
  double seconds = ms / 1000.0;
  return seconds.toStringAsFixed(3);
}

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({Key? key}) : super(key: key);

  @override
  _RecordsScreenState createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  bool orderByBestTime = true;

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final bool isAdmin = (user?.email == '1@1.1' || user?.email == 'admin@admin.com');

    return Scaffold(
      body: Column(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: PopupMenuButton<String>(
                onSelected: (value) {
                  setState(() {
                    orderByBestTime = value == 'Mejor Tiempo';
                  });
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'Mejor Tiempo', child: Text('Ordenar por Mejor Tiempo')),
                  PopupMenuItem(value: 'Cronológico', child: Text('Ordenar Cronológicamente')),
                ],
                icon: Icon(Icons.sort),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('sessions')
                  .orderBy('date', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text('No hay sesiones registradas.'));
                }

                final sessionDocs = snapshot.data!.docs;

                return ListView.builder(
                  itemCount: sessionDocs.length,
                  itemBuilder: (context, index) {
                    final doc = sessionDocs[index];
                    final data = doc.data() as Map<String, dynamic>;

                    DateTime sessionDate = (data['date'] is Timestamp)
                        ? (data['date'] as Timestamp).toDate()
                        : DateTime.now();

                    final dateStr =
                        "${sessionDate.year}-${sessionDate.month.toString().padLeft(2, '0')}-${sessionDate.day.toString().padLeft(2, '0')}";
                    final location = data['location'] ?? 'Ubicación desconocida';
                    final List<dynamic> pilots = data['pilots'] ?? [];

                    final filteredPilots = isAdmin
                        ? pilots
                        : pilots.where((p) => p['id'] == user?.uid).toList();

                    if (!isAdmin && filteredPilots.isEmpty) {
                      return SizedBox.shrink();
                    }

                    return Card(
                      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              location,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Fecha: $dateStr',
                              style: TextStyle(color: Colors.grey[700]),
                            ),
                            Divider(),
                            Column(
                              children: filteredPilots.map((pilotData) {
                                final pilotMap = pilotData as Map<String, dynamic>;
                                final pilotName = pilotMap['name'] ?? 'Desconocido';
                                final List<dynamic> times = pilotMap['times'] ?? [];

                                List<int> sortedTimes = times.map((t) => t as int).toList();
                                if (orderByBestTime) {
                                  sortedTimes.sort();
                                }

                                final formattedTimes = sortedTimes.map((t) => formatMs(t)).toList();
                                final timesStr = formattedTimes.isEmpty
                                    ? '---'
                                    : formattedTimes.join("  ");

                                return ListTile(
                                  leading: Icon(Icons.person),
                                  title: Text(
                                    pilotName,
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text('Tiempos: $timesStr'),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}