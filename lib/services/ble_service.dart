import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/ble_devices/ble_device_big_battery.dart';
import 'package:xcnav/ble_devices/ble_device_runleader.dart';
import 'package:xcnav/ble_devices/ble_device_sp140.dart';
import 'package:xcnav/ble_devices/ble_device_xc170.dart';
import 'package:xcnav/settings_service.dart';

final BleDeviceXc170 bleDeviceXc170 = BleDeviceXc170();
final BleDeviceBigBattery bleDeviceBigBattery = BleDeviceBigBattery();
final BleDeviceRunleader bleDeviceRunleader = BleDeviceRunleader();
final BleDeviceSp140 bleDeviceSp140 = BleDeviceSp140();

final Map<String, BleDeviceHandler> _deviceHandlersByName = {
  r'xc170': bleDeviceXc170,
  r'BigBattery': bleDeviceBigBattery,
  r'[aA]i[lL]ink_[0-9a-zA-Z]{4}': bleDeviceRunleader,
  r'OpenPPG SP140[.]*': bleDeviceSp140,
};

final Map<String, StreamSubscription<BluetoothConnectionState>> _deviceStateListener = {};
StreamSubscription<List<ScanResult>>? _devicesListener;

Timer? autoScan;
bool scanning = false;

BleDeviceHandler? getHandler({String? name, DeviceIdentifier? deviceId}) {
  if (name != null) {
    for (final entry in _deviceHandlersByName.entries) {
      final regex = RegExp(entry.key);
      if (regex.hasMatch(name)) {
        return entry.value;
      }
    }
  } else if (deviceId != null) {
    for (final each in _deviceHandlersByName.values) {
      if (each.device != null && each.device?.remoteId == deviceId) {
        return each;
      }
    }
  }
  return null;
}

void scan() async {
  if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.off) {
    return;
  }
  if (FlutterBluePlus.adapterStateNow == BluetoothAdapterState.unauthorized) {
    Permission.bluetooth.request();
    return;
  }
  debugPrint("BLE Scanning...");
  _devicesListener ??= FlutterBluePlus.scanResults.listen((results) {
    for (ScanResult result in results) {
      final device = result.device;
      final handler = getHandler(name: device.advName);

      if (handler == null) {
        debugPrint("Unknown device found: ${device.advName} ${device.remoteId.str}");
        continue;
      }

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
            if (handler.device?.isConnected ?? false) {
              debugPrint("Deveice disconnected: ${device.advName} ${device.remoteId.str}");
              handler.onDisconnected();
            }
          } else if (state == BluetoothConnectionState.connected) {
            handler.onConnected(device);
          }
        });

        if (settingsMgr.bleAutoDevices.value.contains(device.remoteId.str) && !device.isConnected) {
          debugPrint("Auto connecting to ${device.advName}:${device.remoteId.str}");
          connect(device);
        }
      }
    }
  });

  await FlutterBluePlus.startScan(
      withKeywords: ["AiLink_", "xc170", "BigBattery", "OpenPPG SP140"],
      // withServices: _deviceHandlersByName.values.map((e) => Guid.fromString(e.SERVICE_UUID)).toList(),
      timeout: Duration(seconds: 10));
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
  final handler = getHandler(deviceId: device.remoteId);
  if (handler != null) {
    handler.device = null;
  }
  device.disconnect();
}
