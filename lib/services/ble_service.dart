import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/ble_devices/ble_device_big_battery.dart';
import 'package:xcnav/ble_devices/ble_device_meshtastic.dart';
import 'package:xcnav/ble_devices/ble_device_runleader.dart';
import 'package:xcnav/ble_devices/ble_device_sp140.dart';
import 'package:xcnav/ble_devices/ble_device_stodeus.dart';
import 'package:xcnav/ble_devices/ble_device_xc170.dart';
import 'package:xcnav/settings_service.dart';

final BleDeviceXc170 bleDeviceXc170 = BleDeviceXc170();
final BleDeviceBigBattery bleDeviceBigBattery = BleDeviceBigBattery();
final BleDeviceRunleader bleDeviceRunleader = BleDeviceRunleader();
final BleDeviceSp140 bleDeviceSp140 = BleDeviceSp140();
final BleDeviceMeshtastic bleDeviceMeshtastic = BleDeviceMeshtastic();
final BleDeviceStodeus bleDeviceStodeus = BleDeviceStodeus();

final Map<String, BleDeviceHandler> _deviceHandlersByName = {
  r'xc170': bleDeviceXc170,
  r'BigBattery': bleDeviceBigBattery,
  r'[aA]i[lL]ink_[0-9a-zA-Z]{4}': bleDeviceRunleader,
  r'OpenPPG SP140[.]*': bleDeviceSp140,
  r'([Uu]ltra|ULTRA|[Bb]lue|BLUE)[ _-]?([Bb]ip|BIP)|[Ss]todeus|STODEUS': bleDeviceStodeus,
};

/// Devices whose advertised name varies, so they're matched by advertised service instead.
final List<BleDeviceHandler> _deviceHandlersByService = [bleDeviceMeshtastic];

final Map<String, StreamSubscription<BluetoothConnectionState>> _deviceStateListener = {};
StreamSubscription<List<ScanResult>>? _devicesListener;

Timer? autoScan;
bool scanning = false;
bool alreadyRequestedPermission = false;

/// Scan result is a device we know how to talk to.
bool isSupported(ScanResult result) =>
    getHandler(name: result.device.advName, serviceUuids: result.advertisementData.serviceUuids) != null;

/// Handler is currently associated with this device.
bool isHandlerDevice(BleDeviceHandler handler, DeviceIdentifier deviceId) => handler.device?.remoteId == deviceId;

BleDeviceHandler? getHandler({String? name, List<Guid>? serviceUuids, DeviceIdentifier? deviceId}) {
  if (serviceUuids != null) {
    for (final each in _deviceHandlersByService) {
      if (serviceUuids.contains(Guid(each.SERVICE_UUID))) {
        return each;
      }
    }
  }
  if (name != null) {
    for (final entry in _deviceHandlersByName.entries) {
      final regex = RegExp(entry.key);
      if (regex.hasMatch(name)) {
        return entry.value;
      }
    }
  } else if (deviceId != null) {
    for (final each in [..._deviceHandlersByName.values, ..._deviceHandlersByService]) {
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
    if (!alreadyRequestedPermission) {
      alreadyRequestedPermission = true;
      debugPrint("Requesting Bluetooth permission...");
      await Permission.bluetooth.request();
    } else {
      debugPrint("Bluetooth permission already requested.");
    }
    return;
  }
  debugPrint("BLE Scanning...");
  _devicesListener ??= FlutterBluePlus.scanResults.listen((results) {
    for (ScanResult result in results) {
      final device = result.device;
      final handler = getHandler(name: device.advName, serviceUuids: result.advertisementData.serviceUuids);

      if (handler == null) {
        // Scan is unfiltered, so most results are unrelated devices.
        continue;
      }

      if (isHandlerDevice(handler, device.remoteId)) {
        // Already associated
        debugPrint("Already associated: ${device.advName} ${device.remoteId.str}");
      } else {
        // NOTE: scanResults re-emits the whole list on every advertisement, so only subscribe once per device.
        //       Several devices can share one handler (e.g. multiple Meshtastic nodes in range).
        if (_deviceStateListener[device.remoteId.str] == null) {
          debugPrint("Found device: ${device.advName} ${device.remoteId.str}");
          _deviceStateListener[device.remoteId.str] = device.connectionState.listen((state) {
            if (state == BluetoothConnectionState.disconnected) {
              // Only react if this is the device the handler is using, not another one it could match.
              if (isHandlerDevice(handler, device.remoteId)) {
                debugPrint("Device disconnected: ${device.advName} ${device.remoteId.str}");
                handler.onDisconnected();
              }
            } else if (state == BluetoothConnectionState.connected) {
              handler.onConnected(device);
            }
          });
        }

        if (settingsMgr.bleAutoDevices.value.contains(device.remoteId.str) && !device.isConnected) {
          debugPrint("Auto connecting to ${device.advName}:${device.remoteId.str}");
          connect(device);
        }
      }
    }
  });

  // NOTE: No scan filter. On Android `withKeywords` can't be combined with `withServices`, and some
  //       devices (e.g. Meshtastic) are only recognizable by service. Results are filtered with `isSupported`.
  await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));
}

Future connect(BluetoothDevice device) async {
  debugPrint("Connecting to device: ${device.advName} ${device.remoteId.str}");
  await device.connect(license: License.nonprofit);
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
