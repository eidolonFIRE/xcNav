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

  /// Copy of the [input, output] points, sorted by input.
  List<List<T>> get points => _sensorLUT.map((e) => List<T>.from(e)).toList();

  /// Parse from a list of [input, output] pairs. Returns null if the data isn't a valid curve.
  static MapValue<double>? fromJson(dynamic data) {
    if (data is! List) return null;
    final List<List<double>> points = [];
    for (final each in data) {
      if (each is! List || each.length < 2) return null;
      final x = parseAsDouble(each[0]);
      final y = parseAsDouble(each[1]);
      if (x == null || y == null) return null;
      points.add([x, y]);
    }
    return MapValue.validate(points);
  }

  /// Sort points by input. Returns null if there are fewer than 2 points or duplicate inputs.
  static MapValue<double>? validate(List<List<double>> points) {
    if (points.length < 2) return null;
    final sorted = points.map((e) => List<double>.from(e)).toList()..sort((a, b) => a[0].compareTo(b[0]));
    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i][0] == sorted[i - 1][0]) return null;
    }
    return MapValue<double>(sorted);
  }

  List<List<T>> toJson() => points;

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

  MapValue<T>? calibration;

  /// Last value received, before calibration is applied.
  T? lastRawValue;

  BleLoggedValue({this.calibration});

  void addValue(T value, DateTime? timestamp) {
    lastRawValue = value;
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
