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
          
          // Mapea cada ubicación a la lista de pilotos y a su distancia (en metros)
          Map<String, List<Map<String, dynamic>>> locationToPilots = {};
          Map<String, int> locationToDistance = {};

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final location = data['location'] ?? 'Sin ubicación';
              // Asumimos que 'distance' viene en metros
              final int distance = data['distance'] ?? 0;
              final List<dynamic> pilots = data['pilots'] ?? [];

              // Si ya se registró la ubicación, nos quedamos con el primero (o podrías promediar, etc.)
              if (!locationToDistance.containsKey(location)) {
                locationToDistance[location] = distance;
              }

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

          // Ordenar pilotos en cada ubicación y rellenar la lista hasta 20 elementos
          locationToPilots.forEach((key, list) {
            list.sort((a, b) => (a['bestTime'] as int).compareTo(b['bestTime'] as int));
            while (list.length < 20) {
              list.add({'name': '---', 'bestTime': 999999});
            }
          });

          final locationKeys = locationToPilots.keys.toList();

          return Padding(
            padding: EdgeInsets.symmetric(horizontal: 8.0),
            child: ListView.builder(
              itemCount: locationKeys.length,
              itemBuilder: (context, index) {
                final loc = locationKeys[index];
                final pilots = locationToPilots[loc]!.take(10).toList();
                final distance = locationToDistance[loc] ?? 0;

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Título con la ubicación y la distancia
                        Text(
                          "$loc - ${distance}m",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Divider(),
                        ...pilots.take(5).map((pilot) {
                          final name = pilot['name'] ?? '---';
                          final int bestTimeMs = pilot['bestTime'] ?? 999999;
                          final bestTimeFormatted = formatMs(bestTimeMs);

                          Widget leadingWidget;
                          final int position = pilots.indexOf(pilot);
                          switch (position) {
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
                                child: Text((position + 1).toString()),
                              );
                          }

                          return ListTile(
                            leading: leadingWidget,
                            title: Text(name),
                            subtitle: Text("Mejor tiempo: $bestTimeFormatted seg"),
                          );
                        }).toList(),
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
