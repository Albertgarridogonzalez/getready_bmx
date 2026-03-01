import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:google_fonts/google_fonts.dart';

String formatMs(dynamic msInput) {
  int ms = 0;
  if (msInput is num) {
    ms = msInput.toInt();
  } else if (msInput is String) {
    ms = int.tryParse(msInput) ?? 0;
  }
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
        stream:
            FirebaseFirestore.instance.collection('leaderboards').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No hay records registrados.'));
          }

          final leaderboardDocs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 120, top: 20),
            itemCount: leaderboardDocs.length,
            itemBuilder: (context, index) {
              final data =
                  leaderboardDocs[index].data() as Map<String, dynamic>;
              final String location = data['location'] ?? 'Sin ubicación';
              final List<dynamic> records = data['records'] ?? [];

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
                        Text(
                          location.toUpperCase(),
                          style: GoogleFonts.orbitron(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(height: 1),
                        const SizedBox(height: 16),
                        ...records.asMap().entries.map((entry) {
                          final i = entry.key;
                          final record = entry.value;
                          final int timeMs =
                              (record['time'] as num?)?.toInt() ?? 999999;

                          return _LeaderboardRow(
                            rank: i + 1,
                            name: record['name'] ?? 'Piloto',
                            time: formatMs(timeMs),
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
