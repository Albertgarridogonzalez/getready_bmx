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
  DateTime selectedDate = DateTime.now();
  String? selectedLocation;
  List<String> locations = [];
  List<Map<String, dynamic>> selectedPilots = [];
  String? currentSessionId;

  @override
  void initState() {
    super.initState();
    fetchLocations();
  }

  void fetchLocations() async {
    var snapshot =
        await FirebaseFirestore.instance.collection('locations').get();
    setState(() {
      locations = snapshot.docs.map((doc) => doc.id).toList();
    });
  }

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

  void startLiveSession() async {
    if (selectedLocation == null) return;

    DocumentReference sessionRef =
        await FirebaseFirestore.instance.collection('sessions').add({
      'location': selectedLocation,
      'distance': locations.contains(selectedLocation)
          ? await FirebaseFirestore.instance
              .collection('locations')
              .doc(selectedLocation)
              .get()
              .then((doc) => doc['distance'])
          : 0,
      'date': selectedDate,
      'pilots': [],
    });

    setState(() {
      currentSessionId = sessionRef.id;
    });

    showPilotSelectionPopup();
  }

  void showPilotSelectionPopup() async {
    List<Map<String, dynamic>> pilots = [];
    var snapshot = await FirebaseFirestore.instance.collection('pilots').get();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Seleccionar Pilotos"),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: snapshot.docs.map((doc) {
                  String name = doc['name'];
                  return CheckboxListTile(
                    title: Text(name),
                    value: pilots.any((p) => p['id'] == doc.id),
                    onChanged: (bool? checked) {
                      setState(() {
                        if (checked == true) {
                          pilots.add({'id': doc.id, 'name': name});
                        } else {
                          pilots.removeWhere((p) => p['id'] == doc.id);
                        }
                      });
                    },
                  );
                }).toList(),
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

  void savePilotTime(String pilotId, int time) async {
    if (currentSessionId == null) return;

    DocumentReference sessionRef =
        FirebaseFirestore.instance.collection('sessions').doc(currentSessionId);
    
    DocumentSnapshot sessionSnapshot = await sessionRef.get();
    Map<String, dynamic> sessionData = sessionSnapshot.data() as Map<String, dynamic>;

    List<dynamic> updatedPilots = sessionData['pilots'].map((pilot) {
      if (pilot['id'] == pilotId) {
        pilot['times'] = (pilot['times'] ?? [])..add(time);
      }
      return pilot;
    }).toList();

    sessionRef.update({'pilots': updatedPilots});
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final bool isAdmin = authProvider.user?.email == 'admin@admin.com';

    return Scaffold(
      appBar: AppBar(title: Text('Live')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (isAdmin) ...[
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
                              decoration: InputDecoration(
                                  labelText: 'Distancia (m)'),
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                              onPressed: createLocation,
                              child: Text("Guardar"))
                        ],
                      ),
                    );
                  },
                  child: Text('Crear'),
                ),
              ),
            ],
            ListTile(
              title: Text('Fecha: ${selectedDate.toLocal()}'.split(' ')[0]),
              trailing: Icon(Icons.calendar_today),
              onTap: () async {
                DateTime? pickedDate = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (pickedDate != null) {
                  setState(() {
                    selectedDate = pickedDate;
                  });
                }
              },
            ),
            DropdownButton<String>(
              value: selectedLocation,
              hint: Text("Seleccionar Ubicación"),
              items: locations.map((String location) {
                return DropdownMenuItem<String>(
                  value: location,
                  child: Text(location),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  selectedLocation = newValue;
                });
              },
            ),
            ElevatedButton(
              onPressed: startLiveSession,
              child: Text('Iniciar Live'),
            ),
            if (currentSessionId != null) Expanded(
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('sessions')
                    .doc(currentSessionId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return CircularProgressIndicator();

                  var data = snapshot.data!.data() as Map<String, dynamic>;
                  List<dynamic> pilots = data['pilots'] ?? [];

                  return ListView(
                    children: pilots.map((pilot) {
                      return ListTile(
                        title: Text(pilot['name']),
                        subtitle: Text("Tiempos: ${pilot['times']?.join(", ") ?? ''}"),
                      );
                    }).toList(),
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
