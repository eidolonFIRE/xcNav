import 'dart:async';

import 'package:bisection/bisect.dart';
import 'package:clock/clock.dart';
import 'package:xcnav/util.dart';

class MapValue<T extends num> {
  /// map input -> output curve
  final List<List<T>> _sensorLUT;

  T get maxValue => _sensorLUT.last[1];
  T get minValue => _sensorLUT.first[1];

  MapValue(this._sensorLUT);

  T mapValue(T rawValue) {
    // Check bounds
    if (rawValue <= _sensorLUT.first[0]) {
      return minValue;
    } else if (rawValue >= _sensorLUT.last[0]) {
      return maxValue;
    }

    // Find the closest value in the LUT
    int index = bisect_right(_sensorLUT.map((e) => e[0]).toList(), rawValue);

    final x1 = _sensorLUT[index - 1][0];
    final y1 = _sensorLUT[index - 1][1];
    final x2 = _sensorLUT[index][0];
    final y2 = _sensorLUT[index][1];

    // Linear interpolation

    if (T is int) {
      return (y1 + (y2 - y1) * ((rawValue - x1) / (x2 - x1))).round() as T;
    } else {
      return y1 + (y2 - y1) * ((rawValue - x1) / (x2 - x1)) as T;
    }
  }
}

class BleLoggedValue<T extends num> {
  final StreamController<T> _valueRawStream = StreamController.broadcast();

  Stream<T> get valueRawStream => _valueRawStream.stream;

  final List<TimestampValue<T>> log = [];

  final MapValue<T>? calibration;

  BleLoggedValue({required this.calibration});

  void addValue(T value, DateTime? timestamp) {
    T calibratedValue = calibration == null ? value : calibration!.mapValue(value);
    _valueRawStream.sink.add(calibratedValue);
    log.add(TimestampValue<T>((timestamp ?? clock.now()).millisecondsSinceEpoch, calibratedValue));
  }

  Map<String, dynamic>? toJson() {
    final startTime = log.firstOrNull?.time ?? 0;
    return {
      if (calibration != null) "min_value": roundToDigits(calibration!.minValue.toDouble(), 1),
      if (calibration != null) "max_value": roundToDigits(calibration!.maxValue.toDouble(), 1),
      "start_time": startTime,
      "data": log
          .map((e) => [e.time - startTime, e.value is double ? roundToDigits(e.value as double, 2) : e.value])
          .toList()
    };
  }
}
