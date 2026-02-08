import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:google_fonts/google_fonts.dart';

String formatMs(int ms) {
  double seconds = ms / 1000.0;
  return seconds.toStringAsFixed(3);
}

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = themeProvider.primaryColor;

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('sessions').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          Map<String, List<Map<String, dynamic>>> locationToPilots = {};
          Map<String, int> locationToDistance = {};

          if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
            for (var doc in snapshot.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final location = data['location'] ?? 'Sin ubicación';
              final int distance = data['distance'] ?? 0;
              final List<dynamic> pilots = data['pilots'] ?? [];

              if (!locationToDistance.containsKey(location)) {
                locationToDistance[location] = distance;
              }

              locationToPilots.putIfAbsent(location, () => []);

              for (var pilotEntry in pilots) {
                final pilotMap = pilotEntry as Map<String, dynamic>;
                final String pilotName =
                    pilotMap['name'] ?? 'Piloto sin nombre';
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
            list.sort((a, b) =>
                (a['bestTime'] as int).compareTo(b['bestTime'] as int));
          });

          final locationKeys = locationToPilots.keys.toList();

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120, top: 20),
            itemCount: locationKeys.length,
            itemBuilder: (context, index) {
              final loc = locationKeys[index];
              final pilots = locationToPilots[loc]!.take(10).toList();
              final distance = locationToDistance[loc] ?? 0;

              return Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withOpacity(0.1),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                loc.toUpperCase(),
                                style: GoogleFonts.orbitron(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primary,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "${distance}M",
                                style: GoogleFonts.orbitron(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        ...pilots.asMap().entries.map((entry) {
                          final i = entry.key;
                          final pilot = entry.value;
                          final bestTimeMs = pilot['bestTime'] ?? 999999;

                          return _LeaderboardRow(
                            rank: i + 1,
                            name: pilot['name'],
                            time: formatMs(bestTimeMs),
                            primaryColor: primary,
                          );
                        }).toList(),
                      ],
                    ),
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

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final String name;
  final String time;
  final Color primaryColor;

  const _LeaderboardRow({
    required this.rank,
    required this.name,
    required this.time,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    Color rankColor = Colors.grey.withOpacity(0.5);
    if (rank == 1) rankColor = Colors.amber;
    if (rank == 2) rankColor = const Color(0xFFC0C0C0);
    if (rank == 3) rankColor = const Color(0xFFCD7F32);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color:
                  rank <= 3 ? rankColor.withOpacity(0.2) : Colors.transparent,
              shape: BoxShape.circle,
              border: rank <= 3 ? Border.all(color: rankColor, width: 2) : null,
            ),
            child: Text(
              "$rank",
              style: GoogleFonts.orbitron(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: rank <= 3 ? rankColor : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Text(
            "$time s",
            style: GoogleFonts.orbitron(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: primaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
