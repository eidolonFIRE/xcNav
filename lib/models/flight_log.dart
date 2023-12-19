import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:bisection/bisect.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/models/gear.dart';
import 'package:xml/xml.dart';

import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import 'package:xcnav/util.dart';
import 'package:xcnav/douglas_peucker.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/models/fuel_report.dart';

class FlightLog {
  late final bool goodFile;
  bool unsaved = true;

  String? _filename;
  late List<Geo> samples;
  late final List<Waypoint> waypoints;

  late final String? rawJson;

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
  Gear? _gear;
  Gear? get gear => _gear;
  set gear(newGear) {
    _gear = newGear;
    unsaved = true;
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

  /// Fastest climb sustained for 1min in `m/s`
  double get bestClimb {
    if (_bestClimb == null) {
      // --- Sliding window search for bestClimb
      int left = 0;
      int right = 0;
      _bestClimb = 0;
      while (left < samples.length) {
        // grow window
        while (right < samples.length &&
            Duration(milliseconds: samples[right].time - samples[left].time) < const Duration(seconds: 60)) {
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

  // =========================================
  int speedHistOffset = 0;
  List<int>? _speedHist;
  List<int> get speedHist {
    if (_speedHist == null) {
      _speedHist = [];

      // Build speed histogram
      for (final each in samples) {
        final index = unitConverters[UnitType.speed]!(each.spd).round();

        while (_speedHist!.length <= index) {
          // debugPrint("${_speedHist!.length} <= ${index}");
          _speedHist!.add(0);
        }

        _speedHist![index]++;
      }

      // Trim low count from outliers. Removes outliers and cleans up the chart.
      final int highest = _speedHist!.reduce(max);

      int t = _speedHist!.length - 1;
      while (t >= 0) {
        if (_speedHist!.last < (highest / 100 + 1)) {
          _speedHist!.removeLast();
        } else {
          break;
        }
        t--;
      }

      while (t < _speedHist!.length) {
        if (_speedHist!.first < (highest / 100 + 1)) {
          _speedHist!.removeAt(0);
          speedHistOffset++;
        } else {
          break;
        }
        t++;
      }
    }
    return _speedHist!;
  }

  // =========================================
  double? _altGained;

  /// Meters
  double get altGained {
    if (_altGained == null) {
      _altGained = 0;
      final values = douglasPeucker(samples.map((e) => e.alt).toList(), 3);
      debugPrint("Elev points reduced ${samples.length} => ${values.length}");
      for (int t = 0; t < values.length - 1; t++) {
        _altGained = _altGained! + max(0, values[t + 1] - values[t]);
      }
    }
    return _altGained!;
  }

  // =========================================
  FuelStat? _sumFuelStat;
  FuelStat? get sumFuelStat {
    if (fuelStats.isEmpty) return null;
    return _sumFuelStat ??= fuelStats.reduce((a, b) => a + b);
  }

  // =========================================
  List<FuelStat>? _fuelStats;
  List<FuelStat> get fuelStats {
    if (_fuelStats == null) {
      _fuelStats = [];

      if (goodFile && startTime != null) {
        for (int t = 0; t < _fuelReports.length - 1; t++) {
          // NOTE: if fuel amount stays the same or increases, segment is dropped
          if (_fuelReports[t].amount > _fuelReports[t + 1].amount) {
            _fuelStats!.add(FuelStat.fromSamples(
                _fuelReports[t],
                _fuelReports[t + 1],
                samples.sublist(
                    timeToSampleIndex(_fuelReports[t].time), timeToSampleIndex(_fuelReports[t + 1].time) + 1)));
          }
        }
      }
    }

    return _fuelStats!;
  }

  // =========================================
  LatLngBounds getBounds({double pad = 0.2}) {
    return padLatLngBounds(LatLngBounds.fromPoints(samples.map((e) => e.latlng).toList()), pad);
  }

  void resetFuelStatCache() {
    _fuelStats = null;
    _sumFuelStat = null;
  }

  bool containsTime(DateTime time) {
    return time == startTime || time == endTime || (time.isAfter(startTime!) && time.isBefore(endTime!));
  }

  bool insertFuelReport(double amount, DateTime time) {
    if (containsTime(time) && !_fuelReports.map((e) => e.time).contains(time) && amount >= 0) {
      _fuelReports.insert(
          bisect(_fuelReports.map((e) => e.time.millisecondsSinceEpoch).toList(), time.millisecondsSinceEpoch),
          FuelReport(time, amount));
      unsaved = true;
      resetFuelStatCache();
      return true;
    } else {
      // Fuel Report couldn't be added
      return false;
    }
  }

  void updateFuelReport(int index, double amount) {
    if (index >= 0 && index < _fuelReports.length) {
      _fuelReports[index] = FuelReport(_fuelReports[index].time, amount);
      resetFuelStatCache();
      unsaved = true;
    }
  }

  void removeFuelReport(int index) {
    _fuelReports.removeAt(index);
    resetFuelStatCache();
    unsaved = true;
  }

  // =========================================
  /// Return true if success
  Future<bool> save() async {
    _filename ??=
        "${(await getApplicationDocumentsDirectory()).path}/flight_logs/${startTime!.millisecondsSinceEpoch}.json";
    debugPrint("Saving FlightLog $filename");
    logStore.updateLog(_filename!, this);
    Completer<bool> completer = Completer();
    saveFileToAppDocs(filename: filename, data: toJson()).then((value) {
      unsaved = false;
      completer.complete(true);
    });
    return completer.future;
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
  FlightLog trimLog(int startIndex, int endIndex) {
    // insert new interpolated fuel reports

    final newStartTime = DateTime.fromMillisecondsSinceEpoch(samples[startIndex].time);
    final newEndTime = DateTime.fromMillisecondsSinceEpoch(samples[endIndex].time);

    double interpTime(DateTime start, DateTime end, DateTime i) {
      final dur = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
      return (i.millisecondsSinceEpoch - start.millisecondsSinceEpoch) / dur.toDouble();
    }

    bool newContainsTime(DateTime time) {
      return time == newStartTime || time == newEndTime || (time.isAfter(newStartTime) && time.isBefore(newEndTime));
    }

    final newFuelReports = fuelReports.toList();
    for (int t = 0; t < fuelReports.length - 1; t++) {
      final first = fuelReports[t];
      final second = fuelReports[t + 1];

      // first is not contained, but second is.
      if (!newContainsTime(first.time) && newContainsTime(second.time) && second.time.isAfter(newStartTime)) {
        // insert new at beginning
        final interpValue = interpTime(first.time, second.time, newStartTime);
        newFuelReports.insert(
            0, FuelReport(newStartTime, first.amount * (1 - interpValue) + second.amount * interpValue));
      }

      // first is contained, but second is not.
      if (newContainsTime(first.time) && !newContainsTime(second.time) && first.time.isBefore(newEndTime)) {
        // insert new at end
        final interpValue = interpTime(first.time, second.time, newEndTime);
        newFuelReports.add(FuelReport(newEndTime, first.amount * (1 - interpValue) + second.amount * interpValue));
      }
    }

    final newLog = FlightLog(
        samples: samples.sublist(startIndex, endIndex + 1).toList(),
        waypoints: waypoints,
        fuelReports: newFuelReports,
        gear: gear,
        filename: filename);
    return newLog;
  }

  FlightLog(
      {this.samples = const [],
      this.waypoints = const [],
      List<FuelReport> fuelReports = const [],
      Gear? gear,
      String? filename}) {
    if (samples.isEmpty) {
      goodFile = false;
      throw "Creating FlightLog without samples";
    }
    _filename = filename;
    _fuelReports = fuelReports.where((each) => containsTime(each.time)).toList();
    _gear = gear;
    goodFile = true;
  }

  FlightLog.fromJson(String filename, Map<String, dynamic> data, {this.rawJson}) {
    _filename = filename;
    unsaved = false;

    try {
      // --- Parse Gear
      final rawGear = data["gear"];
      if (rawGear != null) {
        gear = Gear.fromJson(data["gear"]);
      }

      // --- Parse Samples
      List<dynamic> dataSamples = data["samples"];
      samples = dataSamples.map((e) => Geo.fromJson(e)).toList();

      if (samples.isEmpty) {
        throw "No samples in log";
      }

      // --- Fill in speeds
      for (int t = 0; t < samples.length - 1; t++) {
        if (samples[t + 1].spd == 0 && samples[t].time < samples[t + 1].time) {
          final double dist = latlngCalc.distance(samples[t].latlng, samples[t + 1].latlng);
          samples[t + 1].spd = dist / (samples[t + 1].time - samples[t].time) * 1000;
        }
      }

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
      debugPrint("Error Loading Flight Log: $e");
      samples = [];
      waypoints = [];
      goodFile = false;
      DatadogSdk.instance.logs?.error("Broken FlightLog File",
          errorMessage: e.toString(),
          errorStackTrace: trace,
          attributes: {"filename": filename, "dataLength": rawJson?.length});
    }
  }

  String toJson() {
    return jsonEncode({
      "samples": samples.map((e) => e.toJson()).toList(),
      "waypoints":
          waypoints.where((element) => (!element.ephemeral && element.validate())).map((e) => e.toJson()).toList(),
      "fuelReports": fuelReports.map((e) => e.toJson()).toList(),
      "gear": gear?.toJson()
    });
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
