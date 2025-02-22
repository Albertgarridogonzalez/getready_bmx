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
      //appBar: AppBar(title: Text('Leaderboard por Ubicación')),
      body: StreamBuilder<QuerySnapshot>(
        // Leemos TODAS las sesiones
        stream: FirebaseFirestore.instance.collection('sessions').snapshots(),
        builder: (context, snapshot) {
          // Indicador de carga
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          // Si no hay nada
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No hay datos de sesiones aún.'));
          }

          // 1. Recorremos las sesiones y agrupamos por ubicación
          Map<String, Map<String, Map<String, dynamic>>> locationToPilots = {};

          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final location = data['location'] ?? 'Sin ubicación';
            final List<dynamic> pilots = data['pilots'] ?? [];

            // Si no existe la key para esta ubicación, la creamos
            locationToPilots.putIfAbsent(location, () => {});

            // Recorremos los pilotos
            for (var pilot in pilots) {
              final pilotMap = pilot as Map<String, dynamic>;
              final pilotId = pilotMap['id'] ?? 'desconocido';
              final pilotName = pilotMap['name'] ?? 'Piloto sin nombre';
              final List<dynamic> times = pilotMap['times'] ?? [];
              if (times.isEmpty) continue;

              // El mejor tiempo de esa lista
              final int bestTimePilot = times
                  .map((t) => t as int)
                  .reduce((a, b) => a < b ? a : b);

              final existingPilot = locationToPilots[location]![pilotId];

              if (existingPilot == null) {
                // Si no existía, lo creamos
                locationToPilots[location]![pilotId] = {
                  'name': pilotName,
                  'bestTime': bestTimePilot,
                };
              } else {
                // Si ya existía, comparamos para quedarnos con el tiempo menor
                final currentBest = existingPilot['bestTime'] as int;
                if (bestTimePilot < currentBest) {
                  locationToPilots[location]![pilotId] = {
                    'name': pilotName,
                    'bestTime': bestTimePilot,
                  };
                }
              }
            }
          }

          // 2. Construimos la UI con una Card por ubicación
          final locationKeys = locationToPilots.keys.toList();

          return ListView.builder(
            itemCount: locationKeys.length,
            itemBuilder: (context, index) {
              final loc = locationKeys[index];
              final pilotsMap = locationToPilots[loc]!;

              // Convertimos a lista para poder ordernar
              final pilotList = pilotsMap.entries.map((entry) {
                return {
                  'pilotId': entry.key,
                  'name': entry.value['name'],
                  'bestTime': entry.value['bestTime'],
                };
              }).toList();

              // Orden asc por bestTime
              pilotList.sort((a, b) =>
                  (a['bestTime'] as int).compareTo(b['bestTime'] as int));

              // Tomamos solo el top 5
              final top5 = pilotList.take(5).toList();

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Encabezado de la ubicación
                      Text(
                        loc,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Divider(),
                      // Lista de pilotos (top 5)
                      ...top5.asMap().entries.map((entry) {
                        final i = entry.key;       // índice (0,1,2,3,4)
                        final pilot = entry.value; // { 'name':..., 'bestTime':... }
                        final name = pilot['name'] ?? '---';
                        final int bestTimeMs = pilot['bestTime'] ?? 999999;

                        // Convertimos ms -> seg con 3 decimales
                        final bestTimeFormatted = formatMs(bestTimeMs);

                        // Definimos el leading según posición:
                        Widget leadingWidget;
                        switch (i) {
                          case 0:
                            // 1er lugar -> medalla de oro
                            leadingWidget = Icon(
                              Icons.emoji_events,
                              color: Colors.amber,
                              size: 35,
                            );
                            break;
                          case 1:
                            // 2do lugar -> “medalla de plata”
                            leadingWidget = Icon(
                              Icons.emoji_events,
                              color: Colors.grey,
                              size: 35,
                            );
                            break;
                          case 2:
                            // 3er lugar -> “medalla de bronce”
                            leadingWidget = Icon(
                              Icons.emoji_events,
                              color: Colors.brown,
                              size: 35,
                            );
                            break;
                          case 3:
                            // 4to lugar -> muestra número 4
                            leadingWidget = CircleAvatar(
                              backgroundColor: Colors.blueGrey,
                              child: Text('4'),
                            );
                            break;
                          case 4:
                            // 5to lugar -> muestra número 5
                            leadingWidget = CircleAvatar(
                              backgroundColor: Colors.blueGrey,
                              child: Text('5'),
                            );
                            break;
                          default:
                            leadingWidget = Icon(Icons.person);
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
          );
        },
      ),
    );
  }
}
