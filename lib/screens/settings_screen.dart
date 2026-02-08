import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:getready_bmx/services/ble_service.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Antes usabas pilotNameController, ahora usaremos una lista de pilotos y controladores
  List<Map<String, dynamic>> _pilots = [];
  List<TextEditingController> _pilotControllers = [];

  // Controladores para el popup de “Subir Publicación”
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _imageUrlController = TextEditingController();

  // Controlador para el popup de “Crear Piloto” (ya no se usará para crear, sino que agregaremos en la lista)
  final TextEditingController _newPilotController = TextEditingController();

  // ---------- Variables para admin (sesiones/pilotos/tiempos) ----------
  String? _selectedSessionId; // ID de la sesión elegida
  String? _selectedPilotId; // ID del piloto elegido dentro de esa sesión
  final TextEditingController _editTimeController = TextEditingController();

  // BLE
  final BleService _bleService = BleService();
  bool _isScanningBle = false;
  List<DiscoveredDevice> _discoveredDevices = [];
  final TextEditingController _bleSsidController = TextEditingController();
  final TextEditingController _blePassController = TextEditingController();
  final TextEditingController _bleDeviceIdController = TextEditingController();

  String? _role; // Para guardar el rol de la base de datos

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null) {
      print('No hay usuario autenticado');
      return;
    }
    DocumentSnapshot doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists && doc.data() != null) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

      // Manejar el campo "pilots" que puede ser un String o una Lista de Map.
      dynamic pilotsData = data['pilots'];
      List<Map<String, dynamic>> pilotsList = [];
      if (pilotsData is String) {
        // Si es un String, lo convertimos en una lista con un solo piloto.
        pilotsList.add({'id': 'default', 'name': pilotsData});
      } else if (pilotsData is List) {
        pilotsList = pilotsData.map<Map<String, dynamic>>((e) {
          if (e is Map<String, dynamic>) {
            return e;
          } else if (e is String) {
            // Si algún elemento es String, lo tratamos como nombre.
            return {'id': 'default', 'name': e};
          }
          return {};
        }).toList();
      }

      setState(() {
        _pilots = pilotsList;
        _pilotControllers = _pilots.map((pilot) {
          return TextEditingController(text: pilot['name']?.toString() ?? '');
        }).toList();
        _role = data['role']; // Guardamos el rol (Admin, trainer, user...)
      });

      // Carga de opciones de tema (no relacionado con los pilotos)
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

  // -----------------------------------------------------------------------
  // Función para actualizar la lista de pilotos del usuario
  // -----------------------------------------------------------------------
  Future<void> updatePilots(String userId) async {
    List<Map<String, dynamic>> updatedPilots = [];

    for (int i = 0; i < _pilotControllers.length; i++) {
      final pilotName = _pilotControllers[i].text.trim();
      final pilotRfid = _pilots[i]['rfid']?.toString().trim() ?? '';
      if (pilotName.isNotEmpty) {
        updatedPilots.add({
          'id': _pilots[i]['id'] ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          'name': pilotName,
          'rfid': pilotRfid,
        });
      }
    }

    // 🔹 Guardar los pilotos actualizados en el usuario
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'pilots': updatedPilots,
    });

    // 🔹 Crear o actualizar el índice RFID -> userId
    for (var p in updatedPilots) {
      if (p['rfid'] != null && p['rfid'].toString().isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('rfidIndex')
            .doc(p['rfid'])
            .set({
          'userId': userId,
          'pilotName': p['name'],
        });
      }
    }

    // 🔹 Mensaje visual de confirmación
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Pilotos actualizados'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Funciones para eliminar y editar tiempos en sesiones (sin cambios)
  // -----------------------------------------------------------------------
  Future<void> _deleteTime(
      String sessionId, String pilotId, int timeIndex) async {
    final sessionRef =
        FirebaseFirestore.instance.collection('sessions').doc(sessionId);
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

  void _showAssignPilotsToTrainerPopup() async {
    // 1. Obtener la lista de trainers
    final trainerSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'trainer')
        .get();

    // 2. Si no hay entrenadores, mostramos un aviso
    if (trainerSnapshot.docs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No hay entrenadores registrados.')),
      );
      return;
    }

    // 3. Obtener la lista de pilotos (role = user) y armar un array con sus pilots
    final usersSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'user')
        .get();

    List<Map<String, dynamic>> allPilots = [];
    for (var doc in usersSnapshot.docs) {
      final data = doc.data();
      final List<dynamic> pilotsArr = data['pilots'] ?? [];
      // El doc.id corresponde al "userId", pero cada pilot tiene su propio "id"
      // Podrías componer un ID tipo "userId_pilotId" o similar
      // Para simplicidad, guardo la info en un map
      for (var p in pilotsArr) {
        if (p is Map<String, dynamic>) {
          // p['name'] y p['id']
          allPilots.add({
            'userId': doc.id,
            'pilotId': p['id'],
            'pilotName': p['name'] ?? 'Sin nombre',
          });
        } else if (p is String) {
          // Si un pilot es string, lo adaptamos
          allPilots.add({
            'userId': doc.id,
            'pilotId': 'default',
            'pilotName': p,
          });
        }
      }
    }

    // Variables locales para la selección en el popup
    String? selectedTrainerId;
    // Pilotos seleccionados (vamos a guardar un set de IDs compuestos)
    Set<String> selectedPilotIds = {};

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Asignar Pilotos a Trainer'),
          content: StatefulBuilder(
            builder: (context, setStateSB) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Dropdown de entrenadores
                    DropdownButton<String>(
                      value: selectedTrainerId,
                      hint: Text("Seleccionar Entrenador"),
                      isExpanded: true,
                      items: trainerSnapshot.docs.map((trainerDoc) {
                        final tData = trainerDoc.data();
                        final tEmail = tData['email'] ?? trainerDoc.id;
                        return DropdownMenuItem<String>(
                          value: trainerDoc.id,
                          child: Text(tEmail),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setStateSB(() {
                          selectedTrainerId = val;
                        });
                      },
                    ),
                    SizedBox(height: 16),

                    // Lista de pilotos en Cards seleccionables
                    ...allPilots.map((pilot) {
                      // compongo un ID único
                      final combinedId =
                          "${pilot['userId']}_${pilot['pilotId']}";
                      final pName = pilot['pilotName'] ?? '---';
                      final bool isSelected =
                          selectedPilotIds.contains(combinedId);

                      return InkWell(
                        onTap: () {
                          setStateSB(() {
                            if (isSelected) {
                              selectedPilotIds.remove(combinedId);
                            } else {
                              selectedPilotIds.add(combinedId);
                            }
                          });
                        },
                        child: Card(
                          color: isSelected
                              ? const Color.fromARGB(255, 54, 133, 58)
                              : const Color.fromARGB(255, 121, 120, 120),
                          child: Padding(
                            padding: EdgeInsets.all(8.0),
                            child: ListTile(
                              title: Text(pName),
                              subtitle: Text("ID: $combinedId"),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedTrainerId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Selecciona un entrenador')),
                  );
                  return;
                }
                // Guardamos la lista en un campo "assignedPilots" en el doc del entrenador
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(selectedTrainerId)
                    .update({
                  'assignedPilots': selectedPilotIds.toList(),
                });

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Pilotos asignados correctamente')),
                );
              },
              child: Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editTime(
      String sessionId, String pilotId, int timeIndex, int newTime) async {
    final sessionRef =
        FirebaseFirestore.instance.collection('sessions').doc(sessionId);
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

  void _showEditTimeDialog(
      String sessionId, String pilotId, int timeIndex, int currentTime) {
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
        Text(
          "Seleccionar Piloto:",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        if (_selectedSessionId == null) Text("Primero selecciona una sesión"),
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
  // Popup para Subir Publicación (nueva “noticia”) (sin cambios)
  // -----------------------------------------------------------------------
  void _showPublicationPopup() {
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
  // (Opcional) Popup para Crear Piloto – ahora puedes integrarlo o eliminarlo,
  // ya que la gestión se hace en la lista de TextFields.
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
                  // Genera un email aleatorio para este piloto
                  String randomEmail =
                      "pilot_${DateTime.now().millisecondsSinceEpoch}@example.com";
                  // Genera un id para el piloto
                  String newId =
                      DateTime.now().millisecondsSinceEpoch.toString();
                  await FirebaseFirestore.instance.collection('users').add({
                    'email': randomEmail,
                    'role': 'user',
                    'pilots': [
                      {
                        'id': newId,
                        'name': pilotName,
                      }
                    ],
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
  // Popup para borrar pilotos (para admin, se podría adaptar también)
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
                // Recorremos cada documento y extraemos los pilotos
                List<Map<String, dynamic>> pilotEntries = [];
                for (var doc in docs) {
                  Map<String, dynamic> data =
                      doc.data() as Map<String, dynamic>;
                  List<dynamic> pilots = data['pilots'] ?? [];
                  for (var pilot in pilots) {
                    if (pilot is Map<String, dynamic>) {
                      pilotEntries.add({
                        'userId': doc.id,
                        'pilotId': pilot['id'],
                        'pilotName': pilot['name'],
                      });
                    }
                  }
                }
                if (pilotEntries.isEmpty) {
                  return Text("No hay pilotos para borrar.");
                }
                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: pilotEntries.length,
                  itemBuilder: (context, index) {
                    final entry = pilotEntries[index];
                    final pilotName = entry['pilotName'] ?? 'Sin nombre';
                    return Card(
                      child: ListTile(
                        title: Text(pilotName),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  title: Text('Confirmar borrado'),
                                  content: Text(
                                      '¿Estás seguro de borrar a $pilotName?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text('Cancelar'),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(
                                            context); // cierra confirmación
                                        Navigator.pop(
                                            context); // cierra popup principal
                                        await _deletePilotFromUser(
                                          entry['userId'],
                                          entry['pilotId'],
                                        );
                                      },
                                      child: Text('Borrar',
                                          style: TextStyle(color: Colors.red)),
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

  void _showBleConfigPopup() async {
    bool hasPerms = await _bleService.requestPermissions();
    if (!hasPerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Faltan permisos de Bluetooth/Ubicación')),
      );
      return;
    }

    _discoveredDevices.clear();
    _bleSsidController.text = "ALOHA_TERRAZA";
    _blePassController.text = "LuaAragorn68";
    _bleDeviceIdController.text = "esp32_bmx_1";

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: Text('Configurar ESP32 (BLE)'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                        "Paso 1: Buscar dispositivo (Recuerda reiniciar el ESP32)"),
                    SizedBox(height: 10),
                    if (_isScanningBle) CircularProgressIndicator(),
                    if (!_isScanningBle)
                      ElevatedButton(
                        onPressed: () {
                          setStateSB(() => _isScanningBle = true);
                          _bleService.startScan((device) {
                            if (!_discoveredDevices
                                .any((d) => d.id == device.id)) {
                              setStateSB(() {
                                _discoveredDevices.add(device);
                              });
                            }
                          });
                        },
                        child: Text("Escanear (30s config mode)"),
                      ),
                    ..._discoveredDevices.map((d) => ListTile(
                          title:
                              Text(d.name.isNotEmpty ? d.name : "Sin nombre"),
                          subtitle: Text(d.id),
                          onTap: () {
                            _bleService.stopScan();
                            setStateSB(() {
                              _isScanningBle = false;
                              _selectedPilotId = d
                                  .id; // Reutilizamos variable o usamos una nueva
                            });
                          },
                          trailing: _selectedPilotId == d.id
                              ? Icon(Icons.check, color: Colors.green)
                              : null,
                        )),
                    Divider(),
                    Text("Paso 2: Datos WiFi"),
                    TextField(
                        controller: _bleSsidController,
                        decoration: InputDecoration(labelText: 'SSID WiFi')),
                    TextField(
                        controller: _blePassController,
                        decoration:
                            InputDecoration(labelText: 'Password WiFi')),
                    TextField(
                        controller: _bleDeviceIdController,
                        decoration:
                            InputDecoration(labelText: 'ID Dispositivo')),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancelar')),
                ElevatedButton(
                  onPressed: _selectedPilotId == null
                      ? null
                      : () async {
                          await _bleService.sendConfig(
                            deviceAddress: _selectedPilotId!,
                            ssid: _bleSsidController.text,
                            password: _blePassController.text,
                            esp32Id: _bleDeviceIdController.text,
                          );
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Configuración enviada. El ESP32 se reiniciará.')),
                          );
                        },
                  child: Text('Enviar Config'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deletePilotFromUser(String userId, String pilotId) async {
    DocumentReference userRef =
        FirebaseFirestore.instance.collection('users').doc(userId);
    DocumentSnapshot userDoc = await userRef.get();
    if (!userDoc.exists) return;
    Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
    List<dynamic> pilots = data['pilots'] ?? [];
    List<dynamic> updatedPilots = pilots.where((p) {
      if (p is Map<String, dynamic>) {
        return p['id'] != pilotId;
      }
      return true;
    }).toList();
    await userRef.update({'pilots': updatedPilots});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Piloto borrado exitosamente'),
          backgroundColor: Colors.green),
    );
  }

  // Función para borrar piloto y limpiar datos en sesiones (sin cambios)
  Future<void> _deletePilot(String pilotId) async {
    await FirebaseFirestore.instance.collection('users').doc(pilotId).delete();

    QuerySnapshot sessionsSnapshot =
        await FirebaseFirestore.instance.collection('sessions').get();
    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (var sessionDoc in sessionsSnapshot.docs) {
      Map<String, dynamic> sessionData =
          sessionDoc.data() as Map<String, dynamic>;
      List<dynamic> pilots = sessionData['pilots'] ?? [];
      List<dynamic> updatedPilots =
          pilots.where((p) => (p['id'] as String) != pilotId).toList();
      if (updatedPilots.length != pilots.length) {
        batch.update(sessionDoc.reference, {'pilots': updatedPilots});
      }
    }
    await batch.commit();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Piloto borrado exitosamente'),
          backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final bool isAdmin = user?.email == '1@1.1' ||
        user?.email == 'admin@admin.com' ||
        _role == 'Admin';

    return Scaffold(
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            children: [
              // --- Fila superior con lista de pilotos, botón de cerrar sesión y menú de ajustes para admin ---
              Row(
                children: [
                  // Aquí mostramos una columna con un TextField para cada piloto
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._pilotControllers.asMap().entries.map((entry) {
                          int index = entry.key;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: entry.value,
                                      decoration: InputDecoration(
                                        labelText: 'Piloto ${index + 1}',
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete),
                                    onPressed: () {
                                      setState(() {
                                        _pilotControllers.removeAt(index);
                                        _pilots.removeAt(index);
                                      });
                                    },
                                  )
                                ],
                              ),
                              // 👇 Nuevo campo para RFID
                              TextField(
                                decoration: InputDecoration(
                                  labelText:
                                      'Etiqueta RFID del piloto ${index + 1}',
                                ),
                                onChanged: (val) {
                                  _pilots[index]['rfid'] = val.trim();
                                },
                              ),
                              SizedBox(height: 8),
                            ],
                          );
                        }).toList(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              String newId = DateTime.now()
                                  .millisecondsSinceEpoch
                                  .toString();
                              _pilots.add({'id': newId, 'name': ''});
                              _pilotControllers.add(TextEditingController());
                            });
                          },
                          child: Text("Añadir Piloto"),
                        ),
                      ],
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
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  ),
                  SizedBox(width: 20),
                  if (isAdmin)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.settings,
                          color: const Color.fromARGB(255, 70, 69, 69)),
                      onSelected: (value) {
                        if (value == 'subir') {
                          _showPublicationPopup();
                        } else if (value == 'crear') {
                          _showCreatePilotPopup();
                        } else if (value == 'borrar') {
                          _showDeletePilotsPopup();
                        } else if (value == 'asignar') {
                          _showAssignPilotsToTrainerPopup();
                        } else if (value == 'ble') {
                          _showBleConfigPopup();
                        }
                      },
                      itemBuilder: (BuildContext context) =>
                          <PopupMenuEntry<String>>[
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
                        PopupMenuItem<String>(
                          value: 'asignar',
                          child: Text('Asignar Pilotos a Trainer'),
                        ),
                        PopupMenuItem<String>(
                          value: 'ble',
                          enabled: !kIsWeb,
                          child: Text(kIsWeb
                              ? 'Configurar ESP32 (Solo en Móvil)'
                              : 'Configurar ESP32 (BLE)'),
                        ),
                      ],
                    ),
                ],
              ),
              SizedBox(height: 10),
              // Botón para guardar la lista de pilotos (actualiza el documento del usuario)
              ElevatedButton(
                onPressed: user != null ? () => updatePilots(user.uid) : null,
                child: Text('Guardar Pilotos'),
              ),
              SizedBox(height: 20),
              // Sección para cambiar tema (oscuro/claro) y paleta de colores
              Consumer<ThemeProvider>(
                builder: (context, themeProvider, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Modo Oscuro / Claro",
                          style: TextStyle(fontSize: 16)),
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
                                    'palette':
                                        palette.toString().split('.').last,
                                  });
                                }
                              },
                              child: Container(
                                margin: EdgeInsets.all(8.0),
                                width: 60,
                                decoration: BoxDecoration(
                                  color: themeProvider
                                      .getSampleColorForPalette(palette),
                                  border: themeProvider.palette == palette
                                      ? Border.all(
                                          width: 3, color: Colors.white)
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
