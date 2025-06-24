import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Base class for a bluetooth device handler.
/// Performs basic utilitys such as mapping the characteristics of a device.
abstract class BleDeviceHandler {
  BluetoothDevice? device;
  Map<String, Map<String, BluetoothCharacteristic>> characteristics = {};

  void onDisconnected() {
    if (device == null || (device?.isDisconnected ?? true)) return;
    debugPrint("Disconnected from device: ${device?.advName} ${device?.remoteId}");
    device = null;
    characteristics.clear();
  }

  Future onConnected(BluetoothDevice instance) async {
    device = instance;
    debugPrint("Connected to device: ${device!.advName} ${device?.remoteId}");

    // Discover services after connecting
    final services = await device!.discoverServices();
    debugPrint("Discovered services for device: ${device!.advName} ${device?.remoteId}");
    for (var service in services) {
      debugPrint("Service UUID: ${service.uuid}");
      for (var characteristic in service.characteristics) {
        debugPrint("  Characteristic UUID: ${characteristic.uuid}");
        characteristics[service.uuid.toString()] ??= {};
        characteristics[service.uuid.toString()]![characteristic.uuid.toString()] = characteristic;
      }
    }
  }
}
