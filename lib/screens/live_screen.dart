import 'dart:async';
import 'dart:math'; // Para generar números aleatorios
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:getready_bmx/providers/auth_provider.dart';
// import 'package:flutter/foundation.dart';

/// Convierte milisegundos (int o String) a un String con segundos y 3 decimales.
/// Ej: 4590 ms -> "4.590", 34578 ms -> "34.578"
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

class LiveScreen extends StatefulWidget {
  @override
  _LiveScreenState createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final TextEditingController locationController = TextEditingController();
  final TextEditingController distanceController = TextEditingController();

  // Variables para la sesión
  DateTime selectedDate = DateTime.now();
  String? selectedLocation;
  List<Map<String, dynamic>> locations = [];

  List<Map<String, dynamic>> selectedPilots = [];
  String? currentSessionId;
  int? selectedDistance;

  // ----------------- BLE VARIABLES -----------------
  final FlutterReactiveBle flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? connectionSubscription;
  StreamSubscription<List<int>>? dataSubscription;

  // UUIDs
  final Uuid serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
  final Uuid characteristicUuid =
      Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");

  // Estado BLE y datos
  bool esp32Connected = false;
  String receivedData = "Esperando datos...";
  String? connectedDeviceId; // Se guarda el deviceId conectado
  String? waitingPilotId; // Piloto seleccionado para recibir tiempos
  // ---------------------------------------------------

  Timer? reconnectTimer;
  bool debugActive = true; // Variable para activar/desactivar mensajes de debug
  String?
      expandedPilotName; // Para rastrear qué piloto tiene los tiempos expandidos

  @override
  void initState() {
    super.initState();
    fetchLocations();
    requestPermissions().then((granted) {
      if (granted) {
        showDebugMessage("✅ Permisos concedidos");
        scanAndConnect();
        // Cada 15s se reintenta la conexión si no está conectada
        reconnectTimer = Timer.periodic(Duration(seconds: 15), (timer) {
          if (!esp32Connected) {
            showDebugMessage("🔄 Reintentando conexión BLE...");
            scanAndConnect();
          }
        });
      }
    });
  }

  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();
    final allGranted =
        statuses.values.every((status) => status == PermissionStatus.granted);
    return allGranted;
  }

  void scanAndConnect() {
    showDebugMessage("🔍 Iniciando escaneo BLE...");
    scanSubscription = flutterReactiveBle.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      showDebugMessage(
          "📡 Dispositivo encontrado: '${device.name}' - ${device.id}");
      if (device.name.contains("GetReady")) {
        showDebugMessage("✅ Dispositivo compatible encontrado");
        scanSubscription?.cancel();
        connectToDevice(device);
      }
    }, onError: (error) {
      showDebugMessage("❌ Error al escanear: $error");
    });
  }

  void connectToDevice(DiscoveredDevice device) {
    showDebugMessage(
        "🔗 Intentando conectar con: '${device.name}' - ${device.id}");
    connectionSubscription = flutterReactiveBle
        .connectToDevice(
      id: device.id,
      servicesWithCharacteristicsToDiscover: {
        serviceUuid: [characteristicUuid]
      },
      connectionTimeout: Duration(seconds: 10),
    )
        .listen((connectionState) {
      showDebugMessage(
          "🔗 Estado de conexión: ${connectionState.connectionState}");
      if (connectionState.connectionState == DeviceConnectionState.connecting) {
        showDebugMessage("⌛ Conectando...");
      }
      if (connectionState.connectionState == DeviceConnectionState.connected) {
        setState(() {
          esp32Connected = true;
          connectedDeviceId = device.id;
        });
        showDebugMessage("✅ Conexión exitosa con ${device.id}");
        discoverServices(device.id);
      } else if (connectionState.connectionState ==
          DeviceConnectionState.disconnected) {
        setState(() {
          esp32Connected = false;
        });
        showDebugMessage("🔌 Desconectado");
      }
    }, onError: (error) {
      showDebugMessage("❌ Error de conexión: $error");
    });
  }

  void discoverServices(String deviceId) async {
    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
        deviceId: deviceId,
      );
      showDebugMessage(
          "🔍 Suscribiéndose a notify en ${characteristic.characteristicId}");
      await Future.delayed(Duration(seconds: 2));
      // Lectura manual inicial para forzar el descubrimiento
      try {
        List<int> testValue =
            await flutterReactiveBle.readCharacteristic(characteristic);
        showDebugMessage(
            "📤 Lectura manual inicial: ${String.fromCharCodes(testValue)}");
      } catch (e) {
        showDebugMessage("⚠️ Error en lectura manual: $e");
      }
      dataSubscription = flutterReactiveBle
          .subscribeToCharacteristic(characteristic)
          .listen((value) {
        if (value.isNotEmpty) {
          String receivedString = String.fromCharCodes(value);
          showDebugMessage("📩 Notificación recibida: $receivedString");
          String numericString = receivedString.replaceAll(RegExp(r'\D'), '');
          showDebugMessage("🔢 Valor numérico extraído: $numericString");
          setState(() {
            receivedData = numericString;
          });
          if (waitingPilotId != null && numericString.isNotEmpty) {
            int time = int.parse(numericString);
            savePilotTime(waitingPilotId!, time);
            showDebugMessage("📤 Tiempo guardado: $time ms");
          }
        } else {
          showDebugMessage("⚠️ Valor recibido vacío");
        }
      }, onError: (error) {
        showDebugMessage("⚠️ Error en la suscripción: $error");
      }, onDone: () {
        showDebugMessage("⚠️ La suscripción a notify se ha cerrado");
      });
      showDebugMessage("✅ Suscripción a notify activada");
    } catch (e) {
      showDebugMessage("⚠️ Error al descubrir servicios: $e");
    }
  }

  void disconnectDevice() async {
    if (esp32Connected && connectedDeviceId != null) {
      dataSubscription?.cancel();
      connectionSubscription?.cancel();
      flutterReactiveBle.clearGattCache(connectedDeviceId!);
      setState(() {
        esp32Connected = false;
        receivedData = "Esperando datos...";
        connectedDeviceId = null;
      });
      print("🔌 Dispositivo desconectado");
    }
  }

  bool get isAdmin {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    return authProvider.user?.email == '1@1.1';
  }

  void showDebugMessage(String message) {
    if (!debugActive) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: Duration(seconds: 2)),
    );
  }

  // ----------------------------------------------------------------
  // Carga la lista de ubicaciones (locations) desde Firestore
  // ----------------------------------------------------------------
  void fetchLocations() async {
    var snapshot =
        await FirebaseFirestore.instance.collection('locations').get();
    setState(() {
      locations = snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'distance': data['distance'],
        };
      }).toList();
    });
  }

  // ----------------------------------------------------------------
  // Dialog para crear ubicación
  // ----------------------------------------------------------------
  /* void _showCreateLocationDialog() {
    locationController.clear();
    distanceController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Crear Ubicación"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: locationController,
                decoration: InputDecoration(labelText: 'Ubicación'),
              ),
              TextField(
                controller: distanceController,
                decoration: InputDecoration(labelText: 'Distancia (m)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: createLocation,
              child: Text("Guardar"),
            )
          ],
        );
      },
    );
  } */

  void createLocation() async {
    String location = locationController.text.trim();
    String distance = distanceController.text.trim();
    if (location.isNotEmpty && distance.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('locations')
          .doc(location)
          .set({
        'distance': int.parse(distance),
      });
      fetchLocations();
      Navigator.pop(context);
    }
  }

  // ----------------------------------------------------------------
  // Dialog para crear sesión
  // ----------------------------------------------------------------
  /* void _showCreateSessionPopup() {
    DateTime sessionDate = selectedDate;
    String? sessionLocation = selectedLocation;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Crear Sesión"),
          content: StatefulBuilder(
            builder: (context, setStateSB) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title:
                        Text('Fecha: ${sessionDate.toString().split(' ')[0]}'),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: sessionDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setStateSB(() {
                          sessionDate = picked;
                        });
                      }
                    },
                  ),
                  DropdownButton<String>(
                    value: sessionLocation,
                    hint: Text("Seleccionar Ubicación"),
                    items: locations.map((loc) {
                      return DropdownMenuItem<String>(
                        value: loc['id'],
                        child: Text("${loc['id']}, ${loc['distance']} m"),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setStateSB(() {
                        sessionLocation = newValue;
                      });
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (sessionLocation == null) return;
                // Buscar la ubicación seleccionada en el array
                int distance = 0;
                final selectedLoc = locations.firstWhere(
                    (loc) => loc['id'] == sessionLocation,
                    orElse: () => {});
                if (selectedLoc.isNotEmpty) {
                  distance = selectedLoc['distance'] ?? 0;
                }
                DocumentReference sessionRef = await FirebaseFirestore.instance
                    .collection('sessions')
                    .add({
                  'location': sessionLocation,
                  'distance': distance,
                  'date': sessionDate,
                  'pilots': selectedPilots,
                });
                setState(() {
                  currentSessionId = sessionRef.id;
                  selectedDate = sessionDate;
                  selectedLocation = sessionLocation;
                  selectedDistance = distance;
                });
                Navigator.pop(context);
              },
              child: Text("Crear Sesión"),
            ),
          ],
        );
      },
    );
  } */

  // ----------------------------------------------------------------
  // Dialog para seleccionar pilotos
  // ----------------------------------------------------------------
  void showPilotSelectionPopup() async {
    // Si ya hay una sesión, cargamos los pilotos seleccionados previamente
    if (currentSessionId != null) {
      DocumentSnapshot sessionDoc = await FirebaseFirestore.instance
          .collection('sessions')
          .doc(currentSessionId)
          .get();
      List<dynamic> currentPilots =
          (sessionDoc.data() as Map<String, dynamic>?)?['pilots'] ?? [];
      selectedPilots = List<Map<String, dynamic>>.from(currentPilots);
    }
    // Creamos un mapa para tener los pilotos ya seleccionados (clave = id único)
    Map<String, Map<String, dynamic>> currentPilotsMap = {
      for (var p in selectedPilots) p['id']: p
    };

    // Obtenemos todos los documentos de usuarios
    var snapshot = await FirebaseFirestore.instance.collection('users').get();
    // Copia local de los pilotos seleccionados en la sesión actual
    List<Map<String, dynamic>> pilots =
        List<Map<String, dynamic>>.from(selectedPilots);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Seleccionar Pilotos"),
          content: StatefulBuilder(
            builder: (context, setStateSB) {
              return Container(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: snapshot.docs.expand((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    // Obtener la lista de pilotos del usuario (ahora es una lista de maps)
                    final List<dynamic> userPilots = data['pilots'] ?? [];
                    return userPilots.map((pilotData) {
                      // pilotData es un Map, extraemos el nombre y el id original
                      final pilotMap = pilotData as Map<String, dynamic>;
                      final String pilotName =
                          pilotMap['name']?.toString() ?? 'Sin nombre';
                      // Creamos un id único combinando el id del usuario y el id del piloto
                      final String pilotId = "${doc.id}_${pilotMap['id']}";
                      bool isSelected = currentPilotsMap.containsKey(pilotId);

                      return InkWell(
                        onTap: () {
                          setStateSB(() {
                            if (isSelected) {
                              pilots.removeWhere((p) => p['id'] == pilotId);
                              currentPilotsMap.remove(pilotId);
                            } else {
                              pilots.add({
                                'id': pilotId,
                                'name': pilotName,
                                'times': [],
                                'active': true,
                              });
                              currentPilotsMap[pilotId] = pilots.last;
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
                              title: Text(pilotName),
                              subtitle: isSelected
                                  ? Text("Esperando tiempo...")
                                  : null,
                            ),
                          ),
                        ),
                      );
                    }).toList();
                  }).toList(),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  selectedPilots = pilots;
                });
                FirebaseFirestore.instance
                    .collection('sessions')
                    .doc(currentSessionId)
                    .update({'pilots': pilots});
                Navigator.pop(context);
              },
              child: Text("Iniciar"),
            ),
          ],
        );
      },
    );
  }

  // ----------------------------------------------------------------
  // Guarda el tiempo en milisegundos para un piloto en la sesión actual
  // ----------------------------------------------------------------
  void savePilotTime(String pilotId, int time) async {
    if (currentSessionId == null) return;
    DocumentReference sessionRef =
        FirebaseFirestore.instance.collection('sessions').doc(currentSessionId);
    DocumentSnapshot sessionSnapshot = await sessionRef.get();
    if (!sessionSnapshot.exists) return;

    Map<String, dynamic> sessionData =
        sessionSnapshot.data()! as Map<String, dynamic>;
    String pilotName = "";
    List<dynamic> updatedPilots = sessionData['pilots'].map((pilot) {
      final pilotMap = pilot as Map<String, dynamic>;
      if (pilotMap['id'] == pilotId) {
        pilotMap['times'] = (pilotMap['times'] ?? [])..add(time);
        pilotName = pilotMap['name'];
      }
      return pilotMap;
    }).toList();
    await sessionRef.update({'pilots': updatedPilots});

    if (pilotName.isNotEmpty && sessionData['location'] != null) {
      _updateLeaderboard(sessionData['location'], pilotName, time);
    }
  }

  Future<void> _updateLeaderboard(
      String location, String pilotName, int time) async {
    final String docId =
        location.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
    final leaderboardRef =
        FirebaseFirestore.instance.collection('leaderboards').doc(docId);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(leaderboardRef);

      if (!snapshot.exists) {
        transaction.set(leaderboardRef, {
          'location': location,
          'records': [
            {'name': pilotName, 'time': time}
          ]
        });
        return;
      }

      Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
      List<dynamic> records = List.from(data['records'] ?? []);

      int existingIndex = records.indexWhere((r) => r['name'] == pilotName);

      if (existingIndex != -1) {
        if (time < records[existingIndex]['time']) {
          records[existingIndex]['time'] = time;
        } else {
          return; // No es mejor tiempo
        }
      } else {
        records.add({'name': pilotName, 'time': time});
      }

      records.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
      if (records.length > 20) {
        records = records.sublist(0, 20);
      }

      transaction.update(leaderboardRef, {'records': records});
    });
  }

  /// Inserta 10 tiempos aleatorios entre 1500 ms y 3000 ms para cada piloto activo
  /// de la sesión actual.
  void insertRandomTimes() async {
    if (currentSessionId == null) return;
    final sessionRef =
        FirebaseFirestore.instance.collection('sessions').doc(currentSessionId);
    final sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) return;

    final sessionData = sessionSnap.data() as Map<String, dynamic>;
    List<dynamic> pilots = sessionData['pilots'] ?? [];

    final random = Random();

    for (var p in pilots) {
      final pilot = p as Map<String, dynamic>;
      if (pilot['active'] == true) {
        pilot['times'] ??= [];
        for (int i = 0; i < 10; i++) {
          // random.nextInt(1501) genera [0..1500], + 1500 => [1500..3000]
          pilot['times'].add(random.nextInt(1501) + 1500);
        }
      }
    }

    await sessionRef.update({'pilots': pilots});

    // Actualizar leaderboards para cada piloto
    if (sessionData['location'] != null) {
      for (var p in pilots) {
        final pilot = p as Map<String, dynamic>;
        if (pilot['active'] == true &&
            pilot['times'] != null &&
            pilot['times'].isNotEmpty) {
          int bestTime = (pilot['times'] as List).map((e) {
            if (e is num) return e.toInt();
            if (e is String) return int.tryParse(e) ?? 999999;
            return 999999;
          }).reduce((a, b) => a < b ? a : b);
          _updateLeaderboard(sessionData['location'], pilot['name'], bestTime);
        }
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text("Tiempos aleatorios insertados exitosamente"),
          duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primary = themeProvider.primaryColor;
    final authProvider = Provider.of<AuthProvider>(context);
    final bool isAdmin = (authProvider.user?.email == '1@1.1' ||
        authProvider.user?.email == 'admin@admin.com');

    return Scaffold(
      extendBody: true,
      /* appBar: AppBar(
        title: Text("LIVE SESSION",
            style: GoogleFonts.orbitron(
                fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (isAdmin)
            IconButton(
              icon: Icon(
                  debugActive ? Icons.bug_report : Icons.bug_report_outlined,
                  color: debugActive ? Colors.orange : null),
              onPressed: () {
                setState(() => debugActive = !debugActive);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          "Debug ${debugActive ? 'activado' : 'desactivado'}")),
                );
              },
            ),
        ],
      ), */
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            _buildControlCard(primary, isAdmin),

            const SizedBox(height: 10),

            if (currentSessionId != null) ...[
              Expanded(
                child: _buildPilotsMonitoring(currentSessionId!),
              ),
            ] else ...[
              const Expanded(
                child: Center(
                  child: Text("Selecciona una sesión para comenzar",
                      style: TextStyle(
                          color: Colors.grey, fontStyle: FontStyle.italic)),
                ),
              ),
            ],
            const SizedBox(height: 80), // Space for floating nav
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(Color primary, bool isAdmin) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          _buildSessionSelector(isAdmin),
        ],
      ),
    );
  }

  /* Widget _buildStatusIndicator(
      {required IconData icon,
      required Color color,
      required String label,
      VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label,
              style: GoogleFonts.orbitron(
                  fontSize: 8, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  } */

  Widget _buildSessionSelector(bool isAdmin) {
    DateTime now = DateTime.now();
    DateTime yesterday = now.subtract(const Duration(days: 1));
    DateTime yesterdayStart =
        DateTime(yesterday.year, yesterday.month, yesterday.day);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sessions')
          .where('date', isGreaterThanOrEqualTo: yesterdayStart)
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        var docs = snapshot.data!.docs;
        if (docs.isEmpty) return const Text("No hay sesiones");

        // Auto-seleccionar sesión activa o la única disponible
        if (currentSessionId == null) {
          String? toSelect;
          Map<String, dynamic>? toSelectData;

          // Buscar la sesión activa
          for (var doc in docs) {
            var data = doc.data() as Map<String, dynamic>;
            if (data['active'] == true) {
              toSelect = doc.id;
              toSelectData = data;
              break;
            }
          }

          // Si no hay activa pero solo hay una sesión, seleccionamos esa
          if (toSelect == null && docs.length == 1) {
            toSelect = docs.first.id;
            toSelectData = docs.first.data() as Map<String, dynamic>;
          }

          if (toSelect != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && currentSessionId == null) {
                if (isAdmin) {
                  _activateSession(toSelect!);
                } else {
                  _locallySelectSession(toSelect!, toSelectData!);
                }
              }
            });
          }
        }

        final primary = Provider.of<ThemeProvider>(context).primaryColor;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            gradient:
                LinearGradient(colors: [primary.withOpacity(0.8), primary]),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentSessionId,
              hint: Text("SELECCIONAR SESIÓN",
                  style: GoogleFonts.orbitron(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              isExpanded: true,
              dropdownColor: primary,
              iconEnabledColor: Colors.white,
              items: docs.map((doc) {
                var data = doc.data() as Map<String, dynamic>;
                DateTime date = (data['date'] as Timestamp).toDate();
                return DropdownMenuItem<String>(
                  value: doc.id,
                  child: Text(
                      "${data['location'].toString().toUpperCase()} - ${date.toString().split(' ')[0]}",
                      style: GoogleFonts.orbitron(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                );
              }).toList(),
              onChanged: (val) async {
                if (val != null) {
                  if (isAdmin) {
                    _activateSession(val);
                  } else {
                    var doc = docs.firstWhere((d) => d.id == val);
                    _locallySelectSession(
                        val, doc.data() as Map<String, dynamic>);
                  }
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _locallySelectSession(String sessionId, Map<String, dynamic> data) {
    setState(() {
      currentSessionId = sessionId;
      selectedLocation = data['location'];
      selectedDistance = data['distance'];
      selectedDate = (data['date'] as Timestamp).toDate();
    });
  }

  Future<void> _activateSession(String sessionId) async {
    FirebaseFirestore db = FirebaseFirestore.instance;
    QuerySnapshot sessions = await db.collection('sessions').get();
    WriteBatch batch = db.batch();
    for (var doc in sessions.docs) {
      batch.update(doc.reference, {'active': doc.id == sessionId});
    }
    await batch.commit();

    DocumentSnapshot doc = await db.collection('sessions').doc(sessionId).get();
    if (doc.exists) {
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      setState(() {
        currentSessionId = sessionId;
        selectedLocation = data['location'];
        selectedDistance = data['distance'];
        selectedDate = (data['date'] as Timestamp).toDate();
      });
    }
  }

  /* Widget _buildSessionInfoCard(Color primary, bool isAdmin) {
    if (!isAdmin) {
      // Logic for fetching active session for non-admin already exists?
      // Need a StreamBuilder here for the user to see the REAL active session.
      return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('sessions')
            .where('active', isEqualTo: true)
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const SizedBox.shrink();
          }
          var data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
          return _infoCardContent(data['location'], data['distance'],
              (data['date'] as Timestamp).toDate(), primary);
        },
      );
    }
    return _infoCardContent(selectedLocation ?? "---", selectedDistance ?? 0,
        selectedDate, primary);
  }

  Widget _infoCardContent(String loc, int dist, DateTime date, Color primary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary.withOpacity(0.8), primary]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: primary.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Text(loc.toUpperCase(),
              style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
          const SizedBox(height: 4),
          Text("${dist}m • ${date.toString().split(' ')[0]}",
              style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10)),
        ],
      ),
    );
  } */

  Widget _buildPilotsMonitoring(String sessionId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sessions')
          .doc(sessionId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists)
          return const Center(child: CircularProgressIndicator());
        var data = snapshot.data!.data() as Map<String, dynamic>;

        List<Map<String, dynamic>> activePilots =
            _getGroupedPilots(data['pilots'] ?? []);

        return ListView.builder(
          itemCount: activePilots.length,
          itemBuilder: (context, idx) {
            final p = activePilots[idx];
            final bool isWaiting = p['id'] == waitingPilotId;
            return _buildPilotLiveCard(p, isWaiting);
          },
        );
      },
    );
  }

  List<Map<String, dynamic>> _getGroupedPilots(List<dynamic> allPilots) {
    Map<String, Map<String, dynamic>> grouped = {};
    for (var p in allPilots) {
      if (p == null) continue;
      final pilotMap = p as Map<String, dynamic>;

      String name = pilotMap['name'] ?? 'Sin nombre';
      if (grouped.containsKey(name)) {
        List<dynamic> existingTimes = List.from(grouped[name]!['times'] ?? []);
        List<dynamic> newTimes = List.from(pilotMap['times'] ?? []);
        existingTimes.addAll(newTimes);
        grouped[name]!['times'] = existingTimes;

        if (grouped[name]!['id'] != null &&
            (grouped[name]!['id'] as String).startsWith("auto_") &&
            pilotMap['id'] != null &&
            !(pilotMap['id'] as String).startsWith("auto_")) {
          grouped[name]!['id'] = pilotMap['id'];
        }
      } else {
        grouped[name] = Map<String, dynamic>.from(pilotMap);
        grouped[name]!['id'] ??= 'no_id_${name}';
      }
    }
    var list = grouped.values.toList();
    list.sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
    return list;
  }

  Widget _buildPilotLiveCard(Map<String, dynamic> pilot, bool isWaiting) {
    final primary = Theme.of(context).primaryColor;
    final List<dynamic> times = pilot['times'] ?? [];
    final lastTime = times.isNotEmpty ? formatMs(times.last) : "---";

    final bool isExpanded = pilot['name'] == expandedPilotName;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color:
            isWaiting ? primary.withOpacity(0.1) : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isWaiting ? primary : Colors.transparent, width: 2),
      ),
      child: Column(
        children: [
          ListTile(
            onTap: () {
              setState(() {
                if (expandedPilotName == pilot['name']) {
                  expandedPilotName = null;
                } else {
                  expandedPilotName = pilot['name'];
                }
              });
            },
            title: Text(pilot['name'],
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("Último: $lastTime s • Total: ${times.length}",
                style: const TextStyle(fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isWaiting)
                  const Icon(Icons.sync, color: Colors.green)
                else
                  const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Icon(isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down),
              ],
            ),
          ),
          if (isExpanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(color: Colors.white24, height: 20),
                  Text(
                    "HISTORIAL DE TIEMPOS:",
                    style: GoogleFonts.orbitron(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: primary.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: times.map<Widget>((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: primary.withOpacity(0.5)),
                        ),
                        child: Text(
                          "${formatMs(t)}s",
                          style: GoogleFonts.orbitron(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color:
                                Colors.white, // Forzado blanco para visibilidad
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (times.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        "Sin tiempos registrados aún",
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontStyle: FontStyle.italic,
                            fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /* void _showConfirmRandomTimes() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("TIEMPOS ALEATORIOS",
            style: GoogleFonts.orbitron(
                fontSize: 14, fontWeight: FontWeight.bold)),
        content: const Text(
            "¿Generar 10 tiempos falsos para todos los pilotos activos?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("CANCELAR")),
          ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                insertRandomTimes();
              },
              child: const Text("GENERAR")),
        ],
      ),
    );
  } */

  /* void _showQuickSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("SESIÓN RÁPIDA",
                style: GoogleFonts.orbitron(fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: const Text("Crear Nueva Ubicación"),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateLocationDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_to_photos_outlined),
              title: const Text("Crear Nueva Sesión"),
              onTap: () {
                Navigator.pop(ctx);
                _showCreateSessionPopup();
              },
            ),
          ],
        ),
      ),
    );
  } */

  @override
  void dispose() {
    scanSubscription?.cancel();
    connectionSubscription?.cancel();
    dataSubscription?.cancel();
    reconnectTimer?.cancel();
    super.dispose();
  }
}
