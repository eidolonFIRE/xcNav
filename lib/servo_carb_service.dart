import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/carb_needle.dart';

late CarbNeedle highNeedle;
late CarbNeedle lowNeedle;

BluetoothDevice? servoCarbDevice;

void initCarbNeedles(SharedPreferences prefs) {
  highNeedle = CarbNeedle("high", prefs);
  lowNeedle = CarbNeedle("low", prefs);
}

void attachBLEdevice(BluetoothDevice device) {
  servoCarbDevice = device;

  // Debug Printing
  for (final serv in device.servicesList) {
    debugPrint("service: ${serv.serviceUuid}");

    for (final char in serv.characteristics) {
      debugPrint("   - char: ${char.characteristicUuid}");
    }
  }

  final service = device.servicesList.where((element) => element.uuid.str == "00ff").firstOrNull;
  if (service != null) {
    // debugPrint("service");
    final highChar = service.characteristics.where((element) => element.uuid.str == "ff01").firstOrNull;
    if (highChar != null) highNeedle.connect(highChar);

    final lowChar = service.characteristics.where((element) => element.uuid.str == "ff02").firstOrNull;
    if (lowChar != null) lowNeedle.connect(lowChar);
  }
}
