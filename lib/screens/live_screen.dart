import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:getready_bmx/providers/auth_provider.dart';

class LiveScreen extends StatefulWidget {
  @override
  _LiveScreenState createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final TextEditingController locationController = TextEditingController();
  final TextEditingController distanceController = TextEditingController();

  // Variables para la sesión (para crear sesión)
  DateTime selectedDate = DateTime.now();
  String? selectedLocation;
  List<String> locations = [];
  // Lista de pilotos de la sesión (cada uno tendrá: id, name, times, active)
  List<Map<String, dynamic>> selectedPilots = [];
  // Guarda el ID de la sesión en live (seleccionada por el admin)
  String? currentSessionId;

  @override
  void initState() {
    super.initState();
    fetchLocations();
  }

  // Obtiene las ubicaciones creadas en la base de datos.
  void fetchLocations() async {
    var snapshot =
        await FirebaseFirestore.instance.collection('locations').get();
    setState(() {
      locations = snapshot.docs.map((doc) => doc.id).toList();
    });
  }

  // Popup para crear una nueva ubicación.
  void createLocation() async {
    String location = locationController.text.trim();
    String distance = distanceController.text.trim();
    if (location.isNotEmpty && distance.isNotEmpty) {
      await FirebaseFirestore.instance.collection('locations').doc(location).set({
        'distance': int.parse(distance),
      });
      fetchLocations();
      Navigator.pop(context);
    }
  }

  // Popup para crear una sesión.
  // Se selecciona la fecha y la ubicación de la sesión.
  void showCreateSessionPopup() {
    DateTime sessionDate = selectedDate;
    String? sessionLocation = selectedLocation;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Crear Sesión"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Selector de fecha (solo se muestra la fecha)
                  ListTile(
                    title: Text('Fecha: ${sessionDate.toString().split(' ')[0]}'),
                    trailing: Icon(Icons.calendar_today),
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: sessionDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setState(() {
                          sessionDate = picked;
                        });
                      }
                    },
                  ),
                  // Dropdown de ubicaciones (ya creadas)
                  DropdownButton<String>(
                    value: sessionLocation,
                    hint: Text("Seleccionar Ubicación"),
                    items: locations.map((String loc) {
                      return DropdownMenuItem<String>(
                        value: loc,
                        child: Text(loc),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
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
                DocumentReference sessionRef =
                    await FirebaseFirestore.instance.collection('sessions').add({
                  'location': sessionLocation,
                  'distance': locations.contains(sessionLocation)
                      ? await FirebaseFirestore.instance
                          .collection('locations')
                          .doc(sessionLocation)
                          .get()
                          .then((doc) =>
                              (doc.data()! as Map<String, dynamic>)['distance'])
                      : 0,
                  'date': sessionDate,
                  'pilots': selectedPilots,
                });
                setState(() {
                  currentSessionId = sessionRef.id;
                  selectedDate = sessionDate;
                  selectedLocation = sessionLocation;
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

  // Popup para seleccionar/deseleccionar pilotos (riders).
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
            builder: (context, setState) {
              return Container(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: snapshot.docs.map((doc) {
                    final data = doc.data()! as Map<String, dynamic>;
                    String name = data['pilotName'] as String;
                    bool isSelected =
                        (currentPilotsMap[doc.id]?['active'] ?? false) as bool;
                    return InkWell(
                      onTap: () {
                        setState(() {
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
                        color: isSelected ? Colors.green[200] : Colors.white,
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: ListTile(
                            title: Text(name),
                            subtitle: isSelected ? Text("Esperando tiempo...") : null,
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

  // Guarda un tiempo (simulado o real) para un piloto.
  void savePilotTime(String pilotId, int time) async {
    if (currentSessionId == null) return;
    DocumentReference sessionRef =
        FirebaseFirestore.instance.collection('sessions').doc(currentSessionId);
    DocumentSnapshot sessionSnapshot = await sessionRef.get();
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

  // Simula la recepción de un tiempo para un piloto.
  void simulateReceiveTime(String pilotId) {
    int simulatedTime = 123;
    savePilotTime(pilotId, simulatedTime);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final bool isAdmin = authProvider.user?.email == 'admin@admin.com';

    return Scaffold(
      //appBar: AppBar(
      //  title: Row(
      //    mainAxisAlignment: MainAxisAlignment.spaceBetween,
      //    children: [
      //      Text('GetReady BMX'),
      //      Text('Live'),
      //    ],
      //  ),
      //),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (isAdmin) ...[
              // Botón para crear ubicación.
              Align(
                alignment: Alignment.topRight,
                child: ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
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
                      ),
                    );
                  },
                  child: Text('Crear Ubicación'),
                ),
              ),
              SizedBox(height: 10),
              // Botón para crear sesión.
              Align(
                alignment: Alignment.topRight,
                child: ElevatedButton(
                  onPressed: showCreateSessionPopup,
                  child: Text('Crear Sesión'),
                ),
              ),
              SizedBox(height: 10),
              // Dropdown para que el admin seleccione cuál de las últimas 5 sesiones es la live.
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('sessions')
                    .orderBy('date', descending: true)
                    .limit(5)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData)
                    return Center(child: CircularProgressIndicator());
                  var docs = snapshot.data!.docs;
                  final sessionIds = docs.map((doc) => doc.id).toList();
                  final dropdownValue =
                      sessionIds.contains(currentSessionId) ? currentSessionId : null;
                  return DropdownButton<String>(
                    value: dropdownValue,
                    hint: Text("Seleccionar sesión"),
                    items: docs.map((doc) {
                      var data = doc.data() as Map<String, dynamic>;
                      DateTime sessionDate = data['date'] is Timestamp
                          ? (data['date'] as Timestamp).toDate()
                          : data['date'];
                      // Muestra solo "<ubicación>, <fecha>" sin prefijos.
                      String displayText =
                          "${data['location']}, ${sessionDate.toString().split(' ')[0]}";
                      return DropdownMenuItem<String>(
                        value: doc.id,
                        child: Text(displayText),
                      );
                    }).toList(),
                    onChanged: (String? newValue) async {
                      if (newValue != null) {
                        DocumentSnapshot sessionDoc = await FirebaseFirestore.instance
                            .collection('sessions')
                            .doc(newValue)
                            .get();
                        Map<String, dynamic> sessionData =
                            sessionDoc.data()! as Map<String, dynamic>;
                        DateTime docDate = sessionData['date'] is Timestamp
                            ? (sessionData['date'] as Timestamp).toDate()
                            : sessionData['date'];
                        setState(() {
                          currentSessionId = newValue;
                          selectedLocation = sessionData['location'];
                          selectedDate = docDate;
                        });
                      }
                    },
                  );
                },
              ),
              if (currentSessionId != null) ...[
                SizedBox(height: 20),
                Center(
                  child: Text(
                    // Encabezado sin prefijos, actualizado según la sesión seleccionada.
                    "$selectedLocation, ${selectedDate.toString().split(' ')[0]}",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(height: 10),
                ElevatedButton(
                  onPressed: showPilotSelectionPopup,
                  child: Text("Añadir Riders"),
                ),
                SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('sessions')
                        .doc(currentSessionId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return Center(child: CircularProgressIndicator());
                      var data = snapshot.data!.data()! as Map<String, dynamic>;
                      List<dynamic> pilots = data['pilots'] ?? [];
                      List<dynamic> activePilots = pilots.where((p) {
                        return ((p as Map<String, dynamic>)['active'] ?? false)
                            as bool;
                      }).toList();
                      return ListView(
                        children: activePilots.map((pilot) {
                          final pilotMap = pilot as Map<String, dynamic>;
                          return InkWell(
                            onTap: () {
                              simulateReceiveTime(pilotMap['id'] as String);
                            },
                            child: Card(
                              margin: EdgeInsets.symmetric(
                                  vertical: 6.0, horizontal: 8.0),
                              child: ListTile(
                                title: Text(pilotMap['name'] as String),
                                subtitle: Text(
                                    "Tiempos: ${(pilotMap['times'] as List?)?.join(", ") ?? '---'}"),
                                trailing: Icon(Icons.timer),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
              ],
            ],
            // Para usuarios no admin: se muestra el encabezado (texto) y la lista de riders de la sesión live.
            if (!isAdmin)
              Expanded(
                child: currentSessionId == null
                    ? Center(child: Text("No hay sesión en vivo."))
                    : StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('sessions')
                            .doc(currentSessionId)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData)
                            return Center(child: CircularProgressIndicator());
                          var data =
                              snapshot.data!.data()! as Map<String, dynamic>;
                          DateTime sessionDate = data['date'] is Timestamp
                              ? (data['date'] as Timestamp).toDate()
                              : data['date'];
                          return Column(
                            children: [
                              Center(
                                child: Text(
                                  "${data['location']}, ${sessionDate.toString().split(' ')[0]}",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              SizedBox(height: 10),
                              Expanded(
                                child: StreamBuilder<DocumentSnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('sessions')
                                      .doc(currentSessionId)
                                      .snapshots(),
                                  builder: (context, snapshot2) {
                                    if (!snapshot2.hasData)
                                      return Center(
                                          child: CircularProgressIndicator());
                                    var sessionData =
                                        snapshot2.data!.data() as Map<String, dynamic>;
                                    List<dynamic> pilots = sessionData['pilots'] ?? [];
                                    List<dynamic> activePilots = pilots.where((p) {
                                      return ((p as Map<String, dynamic>)['active'] ??
                                              false)
                                          as bool;
                                    }).toList();
                                    return ListView(
                                      children: activePilots.map((pilot) {
                                        final pilotMap =
                                            pilot as Map<String, dynamic>;
                                        return InkWell(
                                          onTap: () {
                                            simulateReceiveTime(
                                                pilotMap['id'] as String);
                                          },
                                          child: Card(
                                            margin: EdgeInsets.symmetric(
                                                vertical: 6.0, horizontal: 8.0),
                                            child: ListTile(
                                              title: Text(pilotMap['name'] as String),
                                              subtitle: Text(
                                                  "Tiempos: ${(pilotMap['times'] as List?)?.join(", ") ?? '---'}"),
                                              trailing: Icon(Icons.timer),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
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
    );
  }
}
