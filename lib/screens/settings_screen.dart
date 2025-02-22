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

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  // Carga el nombre del piloto y la configuración de tema del usuario desde Firestore
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

  // Escanea y conecta con el ESP32
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

  // Desconecta el dispositivo ESP32
  void disconnectDevice() {
    if (isConnected && deviceId != null) {
      flutterReactiveBle.clearGattCache(deviceId!);
      setState(() {
        isConnected = false;
        deviceId = null;
      });
    }
  }

  // Actualiza el nombre del piloto en Firestore
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
      //appBar: AppBar(
      //  title: Row(
      //    mainAxisAlignment: MainAxisAlignment.spaceBetween,
      //    children: [
      //      Text('GetReady BMX'),
      //      Text('Ajustes'),
      //    ],
      //  ),
      //),
      body: SingleChildScrollView(
        child: Padding(
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
              SizedBox(height: 20),
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
                                await FirebaseFirestore.instance.collection('users').doc(uid).update({
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
            ],
          ),
        ),
      ),
    );
  }
}
