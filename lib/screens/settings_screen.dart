// screens/settings_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:getready_bmx/providers/auth_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPilotName();
  }

  Future<void> _loadPilotName() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          pilotNameController.text = doc['pilotName'] ?? '';
        });
      }
    }
  }

  void scanAndConnect() {
    final serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
    final characteristicUuid = Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");
    
    flutterReactiveBle.scanForDevices(withServices: [serviceUuid]).listen((device) {
      if (device.name == "GetReady_BMX") {
        flutterReactiveBle.connectToDevice(id: device.id).listen((connectionState) {
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
    });
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
      SnackBar(content: Text('Nombre del piloto actualizado'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;
    final bool isAdmin = user?.email == 'admin@admin.com';

    return Scaffold(
      appBar: AppBar(title: Text('Ajustes')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: pilotNameController,
              decoration: InputDecoration(labelText: 'Nombre del piloto'),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => updatePilotName(user!.uid),
              child: Text('Guardar Nombre'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                await authProvider.signOut();
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              },
              child: Text('Cerrar Sesión'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
            SizedBox(height: 20),
            if (isAdmin)
              ElevatedButton(
                onPressed: isConnected ? disconnectDevice : scanAndConnect,
                child: Text(isConnected ? 'Desconectar ESP32' : 'Conectar al ESP32'),
              ),
          ],
        ),
      ),
    );
  }
}
