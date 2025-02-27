import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:getready_bmx/providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController pilotNameController = TextEditingController();

  // Controladores para el popup de “Subir Publicación”
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();

  // Controlador para el popup de “Crear Piloto”
  final TextEditingController _newPilotController = TextEditingController();

  // ---------- Variables para admin (sesiones/pilotos/tiempos) ----------
  String? _selectedSessionId; // ID de la sesión elegida
  String? _selectedPilotId; // ID del piloto elegido dentro de esa sesión
  final TextEditingController _editTimeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && doc.data() != null) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        setState(() {
          pilotNameController.text = data['pilotName'] ?? '';
        });

        bool darkMode = data['darkMode'] ?? true;
        String paletteStr = data['palette'] ?? 'blue';
        ColorPalette palette;
        switch (paletteStr) {
          case 'red':
            palette = ColorPalette.red;
            break;
          case 'green':
            palette = ColorPalette.green;
            break;
          case 'purple':
            palette = ColorPalette.purple;
            break;
          case 'orange':
            palette = ColorPalette.orange;
            break;
          case 'blue':
          default:
            palette = ColorPalette.blue;
            break;
        }

        Provider.of<ThemeProvider>(context, listen: false)
            .setDarkMode(darkMode, save: false);
        Provider.of<ThemeProvider>(context, listen: false)
            .setPalette(palette, save: false);
      }
    }
  }

  // -----------------------------------------------------------------------
  // Función para actualizar el nombre del piloto
  // -----------------------------------------------------------------------
  Future<void> updatePilotName(String userId) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'pilotName': pilotNameController.text,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nombre del piloto actualizado'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Funciones para eliminar y editar tiempos en sesiones
  // -----------------------------------------------------------------------
  Future<void> _deleteTime(String sessionId, String pilotId, int timeIndex) async {
    final sessionRef = FirebaseFirestore.instance.collection('sessions').doc(sessionId);
    final sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) return;

    final data = sessionDoc.data() as Map<String, dynamic>;
    List<dynamic> pilots = data['pilots'] ?? [];

    for (int i = 0; i < pilots.length; i++) {
      final pilot = pilots[i] as Map<String, dynamic>;
      if (pilot['id'] == pilotId) {
        List<dynamic> times = pilot['times'] ?? [];
        if (timeIndex >= 0 && timeIndex < times.length) {
          times.removeAt(timeIndex);
        }
        pilot['times'] = times;
        pilots[i] = pilot;
        break;
      }
    }
    await sessionRef.update({'pilots': pilots});
  }

  Future<void> _editTime(String sessionId, String pilotId, int timeIndex, int newTime) async {
    final sessionRef = FirebaseFirestore.instance.collection('sessions').doc(sessionId);
    final sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) return;

    final data = sessionDoc.data() as Map<String, dynamic>;
    List<dynamic> pilots = data['pilots'] ?? [];

    for (int i = 0; i < pilots.length; i++) {
      final pilot = pilots[i] as Map<String, dynamic>;
      if (pilot['id'] == pilotId) {
        List<dynamic> times = pilot['times'] ?? [];
        if (timeIndex >= 0 && timeIndex < times.length) {
          times[timeIndex] = newTime;
        }
        pilot['times'] = times;
        pilots[i] = pilot;
        break;
      }
    }
    await sessionRef.update({'pilots': pilots});
  }

  void _showEditTimeDialog(String sessionId, String pilotId, int timeIndex, int currentTime) {
    _editTimeController.text = currentTime.toString();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Editar Tiempo'),
          content: TextField(
            controller: _editTimeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Nuevo Tiempo'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newTime = int.tryParse(_editTimeController.text);
                if (newTime != null) {
                  await _editTime(sessionId, pilotId, timeIndex, newTime);
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

  // -----------------------------------------------------------------------
  // Sección de administración: elegir sesión, piloto y gestionar tiempos
  // -----------------------------------------------------------------------
  Widget _buildAdminSessionPilotTimesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Seleccionar Sesión:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance
              .collection('sessions')
              .orderBy('date', descending: true)
              .get(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Text("No hay sesiones creadas.");
            }
            return DropdownButton<String>(
              value: _selectedSessionId,
              hint: Text("Elige la sesión"),
              isExpanded: true,
              onChanged: (val) {
                setState(() {
                  _selectedSessionId = val;
                  _selectedPilotId = null;
                });
              },
              items: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final date = data['date'] is Timestamp
                    ? (data['date'] as Timestamp).toDate()
                    : (data['date'] ?? DateTime.now());
                final location = data['location'] ?? 'Ubicación desconocida';
                final dateStr = date.toString().split(' ')[0];
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text("$location, $dateStr"),
                );
              }).toList(),
            );
          },
        ),
        SizedBox(height: 16),

        // Dropdown de piloto (dentro de la sesión seleccionada)
        Text(
          "Seleccionar Piloto:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (_selectedSessionId == null)
          Text("Primero selecciona una sesión"),
        if (_selectedSessionId != null)
          FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('sessions')
                .doc(_selectedSessionId)
                .get(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }
              final doc = snapshot.data;
              if (doc == null || !doc.exists) {
                return Text("Sesión no encontrada");
              }
              final data = doc.data() as Map<String, dynamic>;
              final List<dynamic> pilots = data['pilots'] ?? [];

              if (pilots.isEmpty) {
                return Text("No hay pilotos en esta sesión");
              }

              return DropdownButton<String>(
                value: _selectedPilotId,
                hint: Text("Elige un piloto"),
                isExpanded: true,
                onChanged: (val) {
                  setState(() {
                    _selectedPilotId = val;
                  });
                },
                items: pilots.map((p) {
                  final pilotMap = p as Map<String, dynamic>;
                  final pid = pilotMap['id'] as String?;
                  final pname = pilotMap['name'] as String?;
                  return DropdownMenuItem<String>(
                    value: pid,
                    child: Text(pname ?? 'Piloto sin nombre'),
                  );
                }).toList(),
              );
            },
          ),
        SizedBox(height: 16),

        // Lista de tiempos del piloto seleccionado
        Text(
          "Tiempos del Piloto:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (_selectedSessionId != null && _selectedPilotId != null)
          _buildTimesList(_selectedSessionId!, _selectedPilotId!),
      ],
    );
  }

  Widget _buildTimesList(String sessionId, String pilotId) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('sessions')
          .doc(sessionId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Center(child: CircularProgressIndicator());
        }
        final doc = snapshot.data;
        if (doc == null || !doc.exists) {
          return Text("Sesión no encontrada");
        }
        final data = doc.data() as Map<String, dynamic>;
        final List<dynamic> pilots = data['pilots'] ?? [];

        final pilotMap = pilots.firstWhere(
          (p) => (p['id'] == pilotId),
          orElse: () => null,
        );
        if (pilotMap == null) {
          return Text("No se encontró el piloto en esta sesión");
        }

        final times = pilotMap['times'] as List<dynamic>? ?? [];
        if (times.isEmpty) {
          return Text("No hay tiempos para este piloto.");
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: NeverScrollableScrollPhysics(),
          itemCount: times.length,
          itemBuilder: (context, index) {
            final timeVal = times[index];
            return Card(
              margin: EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                title: Text("Tiempo: $timeVal seg"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () {
                        _showEditTimeDialog(sessionId, pilotId, index, timeVal);
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete),
                      onPressed: () async {
                        await _deleteTime(sessionId, pilotId, index);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Popup para Subir Publicación (nueva “noticia”)
  // -----------------------------------------------------------------------
  void _showPublicationPopup() {
    // Limpiamos los campos antes de abrir
    _titleController.clear();
    _contentController.clear();
    _imageUrlController.clear();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Nueva Publicación'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(labelText: 'Título'),
                ),
                TextField(
                  controller: _contentController,
                  decoration: InputDecoration(labelText: 'Contenido'),
                  maxLines: 3,
                ),
                TextField(
                  controller: _imageUrlController,
                  decoration: InputDecoration(labelText: 'URL de la imagen'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Subimos a Firestore en la colección "news"
                await FirebaseFirestore.instance.collection('news').add({
                  'title': _titleController.text,
                  'content': _contentController.text,
                  'imageUrl': _imageUrlController.text,
                  'timestamp': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              },
              child: Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Popup para Crear Piloto (solo solicita el nombre)
  // -----------------------------------------------------------------------
  void _showCreatePilotPopup() {
    _newPilotController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Crear Nuevo Piloto'),
          content: TextField(
            controller: _newPilotController,
            decoration: InputDecoration(labelText: 'Nombre del piloto'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final pilotName = _newPilotController.text.trim();
                if (pilotName.isNotEmpty) {
                  // Se crea un documento en 'users' con email vacío, role "user" y pilotName
                  await FirebaseFirestore.instance.collection('users').add({
                    'email': '',
                    'role': 'user',
                    'pilotName': pilotName,
                  });
                  
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Piloto creado exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Popup para borrar pilotos (lista de cards de pilotos)
  // -----------------------------------------------------------------------
  void _showDeletePilotsPopup() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Borrar Pilotos'),
          content: Container(
            width: double.maxFinite,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'user')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return Text("No hay pilotos para borrar.");
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final pilotName = data['pilotName'] ?? 'Sin nombre';
                    return Card(
                      child: ListTile(
                        title: Text(pilotName),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            // Confirmar borrado
                            showDialog(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  title: Text('Confirmar borrado'),
                                  content: Text('¿Estás seguro de borrar a $pilotName?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(context); // Cierra confirmación
                                        Navigator.pop(context); // Cierra popup de borrar pilotos
                                        await _deletePilot(doc.id);
                                      },
                                      child: Text('Borrar', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  // Función para borrar piloto y limpiar datos en sesiones
  Future<void> _deletePilot(String pilotId) async {
    // Borrar usuario en la colección 'users'
    await FirebaseFirestore.instance.collection('users').doc(pilotId).delete();

    // Buscar y actualizar sesiones en las que aparezca este piloto
    QuerySnapshot sessionsSnapshot = await FirebaseFirestore.instance.collection('sessions').get();
    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (var sessionDoc in sessionsSnapshot.docs) {
      Map<String, dynamic> sessionData = sessionDoc.data() as Map<String, dynamic>;
      List<dynamic> pilots = sessionData['pilots'] ?? [];
      // Filtrar pilotos removiendo aquél con id == pilotId
      List<dynamic> updatedPilots = pilots.where((p) => (p['id'] as String) != pilotId).toList();
      if (updatedPilots.length != pilots.length) {
        batch.update(sessionDoc.reference, {'pilots': updatedPilots});
      }
    }
    await batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Piloto borrado exitosamente'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final bool isAdmin =
        user?.email == '1@1.1' || user?.email == 'admin@admin.com';

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              // --- Fila superior con nombre, botón de cerrar sesión y menú de ajustes para admin ---
              Row(
                children: [
                  // Campo para el nombre del piloto
                  Expanded(
                    child: TextField(
                      controller: pilotNameController,
                      decoration: InputDecoration(labelText: 'Nombre del piloto'),
                    ),
                  ),
                  SizedBox(width: 20),
                  ElevatedButton(
                    onPressed: () async {
                      await authProvider.signOut();
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        '/login',
                        (route) => false,
                      );
                    },
                    child: Text('Cerrar Sesión'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                  SizedBox(width: 20),
                  if (isAdmin)
                    // Menú desplegable de ajustes para admin
                    PopupMenuButton<String>(
                      icon: Icon(Icons.settings, color: const Color.fromARGB(255, 70, 69, 69)),
                      onSelected: (value) {
                        if (value == 'subir') {
                          _showPublicationPopup();
                        } else if (value == 'crear') {
                          _showCreatePilotPopup();
                        } else if (value == 'borrar') {
                          _showDeletePilotsPopup();
                        }
                      },
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        PopupMenuItem<String>(
                          value: 'subir',
                          child: Text('Subir Publicación'),
                        ),
                        PopupMenuItem<String>(
                          value: 'crear',
                          child: Text('Crear Piloto'),
                        ),
                        PopupMenuItem<String>(
                          value: 'borrar',
                          child: Text('Borrar Pilotos'),
                        ),
                      ],
                    ),
                ],
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: user != null ? () => updatePilotName(user.uid) : null,
                child: Text('Guardar Nombre'),
              ),
              SizedBox(height: 20),

              // Sección para cambiar tema (oscuro/claro) y paleta de colores
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Modo Oscuro / Claro", style: TextStyle(fontSize: 16)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(themeProvider.isDarkMode ? "Oscuro" : "Claro"),
                          Switch(
                            value: themeProvider.isDarkMode,
                            onChanged: (value) async {
                              themeProvider.setDarkMode(value);
                              if (user != null) {
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .update({'darkMode': value});
                              }
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text("Selecciona la paleta de colores:",
                          style: TextStyle(fontSize: 16)),
                      SizedBox(
                        height: 80,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: ColorPalette.values.map((palette) {
                            return GestureDetector(
                              onTap: () async {
                                themeProvider.setPalette(palette);
                                if (user != null) {
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(user.uid)
                                      .update({
                                    'palette': palette.toString().split('.').last,
                                  });
                                }
                              },
                              child: Container(
                                margin: EdgeInsets.all(8.0),
                                width: 60,
                                decoration: BoxDecoration(
                                  color: themeProvider.getSampleColorForPalette(palette),
                                  border: themeProvider.palette == palette
                                      ? Border.all(width: 3, color: Colors.white)
                                      : null,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: 20),

              // ---------- SECCIÓN DE ADMIN: EDITAR TIEMPOS DE SESIÓN ----------
              if (isAdmin) _buildAdminSessionPilotTimesSection(),
            ],
          ),
        ),
      ),
    );
  }
}
