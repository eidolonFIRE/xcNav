import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/ble_devices/ble_device_big_battery.dart';
import 'package:xcnav/ble_devices/ble_device_xc170.dart';
import 'package:xcnav/settings_service.dart';

final BleDeviceXc170 bleDeviceXc170 = BleDeviceXc170();
final BleDeviceBigBattery bleDeviceBigBattery = BleDeviceBigBattery();

final Map<String, BleDeviceHandler> _deviceHandlers = {"xc170": bleDeviceXc170, "BigBattery": bleDeviceBigBattery};

final Map<String, StreamSubscription<BluetoothConnectionState>> _deviceStateListener = {};
StreamSubscription<List<ScanResult>>? _devicesListener;

Timer? autoScan;
bool scanning = false;

BleDeviceHandler? getHandler({String? name, DeviceIdentifier? deviceId}) {
  if (name != null) {
    final handler = _deviceHandlers[name];
    if (handler != null && handler.device != null) {
      return handler;
    }
  } else if (deviceId != null) {
    for (final each in _deviceHandlers.values) {
      if (each.device != null && each.device?.remoteId == deviceId) {
        return each;
      }
    }
  }
  return null;
}

void scan() async {
  if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
    return;
  }
  debugPrint("BLE Scanning...");
  // if (_devicesListener != null) {
  //   debugPrint("Cancelling previous scan listener");
  //   await _devicesListener!.cancel();
  // }
  _devicesListener ??= FlutterBluePlus.scanResults.listen((results) {
    for (ScanResult result in results) {
      final device = result.device;
      if (_deviceHandlers.containsKey(device.advName)) {
        final handler = _deviceHandlers[device.advName]!;
        if (handler.device?.hashCode == device.hashCode) {
          // Already associated
          debugPrint("Already associated: ${device.advName} ${device.remoteId.str}");
        } else {
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

          if (settingsMgr.bleAutoDevices.value.contains(device.remoteId.str) && !device.isConnected) {
            debugPrint("Auto connecting to ${device.advName}:${device.remoteId.str}");
            connect(device);
          }
        }
      } else {
        debugPrint("Unknown device found: ${device.advName}");
      }
    }
  });

  await FlutterBluePlus.startScan(withNames: _deviceHandlers.keys.toList(), timeout: Duration(seconds: 10));
}

Future connect(BluetoothDevice device) async {
  debugPrint("Connecting to device: ${device.advName} ${device.remoteId.str}");
  await device.connect(license: License.free);

  // Arm autoScan so we auto-connect if disconnected
  // Timer(Duration(seconds: 30), () {
  //   debugPrint("BLE autoScan armed (was $autoScan)");
  //   autoScan ??= Timer.periodic(Duration(minutes: 1), (timer) => scan());
  // });
}

Future disconnect(BluetoothDevice device) async {
  debugPrint("Disconnecting from device: ${device.advName} ${device.remoteId.str}");
  final handler = _deviceHandlers[device.advName];
  if (handler != null) {
    handler.device = null;
  }
  device.disconnect();
}
