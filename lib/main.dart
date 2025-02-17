import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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
  String receivedData = "Esperando tiempo...";
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? targetCharacteristic;
  List<String> foundDevices = [];

  @override
  void initState() {
    super.initState();
    requestPermissions();
  }

  void requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    if (statuses[Permission.bluetooth] == PermissionStatus.granted &&
        statuses[Permission.bluetoothScan] == PermissionStatus.granted &&
        statuses[Permission.bluetoothConnect] == PermissionStatus.granted &&
        statuses[Permission.location] == PermissionStatus.granted) {
      print("✅ Todos los permisos concedidos");
    } else {
      print("⚠️ Algunos permisos fueron denegados");
    }
  }

  void scanAndConnect() async {
    try {
      requestPermissions(); // Asegurar permisos antes de escanear
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Escaneando dispositivos...")),
      );

      FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
      await Future.delayed(Duration(seconds: 2));
      List<ScanResult> scanResults = await FlutterBluePlus.scanResults.first;

      setState(() {
        foundDevices = scanResults.map((r) => "📡 ${r.device.name} - ${r.device.id}").toList();
      });

      ScanResult result = scanResults.firstWhere(
        (r) => r.device.name == "GetReady_BMX",
        orElse: () => throw Exception("No encontrado"),
      );

      FlutterBluePlus.stopScan();
      connectToDevice(result.device);
    } catch (e) {
      setState(() {
        receivedData = "No se encontró el ESP32";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("No se encontró el ESP32")),
      );
    }
  }

  void connectToDevice(BluetoothDevice device) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Conectando a ${device.name}...")),
      );

      await device.connect(autoConnect: true);
      setState(() {
        connectedDevice = device;
      });
      discoverServices(device);
    } catch (e) {
      setState(() {
        receivedData = "Error al conectar";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al conectar")),
      );
    }
  }

  void discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      for (var char in service.characteristics) {
        if (char.properties.notify) {
          await char.setNotifyValue(true);
          char.value.listen((value) {
            setState(() {
              receivedData = String.fromCharCodes(value);
            });
          });
          targetCharacteristic = char;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Conexión exitosa. Recibiendo datos...")),
          );
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Cronómetro Bluetooth")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              receivedData,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: scanAndConnect,
              child: Text(connectedDevice == null ? "Conectar al ESP32" : "Reconectar"),
            ),
            SizedBox(height: 20),
            Text("🔍 Dispositivos encontrados:"),
            ...foundDevices.map((device) => Text(device)).toList(),
          ],
        ),
      ),
    );
  }
}
