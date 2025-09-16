import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:bisection/bisect.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/gaussian_filter.dart';
import 'package:xml/xml.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'package:intl/intl.dart';

import 'package:xcnav/util.dart';

import 'package:xcnav/douglas_peucker.dart';

import 'package:xcnav/datadog.dart';
import 'package:xcnav/log_store.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/models/gear.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/g_force.dart';

class FlightLog {
  late final bool goodFile;
  bool unsaved = true;

  String? _filename;
  late List<Geo> samples;
  late final List<Waypoint> waypoints;

  late List<TimestampDouble> gForceSamples;

  late final String? rawJson;
  late final Map<String, dynamic>? bleDevicesJson;

  late List<FuelReport> _fuelReports;
  List<FuelReport> get fuelReports => _fuelReports;

  String get title {
    if (goodFile) {
      return DateFormat("MMM d - yyyy").format(DateTime.fromMillisecondsSinceEpoch(samples.first.time));
    } else {
      return "Broken Log! $filename";
    }
  }

  // =========================================
  String? _imported;

  /// If log is imported from another program, which one.
  String? get imported => _imported;

  // =========================================
  int? _timezone;

  /// Timezone offset
  int? get timezone => _timezone;

  // =========================================
  Gear? _gear;
  Gear? get gear => _gear;
  set gear(newGear) {
    _gear = newGear;
    unsaved = true;
  }

  // =========================================
  DateTimeRange? get timeRange {
    if (samples.isEmpty) {
      return null;
    } else {
      return DateTimeRange(start: startTime!, end: endTime!);
    }
  }

  // =========================================
  Duration? _durationTime;
  Duration get durationTime {
    return _durationTime ??=
        samples.isNotEmpty ? Duration(milliseconds: samples.last.time - samples.first.time) : const Duration();
  }

  // =========================================
  double? _durationDist;

  /// Meters
  double get durationDist {
    if (_durationDist == null) {
      _durationDist = 0;
      for (int i = 0; i < samples.length - 1; i++) {
        _durationDist = _durationDist! + samples[i].distanceTo(samples[i + 1]);
      }
    }
    return _durationDist!;
  }

  // =========================================
  double? _maxAlt;

  /// Meters
  double get maxAlt {
    if (_maxAlt == null) {
      if (samples.length > 1) {
        _maxAlt = samples.reduce((a, b) => a.alt > b.alt ? a : b).alt;
      } else {
        _maxAlt = samples.first.alt;
      }
    }
    return _maxAlt!;
  }

  // =========================================
  double? _bestClimb;

  /// Fastest climb sustained
  double get bestClimb {
    if (_bestClimb == null) {
      // --- Sliding window search for bestClimb
      int left = 0;
      int right = 0;
      _bestClimb = 0;
      while (left < samples.length) {
        // grow window
        while (right < samples.length &&
            Duration(milliseconds: samples[right].time - samples[left].time) < const Duration(seconds: 30)) {
          right++;
        }

        if (right >= samples.length - 1) {
          // Not enough samples to get a best 1min climb
          break;
        }

        // check max
        double newClimb = (samples[right].alt - samples[left].alt) / (samples[right].time - samples[left].time) * 1000;
        if (newClimb > _bestClimb!) {
          _bestClimb = newClimb;
        }

        // scoot window
        left++;
      }
    }
    return _bestClimb!;
  }

  // =========================================
  double? _meanSpd;

  /// `m/s`
  double get meanSpd {
    if (_meanSpd == null) {
      if (durationTime.inMilliseconds > 0) {
        _meanSpd = durationDist / durationTime.inSeconds;
      } else {
        _meanSpd = 0;
      }
    }
    return _meanSpd!;
  }

  // =========================================
  String? get filename => _filename;
  DateTime? get startTime => samples.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(samples.first.time);
  DateTime? get endTime => samples.isEmpty ? null : DateTime.fromMillisecondsSinceEpoch(samples.last.time);

  /// In original timezone
  DateTime? get startTimeOriginal {
    if (timezone != null) {
      // timezone adjusted
      return startTime?.add(DateTime.now().timeZoneOffset).subtract(Duration(hours: timezone!));
    } else {
      return startTime;
    }
  }

  /// In original timezone
  DateTime? get endTimeOriginal {
    if (timezone != null) {
      // timezone adjusted
      return endTime?.add(DateTime.now().timeZoneOffset).subtract(Duration(hours: timezone!));
    } else {
      return endTime;
    }
  }

  // =========================================
  // int speedHistOffset = 0;
  // List<int>? _speedHist;
  // List<int> get speedHist {
  //   _speedHist ??= speedHistogram(0, samples.length);

  //   return _speedHist!;
  // }

  int? _speedHistMaxIndex;
  int get speedHistMaxIndex {
    if (_speedHistMaxIndex == null) {
      final fullHist = speedHistogram(0, samples.length);
      _speedHistMaxIndex = fullHist.values.length + fullHist.range.start;
    }
    return _speedHistMaxIndex!;
  }

  HistogramData<int> speedHistogram(int start, int end, {int? width}) {
    List<int> values = List.filled(max(width ?? 0, 13), 0, growable: true);

    // Build speed histogram
    for (final each in samples.sublist(start, end)) {
      final index = (each.spd * 2).round();

      // Auto grow
      if (width == null && values.length <= index) {
        values.addAll(List.filled(index - values.length, 0));
      }
      if (index < values.length && index > 0) {
        values[index]++;
      }
    }

    if (width == null) {
      // Trim low count from outliers. Removes outliers and cleans up the chart.
      final int highest = values.reduce(max);

      int clipEnd = values.length - 1;
      while (clipEnd >= 0) {
        if (values[clipEnd] < (highest / 20 + 1)) {
        } else {
          break;
        }
        clipEnd--;
      }
      clipEnd = min(values.length, (clipEnd / 5).ceil() * 5 + 1);
      values = values.sublist(0, clipEnd);
    }

    // int clipStart = 0;
    // while (clipStart < values.length) {
    //   if (values[clipStart] < (highest / 50 + 1)) {
    //     clipStart++;
    //   } else {
    //     break;
    //   }
    //   clipStart++;
    // }

    // clipStart = (clipStart / 5).floor() * 5;

    return HistogramData(Range(0, values.length), values);
  }

  // =========================================
  double? _altGained;

  /// Meters
  double get altGained {
    if (_altGained == null) {
      _altGained = 0;
      final values = douglasPeucker(samples.map((e) => e.alt).toList(), 3);
      for (int t = 0; t < values.length - 1; t++) {
        _altGained = _altGained! + max(0, values[t + 1] - values[t]);
      }
    }
    return _altGained!;
  }

  // =========================================
  LatLngBounds getBounds({double pad = 0.2}) {
    return padLatLngBounds(LatLngBounds.fromPoints(samples.map((e) => e.latlng).toList()), pad);
  }

  // =========================================
  List<TimestampDouble>? _varioLogSmoothed;

  /// Smoothed, calculated vario log from recorded elevation
  List<TimestampDouble> get varioLogSmoothed {
    if (_varioLogSmoothed == null) {
      final altLog =
          gaussianFilterTimestamped(samples.map((e) => TimestampDouble(e.time, e.alt)).toList(), 3, 3).toList();
      _varioLogSmoothed = altLog
          .convolve((a, b) => b.time > a.time + 10
              ? TimestampDouble(((a.time + b.time) / 2).round(), (b.value - a.value) / (b.time - a.time) * 1000)
              : null)
          .toList();
    }
    return _varioLogSmoothed!;
  }

  // =========================================
  FuelStat? _sumFuelStat;
  FuelStat? get sumFuelStat {
    if (fuelStats.isEmpty) return null;
    _sumFuelStat ??= fuelStats.reduce((a, b) => a + b);
    return _sumFuelStat;
  }

  // =========================================
  List<FuelStat>? _fuelStats;
  List<FuelStat> get fuelStats {
    if (_fuelStats == null) {
      _fuelStats = [];

      if (goodFile) {
        for (int t = 0; t < _fuelReports.length - 1; t++) {
          // NOTE: if fuel amount stays the same, segment is dropped
          // if (_fuelReports[t].amount != _fuelReports[t + 1].amount) {
          _fuelStats!.add(FuelStat.fromSamples(
              _fuelReports[t],
              _fuelReports[t + 1],
              samples.sublist(
                  timeToSampleIndex(_fuelReports[t].time), timeToSampleIndex(_fuelReports[t + 1].time) + 1)));
          // }
        }
      }
    }

    return _fuelStats!;
  }

  // =========================================
  List<GForceEvent>? _gForceEvents;
  List<GForceEvent> get gForceEvents {
    if (_gForceEvents == null) {
      late List<GForceSlice> slices;
      slices = getGForceSlices(samples: gForceSamples, high: 1.5);
      if (slices.length > 15) {
        slices = getGForceSlices(samples: gForceSamples, high: 2);
        if (slices.length > 15) {
          slices = getGForceSlices(samples: gForceSamples, high: 2.5);
        }
      } else if (slices.length < 3) {
        slices = getGForceSlices(samples: gForceSamples, high: 1.2);
        if (slices.length > 15) {
          slices = getGForceSlices(samples: gForceSamples, high: 1.4);
        }
      }
      _gForceEvents = slices.map((e) {
        final first = samples[timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(gForceSamples[e.start].time))];
        final last = samples[timeToSampleIndex(DateTime.fromMillisecondsSinceEpoch(gForceSamples[e.end].time))];
        final center = samples[timeToSampleIndex(
            DateTime.fromMillisecondsSinceEpoch((gForceSamples[e.start].time + gForceSamples[e.end].time) ~/ 2))];
        return GForceEvent(
            e,
            DateTimeRange(
                start: DateTime.fromMillisecondsSinceEpoch(first.time),
                end: DateTime.fromMillisecondsSinceEpoch(last.time)),
            center);
      }).toList();
    }

    return _gForceEvents!;
  }

  // =========================================
  Duration? _durationOver2G;

  /// Duration of flight time spent over 2G in force.
  Duration get durationOver2G {
    if (_durationOver2G == null) {
      int ms = 0;
      for (int i = 1; i < gForceSamples.length - 1; i++) {
        if (gForceSamples[i].value > 2.0) {
          final start = (gForceSamples[i - 1].time + gForceSamples[i].time) / 2;
          final end = (gForceSamples[i + 1].time + gForceSamples[i].time) / 2;
          ms += (end - start).round();
        }
      }
      _durationOver2G = Duration(milliseconds: ms);
    }
    return _durationOver2G!;
  }

  // =========================================
  /// Peak instantanious G-force recorded
  /// If event index not given, will return max value for the whole timeline
  double maxG({int? index}) {
    if (gForceSamples.isEmpty) {
      return 1;
    }
    if (index != null) {
      final event = gForceSamples
          .sublist(gForceEvents[index].gForceIndeces.start, gForceEvents[index].gForceIndeces.end)
          .toList();
      return event.map((a) => a.value).max;
    } else {
      return gForceSamples.map((a) => a.value).max;
    }
  }

  // =========================================
  void resetFuelStatCache() {
    _fuelStats = null;
    _sumFuelStat = null;
  }

  /// Does this flight log contain this timestamp?
  bool containsTime(DateTime time) {
    return time == startTime || time == endTime || (time.isAfter(startTime!) && time.isBefore(endTime!));
  }

  /// Simple update of an existing fuel report
  void updateFuelReport(int index, double amount, {DateTime? time}) {
    if (index >= 0 && index < _fuelReports.length) {
      _fuelReports[index] = FuelReport(time ?? _fuelReports[index].time, amount);
      resetFuelStatCache();
      unsaved = true;
    }
  }

  /// Find overlapping fuel report.
  /// If the time is close to two reports, the earlier index will be returned.
  /// Null is returned if no matches within tolerance are found.
  int? findFuelReportIndex(DateTime time, {Duration tolerance = const Duration(minutes: 5)}) {
    final index =
        bisect_left<int>(fuelReports.map((e) => e.time.millisecondsSinceEpoch).toList(), time.millisecondsSinceEpoch);
    if (index > 0 && fuelReports[index - 1].time.difference(time).abs().compareTo(tolerance) < 1) {
      return index - 1;
    } else if (index < fuelReports.length && fuelReports[index].time.difference(time).abs().compareTo(tolerance) < 1) {
      return index;
    } else {
      return null;
    }
  }

  /// Insert a fuel report into the sorted list.
  /// If the new report is within tolerance of another report, it will be replaced.
  void insertFuelReport(DateTime time, double? amount,
      {Duration tolerance = const Duration(minutes: 5), useNewTime = true}) {
    final overwriteIndex = findFuelReportIndex(time, tolerance: tolerance);

    if (overwriteIndex != null) {
      if (amount != null) {
        // edit existing
        fuelReports[overwriteIndex] = FuelReport(useNewTime ? time : fuelReports[overwriteIndex].time, amount);
      } else {
        // remove existing
        fuelReports.removeAt(overwriteIndex);
      }
    } else {
      if (amount != null) {
        // Insert new
        final insertIndex = bisect_left<int>(
            fuelReports.map((e) => e.time.millisecondsSinceEpoch).toList(), time.millisecondsSinceEpoch);
        fuelReports.insert(insertIndex, FuelReport(time, amount));
      }
    }

    // reset internal calculations
    resetFuelStatCache();
    unsaved = true;
  }

  void removeFuelReport(int index) {
    _fuelReports.removeAt(index);
    resetFuelStatCache();
    unsaved = true;
  }

  // =========================================
  /// Return true if success
  Future<bool> save({Map<String, dynamic>? additionalJson}) async {
    _filename ??=
        "${(await getApplicationDocumentsDirectory()).path}/flight_logs/${startTime!.millisecondsSinceEpoch}.json";
    debugPrint("Saving FlightLog $filename");
    logStore.updateLog(_filename!, this);
    Completer<bool> completer = Completer();
    Map<String, dynamic> logJson = toJson();
    if (additionalJson != null) {
      logJson.addAll(additionalJson);
    }
    final encoded = jsonEncode(logJson);
    debugPrint(encoded);
    saveFileToAppDocs(filename: filename, data: encoded).then((value) {
      unsaved = false;
      completer.complete(true);
    });
    return completer.future;
  }

  Future<String> export({String fileType = "json"}) async {
    String outFilename = "";
    if (samples.isNotEmpty) {
      outFilename = DateFormat("yyyy_MM_dd_hh_mm").format(DateTime.fromMillisecondsSinceEpoch(samples[0].time));
    } else {
      outFilename = p.basenameWithoutExtension(filename ?? DateFormat("yyyy_MM_dd_hh_mm").format(DateTime.now()));
    }
    Directory path =
        (Platform.isIOS ? await getApplicationDocumentsDirectory() : Directory('/storage/emulated/0/Documents'));

    final outFile = File("${path.path}/xcNav_$fileType/$outFilename.$fileType");
    await outFile.create(recursive: true);
    await outFile.writeAsString(
        fileType == "json" ? (rawJson ?? jsonEncode(toJson())) : (fileType == "kml" ? toKML() : toGPX()));
    return outFile.path;
  }

  int compareTo(FlightLog other) {
    if (goodFile && other.goodFile) {
      return other.startTime!.compareTo(startTime!);
    } else {
      return (other.filename ?? "").compareTo(filename ?? "");
    }
  }

  /// Find the nearest sample index
  int timeToSampleIndex(DateTime time) {
    return nearestIndex(samples.map((e) => e.time).toList(), time.millisecondsSinceEpoch);
  }

  /// Return a copy of this log with a trimmed timeline.
  /// Fuel reports will be interpolated in some cases
  FlightLog cropLog(Range<int> index) {
    final newRange = DateTimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(samples[index.start].time),
        end: DateTime.fromMillisecondsSinceEpoch(samples[index.end - 1].time));

    double interpTime(DateTime start, DateTime end, DateTime i) {
      final dur = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      return (i.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / dur.toDouble();
    }

    bool newContainsTime(DateTime time) {
      return time == newRange.start ||
          time == newRange.end ||
          (time.isAfter(newRange.start) && time.isBefore(newRange.end));
    }

    final newFuelReports = fuelReports.toList();
    for (int t = 0; t < fuelReports.length - 1; t++) {
      final first = fuelReports[t];
      final second = fuelReports[t + 1];

      // first is not contained, but second is.
      if (!newContainsTime(first.time) && newContainsTime(second.time) && second.time.isAfter(newRange.start)) {
        // insert new at beginning
        final interpValue = interpTime(first.time, second.time, newRange.start);
        newFuelReports.insert(
            0, FuelReport(newRange.start, first.amount * (1 - interpValue) + second.amount * interpValue));
      }

      // first is contained, but second is not.
      if (newContainsTime(first.time) && !newContainsTime(second.time) && first.time.isBefore(newRange.end)) {
        // insert new at end
        final interpValue = interpTime(first.time, second.time, newRange.end);
        newFuelReports.add(FuelReport(newRange.end, first.amount * (1 - interpValue) + second.amount * interpValue));
      }
    }

    final newSamples = samples.sublist(index.start, index.end).toList();

    final newGForceSamples =
        gForceSamples.where((e) => e.time >= newSamples.first.time && e.time <= newSamples.last.time).toList();

    final newLog = FlightLog(
        samples: newSamples,
        gForceSamples: newGForceSamples,
        waypoints: waypoints,
        fuelReports: newFuelReports,
        gear: gear,
        filename: filename,
        imported: _imported,
        timezone: _timezone);
    return newLog;
  }

  void _calculateSpeeds() {
    // --- Fill in speeds
    for (int t = 0; t < samples.length - 1; t++) {
      if (samples[t + 1].spd == 0 && samples[t].time < samples[t + 1].time) {
        final double dist = latlngCalc.distance(samples[t].latlng, samples[t + 1].latlng);
        samples[t + 1].spd = dist / (samples[t + 1].time - samples[t].time) * 1000;
      }
    }
  }

  void _calculateHdgs() {
    // --- Fill in headings
    for (int t = 0; t < samples.length - 1; t++) {
      if (samples[t + 1].hdg == 0 && samples[t].time < samples[t + 1].time) {
        samples[t + 1].hdg = latlngCalc.bearing(samples[t].latlng, samples[t + 1].latlng) / 180 * pi;
      }
    }
  }

  FlightLog(
      {this.samples = const [],
      this.waypoints = const [],
      this.gForceSamples = const [],
      String? imported,
      int? timezone,
      List<FuelReport> fuelReports = const [],
      Gear? gear,
      String? filename,
      this.bleDevicesJson}) {
    if (samples.isEmpty) {
      goodFile = false;
      throw "Creating FlightLog without samples";
    }
    _timezone = timezone;
    _imported = imported;
    _filename = filename;
    _fuelReports = fuelReports.where((each) => containsTime(each.time)).toList();
    _gear = gear;
    gForceSamples = gForceSamples.where((e) => containsTime(DateTime.fromMillisecondsSinceEpoch(e.time))).toList();
    goodFile = true;
  }

  FlightLog.fromJson(String? filename, Map<String, dynamic> data, {this.rawJson}) {
    _filename = filename;
    unsaved = false;

    try {
      bleDevicesJson = data["ble_devices"];

      // --- Misc
      final maybeImported = data["imported"];
      if (maybeImported != null) {
        _imported = data["imported"];
      }

      final maybeTimezone = data["timezone"];
      if (maybeTimezone != null) {
        _timezone = data["timezone"];
      }

      // --- Parse Gear
      final rawGear = data["gear"];
      if (rawGear != null) {
        _gear = Gear.fromJson(data["gear"]);
      }

      // --- Parse Samples
      List<dynamic> dataSamples = data["samples"];
      samples = dataSamples.map((e) => Geo.fromJson(e)).toList();

      if (samples.isEmpty) {
        throw "No samples in log";
      }

      // --- Try load g-force samples
      gForceSamples = [];
      if (data.containsKey("gForceSamples")) {
        final List<dynamic> gSamples = data["gForceSamples"];
        for (int t = 0; t < gSamples.length; t += 2) {
          gForceSamples.add(
              TimestampDouble((gSamples[t] as int) + startTime!.millisecondsSinceEpoch, gSamples[t + 1] as double));
        }
      }

      _calculateSpeeds();

      // --- Try load waypoints
      if (data.containsKey("waypoints")) {
        waypoints = (data["waypoints"] as List<dynamic>)
            .map((each) => Waypoint.fromJson(each))
            .where((element) => element.validate())
            .toList();
      } else {
        waypoints = [];
      }

      // --- Try loading fuel reports
      if (data.containsKey("fuelReports")) {
        _fuelReports = (data["fuelReports"] as List<dynamic>).map((e) => FuelReport.fromJson(e)).toList();
      } else {
        _fuelReports = [];
      }

      goodFile = true;
    } catch (e, trace) {
      samples = [];
      waypoints = [];
      gForceSamples = [];
      goodFile = false;
      error("Broken FlightLog File",
          errorMessage: e.toString(),
          errorStackTrace: trace,
          attributes: {"filename": filename, "dataLength": rawJson?.length});
    }
  }

  FlightLog.fromIGC(String data, {this.rawJson}) {
    // Spec: https://xp-soaring.github.io/igc_file_format/index.html
    unsaved = false;
    samples = [];

    DateTime? dateOffset;

    // These are not supported in IGC
    _fuelReports = [];
    gForceSamples = [];
    waypoints = [];
    bleDevicesJson = null;

    try {
      for (final line in data.split("\n")) {
        // parse each line
        if (RegExp(r"HFDTE[0-9]+").firstMatch(line) != null) {
          // (HFDTEDDMMYY) UTC date this file was recorded
          dateOffset = DateTime(int.parse(line.substring(9, 11)) + 2000, int.parse(line.substring(7, 9)),
              int.parse(line.substring(5, 7)));
        } else if (line.startsWith("HFTZNTIMEZONE:")) {
          // Timezone offset
          _timezone = int.parse(line.substring(("HFTZNTIMEZONE:").length));
          assert(dateOffset != null);
          dateOffset!.subtract(Duration(hours: timezone!));
        } else if (line.startsWith("HFGTYGLIDERTYPE:")) {
          // Glider type
          gear ??= Gear();
          gear!.wingMakeModel = line.substring(("HFGTYGLIDERTYPE:").length);
        } else if (line.startsWith("HFGIDGLIDERID:")) {
          // Glider ID (tail number)
          gear ??= Gear();
          gear!.other = line.substring(("HFGIDGLIDERID:").length);
        } else if (line.startsWith("HFFTYFRTYPE:")) {
          // Logger free-text manufacturer and model
          _imported = line.substring(("HFFTYFRTYPE:").length);
        } else if (line.startsWith("B")) {
          // Geo

          // BHH MM SS DD MMMMM N DDD MMMMM E V PPPPP GGGGG AAA SS NNN RRR

          final maybeLat = RegExp(r"([\d]{2})([\d]{5})(N|S)").firstMatch(line);
          assert(maybeLat != null);
          final lat = (double.parse(maybeLat!.group(1)!) + double.parse(maybeLat.group(2)!) / 60000.0) *
              (maybeLat.group(3) == "N" ? 1 : -1);

          final maybeLng = RegExp(r"([\d]{3})([\d]{5})(E|W)").firstMatch(line);
          assert(maybeLng != null);
          final lng = (double.parse(maybeLng!.group(1)!) + double.parse(maybeLng.group(2)!) / 60000.0) *
              (maybeLng.group(3) == "E" ? 1 : -1);

          assert(lat.abs() <= 90);
          assert(lng <= 360);
          assert(lng >= -180);

          final alt = double.parse(line.substring(30, 30 + 5));

          assert(dateOffset != null);
          final newGeo = Geo(
              lat: lat,
              lng: lng,
              alt: alt,
              timestamp: dateOffset!
                  .add(Duration(
                      hours: int.parse(line.substring(1, 3)),
                      minutes: int.parse(line.substring(3, 5)),
                      seconds: int.parse(line.substring(5, 7))))
                  .millisecondsSinceEpoch);
          // debugPrint("Geo ${newGeo.lat}, ${newGeo.lng}, ${newGeo.alt}");

          if (samples.isEmpty || newGeo.time > samples.last.time) {
            samples.add(newGeo);
          }
        }
      }

      if (samples.isEmpty) {
        throw "No samples in log";
      }

      _calculateSpeeds();
      _calculateHdgs();

      goodFile = true;
    } catch (e, trace) {
      samples = [];
      goodFile = false;
      error("Broken Import",
          errorMessage: e.toString(),
          errorStackTrace: trace,
          attributes: {"filename": filename, "dataLength": rawJson?.length});
    }
  }

  Map<String, dynamic> toJson() {
    // Flatten gForceSamples to 1D array for more compact json string
    final List<num> gSamples = [];
    // Only g-force samples within start-end timestamps will be saved
    for (final each in gForceSamples.where((a) => containsTime(DateTime.fromMillisecondsSinceEpoch(a.time)))) {
      gSamples.add(each.time - startTime!.millisecondsSinceEpoch);
      gSamples.add(roundToDigits(each.value, 2));
    }
    final dict = {
      "xcNavVersion": "${version.version}-(${version.buildNumber})",
      "samples": samples.map((e) => e.toJson()).toList(),
      "waypoints":
          waypoints.where((element) => (!element.ephemeral && element.validate())).map((e) => e.toJson()).toList(),
      "fuelReports": fuelReports.map((e) => e.toJson()).toList(),
      "gear": gear?.toJson(),
      "gForceSamples": gSamples
    };
    if (imported != null) {
      dict["imported"] = imported;
    }
    if (timezone != null) {
      dict["timezone"] = timezone;
    }
    if (bleDevicesJson != null) {
      dict["ble_devices"] = bleDevicesJson;
    }
    return dict;
  }

  String toKML() {
    // Convert python code from here: https://github.com/eidolonFIRE/gps_tools/blob/master/gps_tools.py#L261

    const polyColor = "7f0f0f0f";

    // generate pallet of styles
    const numStyles = 1;
    List<String> styles = [];
    for (int i = 0; i < numStyles; i++) {
      final String lineColor = "ff${colorWheel(-i / (max(1, numStyles - 1)) * 2 / 3 + 1 / 3)}";
      styles.add("""<Style id="style$i">
    <LineStyle>
    <color>$lineColor</color>
    <width>4</width>
    </LineStyle>
    <PolyStyle>
    <color>$polyColor</color>
    <outline>0</outline>
    </PolyStyle>
    </Style>""");
    }

    List<String> linestrings = [];
    List<String> waypointStrings = [];

    // assemble kml point list
    List<String> points = samples.map((p) => "${p.lng},${p.lat},${p.alt}").toList();
    final pointsString = points.join("\n");

    // select line style (color) based on the segment's average speed
    linestrings.add("""<Placemark>
    <name>MyPath</name>
    <styleUrl>#style0</styleUrl>
    <LineString>
    <extrude>1</extrude>
    <tessellate>1</tessellate>
    <altitudeMode>absolute</altitudeMode>
    <coordinates>
    $pointsString
    </coordinates>
    </LineString>
    </Placemark>""");

    // waypoints - Points
    for (final waypoint in waypoints.where((element) => element.latlng.length == 1)) {
      waypointStrings.add("""<Placemark>
    <name>${waypoint.name}</name>
    <Point>
      <coordinates>${waypoint.latlng.first.longitude},${waypoint.latlng.first.latitude},0</coordinates>
    </Point>
    </Placemark>""");
    }

    // waypoints - Paths
    for (final waypoint in waypoints.where((element) => element.latlng.length > 1)) {
      final String lineColor = "${waypoint.color?.toRadixString(16).padLeft(6, "0") ?? 0}";
      styles.add("""<Style id="style_path_${waypoint.name}"> 
    <LineStyle>
    <color>$lineColor</color>
    <width>3</width>
    </LineStyle>
    <PolyStyle>
    <color>$polyColor</color>
    <outline>0</outline>
    </PolyStyle>
    </Style>""");

      waypointStrings.add("""<Placemark>
    <name>${waypoint.name}</name>
    <styleUrl>#style_path_${waypoint.name}</styleUrl>
    <LineString>
    <extrude>1</extrude>
    <tessellate>1</tessellate>
    <altitudeMode>clampToGround</altitudeMode>
    <coordinates>
    ${waypoint.latlng.map((p) => "${p.longitude},${p.latitude},0").toList().join("\n")}
    </coordinates>
    </LineString>
    </Placemark>""");
    }

    return """<?xml version="1.0"?>
    <kml xmlns="http://www.opengis.net/kml/2.2">
    <Document>
    ${styles.join("\n")}
    ${linestrings.join("\n")}
    ${waypointStrings.join("\n")}
    </Document>
    </kml>""";
  }

  String toGPX() {
    final builder = XmlBuilder();

    builder.processing("xml", 'version="1.0"');

    builder.element("gpx", attributes: {"creator": "xcNav"}, nest: () {
      builder.element("trk", nest: () {
        builder.element("name", nest: title);

        builder.element("trkseg", nest: () {
          for (final geo in samples) {
            builder.element("trkpt", attributes: {"lat": geo.lat.toString(), "lon": geo.lng.toString()}, nest: () {
              builder.element("ele", nest: geo.alt.toString());
              builder.element("time", nest: DateTime.fromMillisecondsSinceEpoch(geo.time).toIso8601String());
            });
          }
        });
      });
    });

    return builder.buildDocument().toString();
  }
}
