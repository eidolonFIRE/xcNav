import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Base class for a bluetooth device handler.
/// Performs basic utilitys such as mapping the characteristics of a device.
abstract class BleDeviceHandler {
  BluetoothDevice? device;
  Map<String, Map<String, BluetoothCharacteristic>> characteristics = {};

  Timer? reconnector;

  dynamic toJson() {
    throw UnimplementedError();
  }

  Widget configDialog() {
    return Container();
  }

  void onDisconnected() {
    debugPrint("Disconnected from device: ${device?.advName} ${device?.remoteId}");

    if (device != null) {
      reconnector?.cancel();
      reconnector = Timer.periodic(Duration(seconds: 20), (timer) {
        debugPrint("Attempting reconnect to: ${device?.advName} ${device?.remoteId}");
        device?.connect();
      });
    }
  }

  Future onConnected(BluetoothDevice instance) async {
    reconnector?.cancel();
    reconnector = null;

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
