import 'dart:async';

import 'package:bisection/bisect.dart';
import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/douglas_peucker.dart';
import 'package:xcnav/datadog.dart' as dd;

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
    if (T.toString() == "int") {
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

  BleLoggedValue({this.calibration});

  void addValue(T value, DateTime? timestamp) {
    T calibratedValue = calibration == null ? value : calibration!.mapValue(value);
    _valueRawStream.sink.add(calibratedValue);
    log.add(TimestampValue<T>((timestamp ?? clock.now()).millisecondsSinceEpoch, calibratedValue));
  }

  /// Simplifies all the log data
  void compress({double epsilon = 0.01}) {
    if (log is List<TimestampValue<double>>) {
      final temp = douglasPeuckerTimestamped(log as List<TimestampValue<double>>, epsilon);
      log.clear();
      log.addAll(temp as List<TimestampValue<T>>);
    } else if (log is List<TimestampValue<int>>) {
      final temp = douglasPeuckerTimestamped(
          log.map((e) => TimestampValue<double>(e.time, e.value.toDouble())).toList(), epsilon);
      log.clear();
      log.addAll(temp.map((e) => TimestampValue<T>(e.time, e.value.round() as T)).toList());
    } else {
      dd.warn("Tried to compress BleLoggedValue with unsupported type: ${T.runtimeType}");
    }
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

  void trimToRange(DateTimeRange range) {
    // Add interpolated points at the start and end of the range
    final startIndex = bisect_right(log.map((e) => e.time).toList(), range.start.millisecondsSinceEpoch);
    if (log.firstOrNull != null &&
        log.first.time < range.start.millisecondsSinceEpoch &&
        startIndex > 0 &&
        startIndex < log.length) {
      final prev = log[startIndex - 1];
      final next = log[startIndex];
      num interpolatedValue = prev.value +
          (next.value - prev.value) * ((range.start.millisecondsSinceEpoch - prev.time) / (next.time - prev.time));
      if (T.toString() == "int") {
        interpolatedValue = (interpolatedValue as double).round();
      }
      log.insert(startIndex, TimestampValue<T>(range.start.millisecondsSinceEpoch, interpolatedValue as T));
    }
    final endIndex = bisect_left(log.map((e) => e.time).toList(), range.end.millisecondsSinceEpoch);
    if (log.lastOrNull != null &&
        log.last.time > range.end.millisecondsSinceEpoch &&
        endIndex > 0 &&
        endIndex < log.length) {
      final prev = log[endIndex - 1];
      final next = log[endIndex];
      num interpolatedValue = prev.value +
          (next.value - prev.value) * ((range.end.millisecondsSinceEpoch - prev.time) / (next.time - prev.time));
      if (T.toString() == "int") {
        interpolatedValue = (interpolatedValue as double).round();
      }
      log.insert(endIndex, TimestampValue<T>(range.end.millisecondsSinceEpoch, interpolatedValue as T));
    }
    // Trim
    log.removeWhere((e) => e.time < range.start.millisecondsSinceEpoch || e.time > range.end.millisecondsSinceEpoch);
  }
}
