import 'package:flutter/material.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/util.dart';

class LogView with ChangeNotifier {
  late final FlightLog log;

  // --- Sample Range
  Range<int>? _sampleIndexRange;
  Range<int> get sampleIndexRange {
    if (_sampleIndexRange == null) {
      int start = log.timeToSampleIndex(_timeRange.start);
      int end = log.timeToSampleIndex(_timeRange.end) + 1;

      // validate
      if (start < 0) {
        start = 0;
      }
      if (end > log.samples.length) {
        end = log.samples.length;
      }
      if (end <= start) {
        if (end < log.samples.length - 1) {
          end = start + 1;
        } else {
          start = end - 1;
        }
      }

      _sampleIndexRange = Range(start, end);
    }
    return _sampleIndexRange!;
  }

  // --- G-Force range
  Range<int>? _gForceIndexRange;
  Range<int> get gForceIndexRange {
    if (_gForceIndexRange == null) {
      int start = log.timeToGForceSampleIndex(_timeRange.start);
      int end = log.timeToGForceSampleIndex(_timeRange.end) + 1;

      // validate
      if (start < 0) {
        start = 0;
      }
      if (end > log.gForceSamples.length) {
        end = log.gForceSamples.length;
      }
      if (end <= start) {
        if (end < log.gForceSamples.length - 1) {
          end = start + 1;
        } else {
          start = end - 1;
        }
      }
      _gForceIndexRange = Range(start, end);
    }
    return _gForceIndexRange!;
  }

  List<Geo> get samples {
    return log.samples.sublist(sampleIndexRange.start, sampleIndexRange.end);
  }

  List<TimestampDouble> get gForceSamples {
    return log.gForceSamples.sublist(gForceIndexRange.start, gForceIndexRange.end);
  }

  late DateTimeRange _timeRange;
  DateTimeRange get timeRange => _timeRange;
  set timeRange(DateTimeRange newRange) {
    _timeRange = newRange;
    _gForceIndexRange = null;
    _sampleIndexRange = null;
    notifyListeners();
  }

  LogView(this.log) {
    _timeRange = log.timeRange!;
  }
}
