import 'dart:math';

import 'package:bisection/bisect.dart';
import 'package:flutter/material.dart';
import 'package:xcnav/douglas_peucker.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/util.dart';
import 'package:xcnav/datadog.dart' as dd;

class FuelReport {
  late final DateTime time;

  /// Liters
  late final double amount;

  FuelReport(this.time, this.amount);
  FuelReport.fromJson(Map<String, dynamic> data) {
    time = DateTime.fromMillisecondsSinceEpoch(data["time"]);
    amount = parseAsDouble(data["amount"]) ?? 0;
  }

  dynamic toJson() {
    return {"time": time.millisecondsSinceEpoch, "amount": amount};
  }
}

class FuelStat {
  /// Liters burned
  late final double amount;
  late final Duration durationTime;
  late final double durationDist;

  /// Liters / Hour
  late final double rate;

  /// Mileage (meters / liter)
  late final double mpl;
  late final double meanAlt;
  late final double meanSpd;
  late double altGained;

  FuelStat(this.amount, this.durationTime, this.durationDist, this.rate, this.mpl, this.meanAlt, this.meanSpd,
      this.altGained);

  bool get isValid => amount > 0 && durationTime.inMilliseconds > 0;

  FuelStat.fromSamples(FuelReport start, FuelReport end, List<Geo> samples) {
    amount = start.amount - end.amount;
    durationTime = end.time.difference(start.time);
    rate = amount / (durationTime.inMilliseconds / const Duration(hours: 1).inMilliseconds);
    double tempDurationDist = 0;
    for (int i = 0; i < samples.length - 1; i++) {
      tempDurationDist = tempDurationDist + samples[i].distanceTo(samples[i + 1]);
    }
    durationDist = tempDurationDist;
    mpl = durationDist / amount;
    meanAlt = samples.map((e) => e.alt).reduce((a, b) => a + b) / samples.length;
    meanSpd = samples.map((e) => e.spd).reduce((a, b) => a + b) / samples.length;

    altGained = 0;
    final values = douglasPeucker(samples.map((e) => e.alt).toList(), 3);
    for (int t = 0; t < values.length - 1; t++) {
      altGained = altGained + max(0, values[t + 1] - values[t]);
    }
  }

  /// Given the last known fuel level, estimate remaining fuel at a timestamp
  double extrapolateToTime(FuelReport lastReport, DateTime time) {
    final amount = lastReport.amount - rate * time.difference(lastReport.time).inSeconds / 3600;
    return amount;
  }

  /// Given the last known fuel level, estimate remaining endurance.
  /// If `from` is not supplied, it will use the DateTime of the `lastReport`.
  Duration extrapolateEndurance(FuelReport lastReport, {DateTime? from}) {
    final durFromReport = Duration(seconds: (lastReport.amount / rate * 3600).round());
    return durFromReport - (from != null ? from.difference(lastReport.time) : Duration.zero);
  }

  /// Stats are combined with weight; biasing towards the longest duration
  FuelStat operator +(FuelStat other) {
    final ratio = durationTime.inMilliseconds / (durationTime.inMilliseconds + other.durationTime.inMilliseconds);
    double weight(a, b) {
      return a * ratio + (1 - ratio) * b;
    }

    final newAmount = amount + other.amount;
    final newDurationTime = durationTime + other.durationTime;
    final newDurationDist = durationDist + other.durationDist;
    final newRate = weight(rate, other.rate);
    final newMpL = weight(mpl, other.mpl);

    final newMeanAlt = weight(meanAlt, other.meanAlt);
    final newMeanSpd = weight(meanSpd, other.meanSpd);
    final newAltGained = altGained + other.altGained;
    return FuelStat(newAmount, newDurationTime, newDurationDist, newRate, newMpL, newMeanAlt, newMeanSpd, newAltGained);
  }
}

class FuelReportController with ChangeNotifier {
  final List<FuelReport> _fuelReports = [];
  List<FuelReport> get fuelReports => _fuelReports;

  FuelReportController({Iterable<FuelReport> fuelReports = const []}) {
    _fuelReports.addAll(fuelReports);
  }

  FuelStat? _sumFuelStat;
  FuelStat? getSumFuelStat(List<Geo> recordGeo) {
    if (_sumFuelStat == null && getFuelStats(recordGeo).isNotEmpty) {
      debugPrint("Building sumFuelStats");
      // Only use valid stats.
      final temp = _fuelStats!.where((e) => e.isValid).toList();
      if (temp.isNotEmpty) {
        _sumFuelStat = temp.reduce((a, b) => a + b);
      }
    }
    return _sumFuelStat;
  }

  List<FuelStat>? _fuelStats = [];
  List<FuelStat> getFuelStats(List<Geo> recordGeo) {
    if (_fuelStats == null) {
      _fuelStats = [];

      debugPrint("Building fuelStats");

      // Rebuild the stats
      for (int index = 0; index < _fuelReports.length - 1; index++) {
        final a = _fuelReports[index];
        final b = _fuelReports[index + 1];
        final newStat = FuelStat.fromSamples(
            a,
            b,
            recordGeo.sublist(nearestIndex(recordGeo.map((e) => e.time).toList(), a.time.millisecondsSinceEpoch),
                nearestIndex(recordGeo.map((e) => e.time).toList(), b.time.millisecondsSinceEpoch) + 1));
        // this will even include stats that are invalid.
        _fuelStats!.add(newStat);
      }
    }

    return _fuelStats!;
  }

  void resetFuelStatCache() {
    _fuelStats = null;
    _sumFuelStat = null;
  }

  void removeFuelReport(int index) {
    _fuelReports.removeAt(index);
    resetFuelStatCache();
  }

  /// Find overlapping fuel report.
  /// If the time is close to two reports, the earlier index will be returned.
  /// Null is returned if no matches within tolerance are found.
  int? findFuelReportIndex(DateTime time, {Duration tolerance = const Duration(minutes: 5)}) {
    final index =
        bisect_left<int>(_fuelReports.map((e) => e.time.millisecondsSinceEpoch).toList(), time.millisecondsSinceEpoch);
    if (index > 0 && _fuelReports[index - 1].time.difference(time).abs().compareTo(tolerance) < 1) {
      return index - 1;
    } else if (index < _fuelReports.length &&
        _fuelReports[index].time.difference(time).abs().compareTo(tolerance) < 1) {
      return index;
    } else {
      return null;
    }
  }

  /// Insert a fuel report into the sorted list.
  /// If the new report is within tolerance of another report, it will be replaced.
  /// If the amount is null, the report will be removed.
  void insertFuelReport(DateTime time, double? amount, {Duration tolerance = const Duration(minutes: 2)}) {
    final overwriteIndex = findFuelReportIndex(time, tolerance: tolerance);

    if (overwriteIndex != null) {
      removeFuelReport(overwriteIndex);
      if (amount != null) {
        insertFuelReport(time, amount);
      }
    } else {
      if (amount != null) {
        // Insert new
        final insertIndex = bisect_left<int>(
            _fuelReports.map((e) => e.time.millisecondsSinceEpoch).toList(), time.millisecondsSinceEpoch);
        _fuelReports.insert(insertIndex, FuelReport(time, amount));
      }
    }
    resetFuelStatCache();
  }

  void updateFuelReport(int index, double amount, {DateTime? time}) {
    if (index < 0 || index >= _fuelReports.length) {
      dd.warn(
        "FuelReportController.updateFuelReport: index out of range",
        attributes: {"index": index, "length": _fuelReports.length},
      );
      return;
    }
    removeFuelReport(index);
    insertFuelReport(time ?? _fuelReports[index].time, amount);
    resetFuelStatCache();
  }

  void cropReportsToTimeRange(DateTimeRange timeRange) {
    bool newContainsTime(DateTime time) {
      final t = time.millisecondsSinceEpoch;
      final s = timeRange.start.millisecondsSinceEpoch;
      final e = timeRange.end.millisecondsSinceEpoch;
      return t <= e && t >= s;
    }

    final newFuelReports = _fuelReports.where((each) => newContainsTime(each.time)).toList();
    for (int t = 0; t < _fuelReports.length - 1; t++) {
      final first = _fuelReports[t];
      final second = _fuelReports[t + 1];

      // first is not contained, but second is.
      if (!newContainsTime(first.time) && newContainsTime(second.time) && second.time.isAfter(timeRange.start)) {
        // insert new at beginning
        final interpValue = inverseInterpTime(first.time, second.time, timeRange.start);
        newFuelReports.insert(
            0, FuelReport(timeRange.start, first.amount * (1 - interpValue) + second.amount * interpValue));
      }

      // first is contained, but second is not.
      if (newContainsTime(first.time) && !newContainsTime(second.time) && first.time.isBefore(timeRange.end)) {
        // insert new at end
        final interpValue = inverseInterpTime(first.time, second.time, timeRange.end);
        newFuelReports.add(FuelReport(timeRange.end, first.amount * (1 - interpValue) + second.amount * interpValue));
      }
    }
    _fuelReports
      ..clear()
      ..addAll(newFuelReports);
    resetFuelStatCache();
  }
}
