import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';

class RecordsScreen extends StatelessWidget {
  const RecordsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    // Aquí ajusta tu condición de admin
    final bool isAdmin = (user?.email == '1@1.1' || user?.email == 'admin@admin.com');

    return Scaffold(
      //appBar: AppBar(title: Text('Historial de sesiones')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('sessions')
            .orderBy('date', descending: true) // Ordena por fecha descendente
            .snapshots(),
        builder: (context, snapshot) {
          // Mientras se obtienen datos
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          // Si no hay datos o lista vacía
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No hay sesiones registradas.'));
          }

          // Construimos la lista de Cards (una por sesión)
          final sessionDocs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: sessionDocs.length,
            itemBuilder: (context, index) {
              final doc = sessionDocs[index];
              final data = doc.data() as Map<String, dynamic>;

              // Obtenemos la fecha
              DateTime sessionDate;
              if (data['date'] is Timestamp) {
                sessionDate = (data['date'] as Timestamp).toDate();
              } else {
                // Si ya es DateTime
                sessionDate = data['date'] ?? DateTime.now();
              }

              // Para formatear la fecha sin usar intl:
              final dateStr =
                  "${sessionDate.year}-${sessionDate.month.toString().padLeft(2, '0')}-${sessionDate.day.toString().padLeft(2, '0')}";

              // También podrías simplemente usar: sessionDate.toString().split(' ')[0]
              final location = data['location'] ?? 'Ubicación desconocida';

              // Pilotos
              final List<dynamic> pilots = data['pilots'] ?? [];

              // Si eres admin, ves todos; si no, filtras por tu uid
              final filteredPilots = isAdmin
                  ? pilots
                  : pilots.where((p) => p['id'] == user?.uid).toList();

              // Si no eres admin y no tienes tiempos en esa sesión, no mostramos la Card
              if (!isAdmin && filteredPilots.isEmpty) {
                return SizedBox.shrink(); // Oculta esta sesión
              }

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ENCABEZADO: ubicación + fecha
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

                      // Lista de pilotos
                      Column(
                        children: filteredPilots.map((pilotData) {
                          final pilotMap = pilotData as Map<String, dynamic>;
                          final pilotName = pilotMap['name'] ?? 'Desconocido';
                          final List<dynamic> times = pilotMap['times'] ?? [];

                          // Convertimos la lista de tiempos a string
                          final timesStr = times.join(', ');

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
    );
  }
}
