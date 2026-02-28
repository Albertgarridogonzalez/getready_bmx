import 'dart:async';
import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

class BleService {
  final _ble = FlutterReactiveBle();
  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String characteristicUuid =
      "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  Future<bool> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  void startScan(Function(DiscoveredDevice) onDeviceFound) {
    _scanSubscription?.cancel();
    _scanSubscription = _ble.scanForDevices(
      withServices: [],
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (device.name == "BMX_RACE_TIMING") {
        onDeviceFound(device);
      }
    });
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<void> sendConfig({
    required String deviceAddress,
    required String ssid,
    required String password,
    required String esp32Id,
    required String deviceName,
  }) async {
    final characteristic = QualifiedCharacteristic(
      serviceId: Uuid.parse(serviceUuid),
      characteristicId: Uuid.parse(characteristicUuid),
      deviceId: deviceAddress,
    );

    final String json = jsonEncode({
      "ssid": ssid,
      "password": password,
      "esp32Id": esp32Id,
      "deviceName": deviceName,
    });

    final List<int> data = utf8.encode(json);

    // Conectamos manualmente para asegurar el envío
    final connection = _ble
        .connectToDevice(
      id: deviceAddress,
      connectionTimeout: const Duration(seconds: 5),
    )
        .listen((state) async {
      if (state.connectionState == DeviceConnectionState.connected) {
        try {
          await _ble.writeCharacteristicWithResponse(characteristic,
              value: data);
          print("✅ Configuración enviada!");
        } catch (e) {
          print("❌ Error al escribir: $e");
        }
      }
    });

    await Future.delayed(const Duration(seconds: 5));
    await connection.cancel();
  }
}
