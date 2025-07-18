import 'dart:async';

import 'package:bisection/bisect.dart';
import 'package:clock/clock.dart';
import 'package:xcnav/datadog.dart' as dd;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:xcnav/ble_devices/ble_device.dart';
import 'package:xcnav/util.dart';

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

  double get maxValue => _sensorLUT.last[1];
  double get minValue => _sensorLUT.first[1];

  SensorCalibration(this._sensorLUT);

  DeviceValue calibrateValue(double rawValue) {
    // Check bounds
    if (rawValue <= _sensorLUT.first[0]) {
      return DeviceValue(minValue, ValueInRange.belowRange);
    } else if (rawValue >= _sensorLUT.last[0]) {
      return DeviceValue(maxValue, ValueInRange.aboveRange);
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

class DeviceLogEntry {
  final DateTime time;
  final DeviceValue fuel;
  DeviceLogEntry({required this.time, required this.fuel});
}

class BleDeviceXc170 extends BleDeviceHandler {
  final StreamController<DeviceValue> _fuelSensorRawStream = StreamController.broadcast();

  Timer? _refreshTimer;

  BleDeviceXc170() : super();

  Stream<DeviceValue> get fuelSensorRawStream => _fuelSensorRawStream.stream;
  bool get hasLog => log.isNotEmpty;

  final List<DeviceLogEntry> log = [];

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
  Map<String, dynamic>? toJson() {
    if (hasLog) {
      final startTime = log.first.time.millisecondsSinceEpoch;
      return {
        "id": runtimeType.toString(),
        "version": "1.0",
        "fuel": {
          "min_value": roundToDigits(_fuelCalibration.minValue, 1),
          "max_value": roundToDigits(_fuelCalibration.maxValue, 1),
          "start_time": startTime,
          "data": log.map((e) => [e.time.millisecondsSinceEpoch - startTime, roundToDigits(e.fuel.value, 2)]).toList()
        }
      };
    } else {
      return null;
    }
  }

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
          final calibratedValue = _fuelCalibration.calibrateValue(rawValue);
          _fuelSensorRawStream.sink.add(calibratedValue);
          log.add(DeviceLogEntry(time: clock.now(), fuel: calibratedValue));
          // debugPrint("Fuel sensor value: $rawValue == ${calibratedValue.value}");
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
