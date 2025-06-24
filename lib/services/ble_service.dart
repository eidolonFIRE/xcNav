import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/ble_devices/ble_device_xc170.dart';

BleDeviceXc170 bleDeviceXc170 = BleDeviceXc170();

Map<String, BleDeviceHandler> _deviceHandlers = {
  "xc170": bleDeviceXc170,
};

Map<String, StreamSubscription<BluetoothConnectionState>> _deviceStateListener = {};
StreamSubscription<List<ScanResult>>? _devicesListener;

void scan() async {
  if (_devicesListener != null) {
    debugPrint("Cancelling previous scan listener");
    await _devicesListener!.cancel();
  }
  _devicesListener = FlutterBluePlus.scanResults.listen((results) {
    for (ScanResult result in results) {
      final device = result.device;
      if (_deviceHandlers.containsKey(device.advName)) {
        final handler = _deviceHandlers[device.advName]!;
        debugPrint("Found device: ${device.advName} ${device.remoteId.str}");
        // Cancel any existing listener for this device
        if (_deviceStateListener[device.remoteId.str] != null) {
          _deviceStateListener[device.remoteId.str]?.cancel();
        }
        // Start new listener for this device
        _deviceStateListener[device.remoteId.str] = device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected) {
            handler.onDisconnected();
          } else if (state == BluetoothConnectionState.connected) {
            handler.onConnected(device);
          }
        });
      } else {
        debugPrint("Unknown device found: ${device.advName}");
      }
    }
  });

  await FlutterBluePlus.startScan(withNames: _deviceHandlers.keys.toList(), timeout: Duration(seconds: 10));
}

Future connect(BluetoothDevice device) async {
  debugPrint("Connecting to device: ${device.advName} ${device.remoteId.str}");
  await device.connect();
}
