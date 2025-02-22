import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
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
  final flutterReactiveBle = FlutterReactiveBle();
  final TextEditingController pilotNameController = TextEditingController();

  bool isConnected = false;
  String? deviceId;
  StreamSubscription<ConnectionStateUpdate>? connectionSubscription;
  StreamSubscription<List<int>>? dataSubscription;

  // ---------- Variables para la sección de admin (sesiones/pilotos/tiempos) ----------
  String? _selectedSessionId;  // ID de la sesión elegida
  String? _selectedPilotId;    // ID del piloto elegido dentro de esa sesión

  // Para editar un tiempo puntual, usamos un TextEditingController
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

  // -------------------- BLE Lógica (ya existente) --------------------
  void scanAndConnect() {
    final serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
    final characteristicUuid = Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");

    flutterReactiveBle.scanForDevices(withServices: [serviceUuid]).listen(
      (device) {
        if (device.name == "GetReady_BMX") {
          flutterReactiveBle
              .connectToDevice(id: device.id)
              .listen((connectionState) {
            if (connectionState.connectionState == DeviceConnectionState.connected) {
              setState(() {
                isConnected = true;
                deviceId = device.id;
              });
            }
          }, onError: (error) {
            print("Error de conexión: $error");
          });
        }
      },
    );
  }

  void disconnectDevice() {
    if (isConnected && deviceId != null) {
      flutterReactiveBle.clearGattCache(deviceId!);
      setState(() {
        isConnected = false;
        deviceId = null;
      });
    }
  }

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
  // 1) Función para eliminar un tiempo de la lista del piloto en la sesión
  // -----------------------------------------------------------------------
  Future<void> _deleteTime(String sessionId, String pilotId, int timeIndex) async {
    final sessionRef = FirebaseFirestore.instance.collection('sessions').doc(sessionId);
    final sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) return;

    final data = sessionDoc.data() as Map<String, dynamic>;
    List<dynamic> pilots = data['pilots'] ?? [];

    // Buscamos el piloto
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

    // Guardamos cambios
    await sessionRef.update({'pilots': pilots});
  }

  // -----------------------------------------------------------------------
  // 2) Función para editar un tiempo puntual
  // -----------------------------------------------------------------------
  Future<void> _editTime(String sessionId, String pilotId, int timeIndex, int newTime) async {
    final sessionRef = FirebaseFirestore.instance.collection('sessions').doc(sessionId);
    final sessionDoc = await sessionRef.get();
    if (!sessionDoc.exists) return;

    final data = sessionDoc.data() as Map<String, dynamic>;
    List<dynamic> pilots = data['pilots'] ?? [];

    // Buscamos el piloto
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

    // Guardamos cambios
    await sessionRef.update({'pilots': pilots});
  }

  // Diálogo para editar un tiempo
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
  // Construye la sección de administración (drop-down de sesión y piloto, lista de tiempos)
  // -----------------------------------------------------------------------
  Widget _buildAdminSessionPilotTimesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dropdown de sesiones
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
                  _selectedPilotId = null; // reset al cambiar de sesión
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

  // Construye la lista de tiempos del piloto y botones para eliminar/editar
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

        // Localizamos el piloto
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
                    // Botón Editar
                    IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () {
                        _showEditTimeDialog(sessionId, pilotId, index, timeVal);
                      },
                    ),
                    // Botón Eliminar
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
  // Construcción del widget principal
  // -----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final bool isAdmin = user?.email == '1@1.1' || user?.email == 'admin@admin.com';

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Campo para cambiar nombre de piloto
              TextField(
                controller: pilotNameController,
                decoration: InputDecoration(labelText: 'Nombre del piloto'),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                onPressed: user != null ? () => updatePilotName(user.uid) : null,
                child: Text('Guardar Nombre'),
              ),
              SizedBox(height: 20),
              // Botón para cerrar sesión
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
              SizedBox(height: 20),
              // Solo si es admin, mostramos botón de conexión al ESP32
              if (isAdmin) ...[
                ElevatedButton(
                  onPressed: isConnected ? disconnectDevice : scanAndConnect,
                  child: Text(isConnected ? 'Desconectar ESP32' : 'Conectar al ESP32'),
                ),
                SizedBox(height: 20),
              ],

              // Sección para cambiar el tema y la paleta de colores
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
                              final authProvider = Provider.of<AuthProvider>(context, listen: false);
                              String uid = authProvider.user!.uid;
                              await FirebaseFirestore.instance.collection('users').doc(uid).update({
                                'darkMode': value,
                              });
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 20),
                      Text("Selecciona la paleta de colores:", style: TextStyle(fontSize: 16)),
                      SizedBox(
                        height: 80,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: ColorPalette.values.map((palette) {
                            return GestureDetector(
                              onTap: () async {
                                themeProvider.setPalette(palette);
                                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                                String uid = authProvider.user!.uid;
                                await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(uid)
                                    .update({
                                  'palette': palette.toString().split('.').last,
                                });
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

              // ---------- SECCIÓN DE ADMIN: SELECCIONAR SESIÓN, PILOTO Y EDITAR TIEMPOS ----------
              if (isAdmin) _buildAdminSessionPilotTimesSection(),
            ],
          ),
        ),
      ),
    );
  }
}
