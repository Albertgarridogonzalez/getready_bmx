import 'dart:async';
import 'dart:math'; // Para generar números aleatorios
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:getready_bmx/providers/theme_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:getready_bmx/providers/auth_provider.dart';

/// Convierte milisegundos (int) a un String con segundos y 3 decimales.
/// Ej: 4590 ms -> "4.590", 34578 ms -> "34.578"
String formatMs(int ms) {
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
  void _showCreateLocationDialog() {
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
  }

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
  void _showCreateSessionPopup() {
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
  }

  // ----------------------------------------------------------------
  // Dialog para seleccionar pilotos
  // ----------------------------------------------------------------
  void showPilotSelectionPopup() async {
    if (currentSessionId != null) {
      DocumentSnapshot sessionDoc = await FirebaseFirestore.instance
          .collection('sessions')
          .doc(currentSessionId)
          .get();
      List<dynamic> currentPilots =
          (sessionDoc.data() as Map<String, dynamic>?)?['pilots'] ?? [];
      selectedPilots = List<Map<String, dynamic>>.from(currentPilots);
    }
    Map<String, Map<String, dynamic>> currentPilotsMap = {
      for (var p in selectedPilots) p['id']: p
    };
    var snapshot = await FirebaseFirestore.instance.collection('users').get();
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
                  children: snapshot.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    // Si no existe pilotName, mostrar un nombre genérico
                    final String name = data['pilotName'] ?? 'Sin nombre';
                    bool isSelected =
                        (currentPilotsMap[doc.id]?['active'] ?? false) as bool;
                    return InkWell(
                      onTap: () {
                        setStateSB(() {
                          if (currentPilotsMap.containsKey(doc.id)) {
                            int index =
                                pilots.indexWhere((p) => p['id'] == doc.id);
                            if (index != -1) {
                              pilots[index]['active'] =
                                  !(pilots[index]['active'] ?? false);
                              currentPilotsMap[doc.id]!['active'] =
                                  pilots[index]['active'];
                            }
                          } else {
                            pilots.add({
                              'id': doc.id,
                              'name': name,
                              'times': [],
                              'active': true,
                            });
                            currentPilotsMap[doc.id] = pilots.last;
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
                            title: Text(name),
                            subtitle:
                                isSelected ? Text("Esperando tiempo...") : null,
                          ),
                        ),
                      ),
                    );
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
    List<dynamic> updatedPilots = sessionData['pilots'].map((pilot) {
      final pilotMap = pilot as Map<String, dynamic>;
      if (pilotMap['id'] == pilotId) {
        pilotMap['times'] = (pilotMap['times'] ?? [])..add(time);
      }
      return pilotMap;
    }).toList();
    sessionRef.update({'pilots': updatedPilots});
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text("Tiempos aleatorios insertados exitosamente"),
          duration: Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final bool isAdmin = authProvider.user?.email == '1@1.1';

    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              children: [
                // ----------------------------------
                // SECCIÓN PARA ADMIN
                // ----------------------------------
                if (isAdmin) ...[
                  // Card que contiene los íconos superiores y el botón “Añadir Riders”
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          // Fila con íconos BLE, debug, random times, y menú de ajustes
                          Row(
                            children: [
                              // Ícono de estado del ESP32 (arriba-izquierda)
                              GestureDetector(
                                onTap: () {
                                  if (!esp32Connected) {
                                    scanAndConnect();
                                  }
                                },
                                child: Icon(
                                  esp32Connected
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: esp32Connected
                                      ? Colors.green
                                      : Colors.red,
                                  size: 30,
                                ),
                              ),
                              SizedBox(width: 20),
                              // Ícono para activar/desactivar modo debug
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    debugActive = !debugActive;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "Debug ${debugActive ? 'activado' : 'desactivado'}",
                                      ),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: Icon(
                                  Icons.bug_report,
                                  color:
                                      debugActive ? Colors.orange : Colors.grey,
                                  size: 30,
                                ),
                              ),
                              SizedBox(width: 20),
                              // Ícono para insertar 10 tiempos aleatorios
                              GestureDetector(
                                onTap: () {
                                  // Popup de confirmación
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title:
                                          Text("Insertar tiempos aleatorios"),
                                      content: Text(
                                          "¿Deseas insertar 10 tiempos aleatorios (1.5s a 3.0s) a cada piloto activo de esta sesión?"),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: Text("Cancelar"),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(ctx);
                                            insertRandomTimes();
                                          },
                                          child: Text("Aceptar"),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                                child: Icon(
                                  Icons.hourglass_full_rounded,
                                  color: Colors.purpleAccent,
                                  size: 30,
                                ),
                              ),
                              Spacer(),
                              // Ícono de ajustes (popup menu) con “Crear Ubicación” y “Crear Sesión”
                              PopupMenuButton<String>(
                                icon: Icon(Icons.settings),
                                onSelected: (value) {
                                  if (value == 'ubicacion') {
                                    _showCreateLocationDialog();
                                  } else if (value == 'sesion') {
                                    _showCreateSessionPopup();
                                  }
                                },
                                itemBuilder: (BuildContext context) =>
                                    <PopupMenuEntry<String>>[
                                  PopupMenuItem<String>(
                                    value: 'ubicacion',
                                    child: Text('Crear Ubicación'),
                                  ),
                                  PopupMenuItem<String>(
                                    value: 'sesion',
                                    child: Text('Crear Sesión'),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          SizedBox(height: 16),

                          // Dropdown de selección de sesión
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('sessions')
                                .orderBy('date', descending: true)
                                .limit(5)
                                .snapshots(), // Escuchar TODOS los cambios en sesiones
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return Center(
                                    child: CircularProgressIndicator());
                              }

                              var docs = snapshot.data!.docs;
                              if (docs.isEmpty) {
                                return Text("No hay sesiones disponibles.");
                              }

                              return DropdownButton<String>(
                                value: currentSessionId,
                                hint: Text("Seleccionar sesión"),
                                isExpanded: true,
                                items: docs.map((doc) {
                                  var data = doc.data() as Map<String, dynamic>;
                                  DateTime sessionDate =
                                      data['date'] is Timestamp
                                          ? (data['date'] as Timestamp).toDate()
                                          : data['date'];
                                  String displayText =
                                      "${data['location']}, ${data['distance']} m, ${sessionDate.toString().split(' ')[0]}";
                                  return DropdownMenuItem<String>(
                                    value: doc.id,
                                    child: Text(displayText),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) async {
                                  if (newValue != null) {
                                    FirebaseFirestore db =
                                        FirebaseFirestore.instance;

                                    // 🔄 Obtener todas las sesiones
                                    QuerySnapshot sessionSnapshot =
                                        await db.collection('sessions').get();

                                    WriteBatch batch = db.batch();

                                    // Recorrer todas las sesiones y poner `active: false` excepto la seleccionada
                                    for (var doc in sessionSnapshot.docs) {
                                      batch.update(doc.reference,
                                          {'active': doc.id == newValue});
                                    }

                                    // Ejecutar la actualización en Firestore
                                    await batch.commit();

                                    // 🔄 Obtener la sesión activa para actualizar la UI
                                    DocumentSnapshot sessionDoc = await db
                                        .collection('sessions')
                                        .doc(newValue)
                                        .get();
                                    if (sessionDoc.exists) {
                                      Map<String, dynamic> sessionData =
                                          sessionDoc.data()
                                              as Map<String, dynamic>;
                                      DateTime docDate = sessionData['date']
                                              is Timestamp
                                          ? (sessionData['date'] as Timestamp)
                                              .toDate()
                                          : sessionData['date'];

                                      setState(() {
                                        currentSessionId = newValue;
                                        selectedLocation =
                                            sessionData['location'];
                                        selectedDistance =
                                            sessionData['distance'];
                                        selectedDate = docDate;
                                      });
                                    }

                                    // 🔄 Forzar actualización en Web
                                    await Future.delayed(
                                        Duration(milliseconds: 200));
                                    setState(() {});
                                  }
                                },
                              );
                            },
                          ),

                          // Si hay sesión seleccionada, botón de “Añadir Riders”
                          if (currentSessionId != null) ...[
                            SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: showPilotSelectionPopup,
                              child: Text("Añadir Riders"),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Muestra info de la sesión seleccionada (si existe)
                  if (currentSessionId != null) ...[
                    SizedBox(height: 20),
                    Center(
                      child: Text(
                        "$selectedLocation, ${selectedDistance ?? 0} m, ${selectedDate.toString().split(' ')[0]}",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(height: 10),
                    // Lista de pilotos activos
                    Expanded(
                      child: StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('sessions')
                            .doc(currentSessionId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return Center(child: CircularProgressIndicator());
                          }
                          var data =
                              snapshot.data!.data()! as Map<String, dynamic>;
                          List<dynamic> pilots = data['pilots'] ?? [];
                          // Filtra solo los pilotos activos
                          List<dynamic> activePilots = pilots.where((p) {
                            return ((p as Map<String, dynamic>)['active'] ??
                                false) as bool;
                          }).toList();

                          return Consumer<ThemeProvider>(
                            builder: (context, themeProvider, child) {
                              return ListView(
                                children: activePilots.map((pilot) {
                                  final pilotMap =
                                      pilot as Map<String, dynamic>;
                                  final String pilotId =
                                      pilotMap['id'].toString();
                                  final String pilotName =
                                      pilotMap['name'].toString();

                                  final bool isSelected =
                                      (pilotId == waitingPilotId);
                                  final bool isDarkMode =
                                      themeProvider.isDarkMode;
                                  final Color cardColor = isSelected
                                      ? (isDarkMode
                                          ? const Color.fromARGB(
                                              255, 40, 102, 43)
                                          : const Color.fromARGB(
                                              255, 73, 175, 78))
                                      : (isDarkMode
                                          ? const Color.fromARGB(
                                              255, 54, 54, 54)
                                          : const Color.fromARGB(
                                              255, 168, 167, 167));

                                  final times =
                                      pilotMap['times'] as List<dynamic>? ?? [];
                                  final formattedTimes = times
                                      .map((t) => formatMs(t as int))
                                      .toList();
                                  final timesStr = formattedTimes.join("  ");

                                  return InkWell(
                                    onTap: () {
                                      if (esp32Connected) {
                                        setState(() {
                                          waitingPilotId = pilotId;
                                        });
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              "Esperando datos del ESP32 para el piloto $pilotName...",
                                            ),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content:
                                                Text("ESP32 no está conectado"),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      }
                                    },
                                    child: Card(
                                      margin: EdgeInsets.symmetric(
                                          vertical: 6.0, horizontal: 8.0),
                                      color: cardColor,
                                      child: ListTile(
                                        title: Text(pilotName),
                                        subtitle: Text(
                                          times.isEmpty
                                              ? "Tiempos: ---"
                                              : "Tiempos: $timesStr",
                                        ),
                                        trailing: Icon(Icons.timer),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ],

                // ----------------------------------
                // SECCIÓN PARA USUARIOS NO ADMIN
                // ----------------------------------
                if (!isAdmin)
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('sessions')
                          .where('active',
                              isEqualTo: true) // Solo sesiones activas
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return Center(child: CircularProgressIndicator());
                        }
                        var docs = snapshot.data!.docs;
                        if (docs.isEmpty) {
                          return Center(
                              child: Text(
                                  "No hay sesiones activas en este momento."));
                        }

                        var sessionData =
                            docs.first.data() as Map<String, dynamic>;
                        DateTime sessionDate = sessionData['date'] is Timestamp
                            ? (sessionData['date'] as Timestamp).toDate()
                            : sessionData['date'];

                        final pilots =
                            sessionData['pilots'] as List<dynamic>? ?? [];
                        final activePilots =
                            pilots.where((p) => p['active'] == true).toList();

                        return Column(
                          children: [
                            Center(
                              child: Text(
                                "${sessionData['location']}, ${sessionData['distance']} m, ${sessionDate.toString().split(' ')[0]}",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(height: 10),
                            Expanded(
                              child: ListView(
                                children: activePilots.map((pilot) {
                                  final times =
                                      pilot['times'] as List<dynamic>? ?? [];
                                  final formattedTimes = times
                                      .map((t) => formatMs(t as int))
                                      .toList();
                                  final timesStr = formattedTimes.join("  ");

                                  return Card(
                                    child: ListTile(
                                      title: Text(pilot['name']),
                                      subtitle: Text(
                                        times.isEmpty
                                            ? "Tiempos: ---"
                                            : "Tiempos: $timesStr",
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
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    scanSubscription?.cancel();
    connectionSubscription?.cancel();
    dataSubscription?.cancel();
    reconnectTimer?.cancel();
    super.dispose();
  }
}
