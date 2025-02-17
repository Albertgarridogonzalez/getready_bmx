import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BluetoothApp(),
    );
  }
}

class BluetoothApp extends StatefulWidget {
  @override
  _BluetoothAppState createState() => _BluetoothAppState();
}

class _BluetoothAppState extends State<BluetoothApp> {
  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? scanSubscription;
  StreamSubscription<ConnectionStateUpdate>? connectionSubscription;
  StreamSubscription<List<int>>? dataSubscription;

  String receivedData = "Esperando datos...";
  bool isConnected = false;
  String? deviceId;

  // 🔹 Cambiamos los UUIDs a los nuevos valores personalizados
  final Uuid serviceUuid = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
  final Uuid characteristicUuid =
      Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");

  @override
  void initState() {
    super.initState();
    requestPermissions();
  }

  /// 🔹 Solicitar permisos Bluetooth
  void requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses.values.every((status) => status == PermissionStatus.granted)) {
      print("✅ Todos los permisos concedidos");
    } else {
      print("⚠️ Algunos permisos fueron denegados");
    }
  }

  /// 🔹 Escanear dispositivos y conectar
  void scanAndConnect() {
    scanSubscription = flutterReactiveBle.scanForDevices(
      withServices: [serviceUuid],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      print("📡 Dispositivo encontrado: ${device.name} - ${device.id}");
      if (device.name == "GetReady_BMX") {
        scanSubscription?.cancel();
        connectToDevice(device);
      }
    }, onError: (error) {
      print("❌ Error al escanear: $error");
    });
  }

  /// 🔹 Conectar al dispositivo
  void connectToDevice(DiscoveredDevice device) {
    print("🔗 Intentando conectar con: ${device.name} - ${device.id}");

    connectionSubscription = flutterReactiveBle
        .connectToDevice(
      id: device.id,
      servicesWithCharacteristicsToDiscover: {
        serviceUuid: [characteristicUuid]
      },
      connectionTimeout: const Duration(seconds: 5),
    )
        .listen((connectionState) {
      print("🔗 Estado de conexión: ${connectionState.connectionState}");

      if (connectionState.connectionState == DeviceConnectionState.connected) {
        print("✅ Conexión exitosa, llamando a discoverServices()");
        discoverServices(device.id);
      } else {
        print(
            "⚠️ Estado de conexión inesperado: ${connectionState.connectionState}");
      }
    }, onError: (error) {
      print("❌ Error de conexión: $error");
    });
  }

  /// 🔹 Descubrir servicios y suscribirse a `notify`
  void discoverServices(String deviceId) async {
    try {
      final characteristic = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: characteristicUuid,
        deviceId: deviceId,
      );

      print(
          "🔍 Intentando suscribirse a notify en ${characteristic.characteristicId}");

      // 🔹 Espera un poco antes de suscribirse para evitar problemas de conexión
      await Future.delayed(Duration(seconds: 1));

      // 🔥 SUSCRIPCIÓN A NOTIFY
      dataSubscription = flutterReactiveBle
          .subscribeToCharacteristic(characteristic)
          .listen((value) {
        if (value.isNotEmpty) {
          String receivedString = String.fromCharCodes(value);
          print("📩 Datos recibidos en Flutter: $receivedString");

          setState(() {
            receivedData = receivedString;
          });
        } else {
          print("⚠️ Recibido un valor vacío");
        }
      }, onError: (error) {
        print("⚠️ Error en la suscripción: $error");
      });

      print("✅ Suscripción a notify activada correctamente");

      // 🔹 PRUEBA una lectura manual para verificar conexión
      await Future.delayed(Duration(seconds: 2));
      List<int> testValue =
          await flutterReactiveBle.readCharacteristic(characteristic);
      print(
          "📤 Lectura manual de la característica: ${String.fromCharCodes(testValue)}");
    } catch (e) {
      print("⚠️ Error al descubrir servicios: $e");
    }
  }

  /// 🔹 Desconectar el dispositivo
  void disconnectDevice() async {
    if (isConnected && deviceId != null) {
      dataSubscription?.cancel();
      connectionSubscription?.cancel();
      flutterReactiveBle.clearGattCache(deviceId!);

      setState(() {
        isConnected = false;
        receivedData = "Esperando datos...";
      });
      print("🔌 Dispositivo desconectado");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Cronómetro BLE")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              receivedData,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            if (!isConnected) ...[
              ElevatedButton(
                onPressed: scanAndConnect,
                child: Text("Conectar al ESP32"),
              ),
            ] else ...[
              ElevatedButton(
                onPressed: disconnectDevice,
                child: Text("Desconectar"),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
