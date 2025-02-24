import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Convierte milisegundos en un string con 3 decimales de segundos.
/// p.ej. 4590 ms => "4.590"
String formatMs(int ms) {
  double seconds = ms / 1000.0;
  return seconds.toStringAsFixed(3);
}

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('sessions').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          
          Map<String, List<Map<String, dynamic>>> locationToPilots = {};

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final location = data['location'] ?? 'Sin ubicación';
              final List<dynamic> pilots = data['pilots'] ?? [];

              locationToPilots.putIfAbsent(location, () => []);

              for (var pilot in pilots) {
                final pilotMap = pilot as Map<String, dynamic>;
                final pilotName = pilotMap['name'] ?? 'Piloto sin nombre';
                final List<dynamic> times = pilotMap['times'] ?? [];
                final int bestTimePilot = times.isNotEmpty
                    ? times.map((t) => t as int).reduce((a, b) => a < b ? a : b)
                    : 999999;
                
                locationToPilots[location]!.add({
                  'name': pilotName,
                  'bestTime': bestTimePilot,
                });
              }
            }
          }

          locationToPilots.forEach((key, list) {
            list.sort((a, b) => (a['bestTime'] as int).compareTo(b['bestTime'] as int));
            while (list.length < 10) {
              list.add({ 'name': '---', 'bestTime': 999999 });
            }
          });

          final locationKeys = locationToPilots.keys.toList();

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.8, // Ajustado para hacer las cards más altas
              ),
              itemCount: locationKeys.length,
              itemBuilder: (context, index) {
                final loc = locationKeys[index];
                final pilots = locationToPilots[loc]!.take(10).toList();

                return Card(
                  margin: EdgeInsets.all(8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Divider(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: pilots.length,
                            itemBuilder: (context, i) {
                              final name = pilots[i]['name'] ?? '---';
                              final int bestTimeMs = pilots[i]['bestTime'] ?? 999999;
                              final bestTimeFormatted = formatMs(bestTimeMs);

                              Widget leadingWidget;
                              switch (i) {
                                case 0:
                                  leadingWidget = Icon(Icons.emoji_events, color: Colors.amber, size: 35);
                                  break;
                                case 1:
                                  leadingWidget = Icon(Icons.emoji_events, color: Colors.grey, size: 35);
                                  break;
                                case 2:
                                  leadingWidget = Icon(Icons.emoji_events, color: Colors.brown, size: 35);
                                  break;
                                default:
                                  leadingWidget = CircleAvatar(
                                    backgroundColor: Colors.blueGrey,
                                    child: Text((i + 1).toString()),
                                  );
                              }

                              return ListTile(
                                leading: leadingWidget,
                                title: Text(name),
                                subtitle: Text("Mejor tiempo: $bestTimeFormatted seg"),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
