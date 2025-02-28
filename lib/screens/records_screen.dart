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
  void initState() {
    super.initState();
    // Aplica filtro por mejor tiempo desde el inicio
    Future.delayed(Duration.zero, () {
      setState(() {
        orderByBestTime = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final bool isAdmin =
        (user?.email == '1@1.1' || user?.email == 'admin@admin.com');

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
                  PopupMenuItem(
                      value: 'Mejor Tiempo',
                      child: Text('Ordenar por Mejor Tiempo')),
                  PopupMenuItem(
                      value: 'Cronológico',
                      child: Text('Ordenar Cronológicamente')),
                ],
                icon: Icon(Icons.sort),
              ),
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
                  return Center(child: CircularProgressIndicator());
                }
                if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                  return Center(
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
                      return Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                          child: Text('No hay sesiones registradas.'));
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
                        final location =
                            data['location'] ?? 'Ubicación desconocida';
                        final int distance = data['distance'] ?? 0;
                        final List<dynamic> pilots = data['pilots'] ?? [];

                        // Filtrado según rol:
                        List<dynamic> filteredPilots;
                        if (isAdmin) {
                          filteredPilots = pilots;
                        } else if (role == 'trainer') {
                          filteredPilots = pilots.where((p) {
                            final pilotMap = p as Map<String, dynamic>;
                            final pilotIdComp = pilotMap['id'] ?? '';
                            return assignedPilots.contains(pilotIdComp);
                          }).toList();
                        } else {
                          // Caso usuario normal
                          filteredPilots = pilots.where((pilot) {
                            return userPilots.contains(pilot['name']);
                          }).toList();
                        }

                        if (filteredPilots.isEmpty) {
                          return SizedBox.shrink();
                        }

                        return Card(
                          margin:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Datos de la sesión
                                Text(
                                  "$location - ${distance}m",
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
                                // Lista de pilotos
                                Column(
                                  children: filteredPilots.map((pilotMap) {
                                    final String pilotName =
                                        pilotMap['name'] ?? 'Desconocido';
                                    final List<dynamic> times =
                                        pilotMap['times'] ?? [];
                                    List<int> sortedTimes =
                                        times.map((t) => t as int).toList();
                                    if (orderByBestTime) {
                                      sortedTimes.sort();
                                    }
                                    final formattedTimes = sortedTimes
                                        .map((t) => formatMs(t))
                                        .toList();
                                    final timesStr = formattedTimes.isEmpty
                                        ? '---'
                                        : formattedTimes.join("  ");
                                    return ListTile(
                                      leading: Icon(Icons.person),
                                      title: Text(
                                        pilotName,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text('Tiempos: $timesStr'),
                                    );
                                  }).toList(),
                                ),
                                // Si el usuario es de tipo "user", mostramos el botón y las observaciones
                                if (role == 'user') ...[
                                  Divider(),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      icon: Icon(Icons.edit_note),
                                      label: Text("Añadir Observación"),
                                      onPressed: () {
                                        _showAddObservationPopup(
                                            context, doc.id, user!.uid);
                                      },
                                    ),
                                  ),
                                  // Muestra las observaciones añadidas por el usuario para esta sesión
                                  StreamBuilder<QuerySnapshot>(
                                    stream: FirebaseFirestore.instance
                                        .collection('sessionNotes')
                                        .where('sessionId', isEqualTo: doc.id)
                                        .where('userId', isEqualTo: user!.uid)
                                        .snapshots(),
                                    builder: (context, noteSnapshot) {
                                      if (noteSnapshot.connectionState ==
                                          ConnectionState.waiting) {
                                        return CircularProgressIndicator();
                                      }
                                      if (!noteSnapshot.hasData ||
                                          noteSnapshot.data!.docs.isEmpty) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 8.0),
                                          child: Text('Sin observaciones.',
                                              style: TextStyle(
                                                  color: Colors.grey)),
                                        );
                                      }
                                      final notesDocs = noteSnapshot.data!.docs;
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: notesDocs.map((noteDoc) {
                                          final noteData = noteDoc.data()
                                              as Map<String, dynamic>;
                                          final noteText =
                                              noteData['observations'] ??
                                                  'Sin texto';
                                          final noteId = noteDoc.id;
                                          final Timestamp? ts =
                                              noteData['timestamp'];
                                          final String dateStr = ts != null
                                              ? "${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year} ${ts.toDate().hour}:${ts.toDate().minute}"
                                              : 'Fecha desconocida';

                                          return Card(
                                            margin: EdgeInsets.symmetric(
                                                vertical: 4.0),
                                            color: Theme.of(context)
                                                        .brightness ==
                                                    Brightness.dark
                                                ? Colors.grey[
                                                    800] // Gris oscuro en modo oscuro
                                                : Colors.grey[
                                                    200], // Gris claro en modo claro
                                            child: ListTile(
                                              leading: Icon(
                                                Icons.note,
                                                color: Theme.of(context)
                                                            .brightness ==
                                                        Brightness.dark
                                                    ? Colors
                                                        .white // Ícono blanco en modo oscuro
                                                    : Colors
                                                        .black, // Ícono negro en modo claro
                                              ),
                                              title: Text(
                                                noteText,
                                                style: TextStyle(fontSize: 14),
                                              ),
                                              subtitle: Text("Añadido el $dateStr"),
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: Icon(Icons.edit, color: Colors.blue),
                                                    onPressed: () {
                                                      _showEditObservationPopup(context, noteId, noteText);
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: Icon(Icons.delete, color: Colors.red),
                                                    onPressed: () {
                                                      _deleteObservation(context, noteId);
                                                    },
                                                  ),
                                                ],
                                              ),
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
void _showEditObservationPopup(BuildContext context, String noteId, String currentText) {
  final TextEditingController obsController = TextEditingController(text: currentText);

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text('Editar Observación'),
        content: TextField(controller: obsController, maxLines: 3, decoration: InputDecoration(hintText: 'Edita tu nota...')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (obsController.text.trim().isNotEmpty) {
                await FirebaseFirestore.instance.collection('sessionNotes').doc(noteId).update({
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
        content: Text('¿Estás seguro de que quieres eliminar esta observación?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('sessionNotes').doc(noteId).delete();
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
