import 'dart:async';

import 'package:bisection/bisect.dart';
import 'package:xcnav/datadog.dart' as dd;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';

enum ValueInRange {
  inRange,
  belowRange,
  aboveRange,
}

class DeviceValue {
  final double value;

  /// Is value in detectable range?
  final ValueInRange status;

  DeviceValue(this.value, this.status);
}

class SensorCalibration {
  /// map input -> output curve
  final List<List<double>> _sensorLUT;

  SensorCalibration(this._sensorLUT);

  DeviceValue calibrateValue(double rawValue) {
    // Check bounds
    if (rawValue <= _sensorLUT.first[0]) {
      return DeviceValue(_sensorLUT.first[1], ValueInRange.belowRange);
    } else if (rawValue >= _sensorLUT.last[0]) {
      return DeviceValue(_sensorLUT.last[1], ValueInRange.aboveRange);
    }

    // Find the closest value in the LUT
    int index = bisect_right(_sensorLUT.map((e) => e[0]).toList(), rawValue);

    final x1 = _sensorLUT[index - 1][0];
    final y1 = _sensorLUT[index - 1][1];
    final x2 = _sensorLUT[index][0];
    final y2 = _sensorLUT[index][1];

    // Linear interpolation
    return DeviceValue(y1 + (y2 - y1) * ((rawValue - x1) / (x2 - x1)), ValueInRange.inRange);
  }
}

class BleDeviceXc170 extends BleDeviceHandler {
  final StreamController<DeviceValue> _fuelSensorRawStream = StreamController();

  Timer? _refreshTimer;

  BleDeviceXc170() : super();

  Stream<DeviceValue> get fuelSensorRawStream => _fuelSensorRawStream.stream;

  final SensorCalibration _fuelCalibration = SensorCalibration([
    [24, 1], // 18 originally
    [304, 1.5],
    [556, 2],
    [797, 2.5],
    [1030, 3],
    [1265, 3.5],
    [1494, 4],
    [1722, 4.5],
    [1973, 5],
    [2210, 5.5],
    [2448, 6],
    [2688, 6.5],
    [2936, 7],
    [3193, 7.5],
    [3453, 8],
    [3732, 8.5],
    [3993, 9],
    [4274, 9.5],
    [4556, 10],
    [4830, 10.5],
    [5129, 11],
    [5433, 11.5],
    [5755, 12],
    [6101, 12.5],
    [6455, 13],
    [6837, 13.5],
    [7244, 14],
    [7544, 14.5],
    [8049, 15],
    [8180, 15.5], // 8190 originally
  ]);

  @override
  Future onConnected(BluetoothDevice instance) async {
    await super.onConnected(instance);

    // Get fuel sensor reading
    _refreshTimer = Timer.periodic(Duration(seconds: 1), (_) {
      characteristics["00000000-9135-710e-ab8a-531bcc658ce0"]?["00000001-9135-710e-ab8a-531bcc658ce0"]
          ?.read()
          .then((value) {
        if (value.isNotEmpty) {
          final rawValue = (value[0] + (value[1] << 8)).toDouble();
          _fuelSensorRawStream.sink.add(_fuelCalibration.calibrateValue(rawValue));
          debugPrint("Fuel sensor raw value: $rawValue");
        } else {
          debugPrint("No data received from fuel sensor characteristic");
        }
      }).catchError((error) {
        dd.error("Reading fuel sensor characteristic", errorMessage: error.toString(), errorKind: "BLE");
      });
    });
  }

  @override
  void onDisconnected() {
    super.onDisconnected();
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}
