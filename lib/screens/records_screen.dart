import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:google_fonts/google_fonts.dart';

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
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      setState(() {
        orderByBestTime = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = themeProvider.primaryColor;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final bool isAdmin =
        (user?.email == '1@1.1' || user?.email == 'admin@admin.com');

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  "ORDENAR:",
                  style: GoogleFonts.orbitron(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    setState(() {
                      orderByBestTime = value == 'Mejor Tiempo';
                    });
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                        value: 'Mejor Tiempo',
                        child: Text('Mejor Tiempo',
                            style: GoogleFonts.orbitron(fontSize: 12))),
                    PopupMenuItem(
                        value: 'Cronológico',
                        child: Text('Cronológico',
                            style: GoogleFonts.orbitron(fontSize: 12))),
                  ],
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          orderByBestTime ? 'MEJOR' : 'FECHA',
                          style: GoogleFonts.orbitron(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: primary),
                        ),
                        Icon(Icons.keyboard_arrow_down,
                            size: 18, color: primary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user?.uid)
                  .get(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                  return const Center(
                      child: Text('No se encontraron datos del usuario.'));
                }

                final userData =
                    userSnapshot.data!.data() as Map<String, dynamic>;
                final List<dynamic> rawUserPilots = userData['pilots'] ?? [];
                final String? role = userData['role'];
                final List<String> userPilots = rawUserPilots.map((pilot) {
                  if (pilot is Map<String, dynamic>) {
                    return pilot['name']?.toString() ?? '';
                  } else if (pilot is String) {
                    return pilot;
                  }
                  return '';
                }).toList();
                final List<dynamic> assignedPilots =
                    userData['assignedPilots'] ?? [];

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('sessions')
                      .orderBy('date', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                          child: Text('No hay sesiones registradas.'));
                    }

                    final sessionDocs = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.only(bottom: 120, top: 10),
                      itemCount: sessionDocs.length,
                      itemBuilder: (context, index) {
                        final doc = sessionDocs[index];
                        final data = doc.data() as Map<String, dynamic>;

                        DateTime sessionDate = (data['date'] is Timestamp)
                            ? (data['date'] as Timestamp).toDate()
                            : DateTime.now();
                        final dateStr =
                            "${sessionDate.day}/${sessionDate.month}/${sessionDate.year}";
                        final location =
                            data['location'] ?? 'Ubicación desconocida';
                        // final int distance = data['distance'] ?? 0;
                        final List<dynamic> pilots = data['pilots'] ?? [];

                        List<dynamic> filteredPilots;
                        if (isAdmin) {
                          filteredPilots = pilots;
                        } else if (role == 'trainer') {
                          filteredPilots = pilots.where((p) {
                            final pilotIdComp =
                                (p as Map<String, dynamic>)['id'] ?? '';
                            return assignedPilots.contains(pilotIdComp);
                          }).toList();
                        } else {
                          filteredPilots = pilots
                              .where(
                                  (pilot) => userPilots.contains(pilot['name']))
                              .toList();
                        }

                        if (filteredPilots.isEmpty)
                          return const SizedBox.shrink();

                        return Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: primary.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24)),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          location.toUpperCase(),
                                          style: GoogleFonts.orbitron(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: primary,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        dateStr,
                                        style: GoogleFonts.orbitron(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  /* Text(
                                    "Distancia: ${distance}m",
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.grey),
                                  ), */
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Divider(height: 1),
                                  ),
                                  ...filteredPilots.map((pilotMap) {
                                    final String pilotName =
                                        pilotMap['name'] ?? 'Desconocido';
                                    final List<dynamic> times =
                                        pilotMap['times'] ?? [];
                                    List<int> sortedTimes =
                                        times.map((t) => t as int).toList();
                                    if (orderByBestTime) sortedTimes.sort();

                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.person_outline,
                                                  size: 18, color: primary),
                                              const SizedBox(width: 8),
                                              Text(
                                                pilotName,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: sortedTimes
                                                .map((t) => Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10,
                                                          vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: primary
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                        border: Border.all(
                                                            color: primary
                                                                .withOpacity(
                                                                    0.2)),
                                                      ),
                                                      child: Text(
                                                        "${formatMs(t)}s",
                                                        style: GoogleFonts
                                                            .orbitron(
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: primary,
                                                        ),
                                                      ),
                                                    ))
                                                .toList(),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  if (role == 'user') ...[
                                    const Divider(),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "OBSERVACIONES",
                                          style: GoogleFonts.orbitron(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey),
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.add_comment_outlined,
                                              size: 20, color: primary),
                                          onPressed: () =>
                                              _showAddObservationPopup(
                                                  context, doc.id, user!.uid),
                                        ),
                                      ],
                                    ),
                                    StreamBuilder<QuerySnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('sessionNotes')
                                          .where('sessionId', isEqualTo: doc.id)
                                          .where('userId', isEqualTo: user!.uid)
                                          .snapshots(),
                                      builder: (context, noteSnapshot) {
                                        if (noteSnapshot.connectionState ==
                                            ConnectionState.waiting) {
                                          return const SizedBox(
                                              height: 20,
                                              child: LinearProgressIndicator());
                                        }
                                        if (!noteSnapshot.hasData ||
                                            noteSnapshot.data!.docs.isEmpty) {
                                          return const Text(
                                              'Sin observaciones.',
                                              style: TextStyle(
                                                  color: Colors.grey,
                                                  fontSize: 12));
                                        }
                                        final notesDocs =
                                            noteSnapshot.data!.docs;
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: notesDocs.map((noteDoc) {
                                            final noteData = noteDoc.data()
                                                as Map<String, dynamic>;
                                            return Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: themeProvider.isDarkMode
                                                    ? Colors.white
                                                        .withOpacity(0.05)
                                                    : Colors.black
                                                        .withOpacity(0.03),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      noteData[
                                                              'observations'] ??
                                                          '',
                                                      style: const TextStyle(
                                                          fontSize: 13),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.edit_outlined,
                                                        size: 16,
                                                        color: Colors.blue),
                                                    onPressed: () =>
                                                        _showEditObservationPopup(
                                                            context,
                                                            noteDoc.id,
                                                            noteData[
                                                                'observations']),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.delete_outline,
                                                        size: 16,
                                                        color: Colors.red),
                                                    onPressed: () =>
                                                        _deleteObservation(
                                                            context,
                                                            noteDoc.id),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        );
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
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

// Mostrar popup para editar una observación existente
void _showEditObservationPopup(
    BuildContext context, String noteId, String currentText) {
  final TextEditingController obsController =
      TextEditingController(text: currentText);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Editar Observación'),
        content: TextField(
            controller: obsController,
            maxLines: 3,
            decoration: InputDecoration(hintText: 'Edita tu nota...')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (obsController.text.trim().isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('sessionNotes')
                    .doc(noteId)
                    .update({
                  'observations': obsController.text.trim(),
                  'timestamp': FieldValue.serverTimestamp(),
                });
              }
              Navigator.pop(context);
            },
            child: Text('Guardar Cambios'),
          ),
        ],
      );
    },
  );
}

// Eliminar una observación con confirmación
void _deleteObservation(BuildContext context, String noteId) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Eliminar Observación'),
        content:
            Text('¿Estás seguro de que quieres eliminar esta observación?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('sessionNotes')
                  .doc(noteId)
                  .delete();
              Navigator.pop(context);
            },
            child: Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      );
    },
  );
}

void _showAddObservationPopup(
    BuildContext context, String sessionId, String userId) {
  final TextEditingController obsController = TextEditingController();

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Añadir Observación'),
        content: TextField(
          controller: obsController,
          maxLines: 3,
          decoration: InputDecoration(hintText: 'Escribe tu nota...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final noteText = obsController.text.trim();
              if (noteText.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('sessionNotes')
                    .add({
                  'sessionId': sessionId,
                  'userId': userId,
                  'observations': noteText,
                  'timestamp': FieldValue.serverTimestamp(),
                });
              }
              Navigator.pop(context);
            },
            child: Text('Guardar'),
          ),
        ],
      );
    },
  );
}
