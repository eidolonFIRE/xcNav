import 'dart:math';

import 'package:datadog_flutter_plugin/datadog_flutter_plugin.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/douglas_peucker.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/units.dart';
import 'package:xml/xml.dart';

class FlightLog {
  late final String _filename;
  late List<Geo> samples;
  late final List<Waypoint> waypoints;
  late final bool goodFile;
  late final String? rawJson;

  late String title;
  late Duration durationTime;

  /// Meters
  late double durationDist;

  /// Meters
  late double maxAlt;

  /// Fastest climb sustained for 1min
  /// `m/s`
  late double bestClimb;

  /// `m/s`
  late double meanSpd;

  String get filename => _filename;

  DateTime get startTime => DateTime.fromMillisecondsSinceEpoch(samples.first.time);
  DateTime get endTime => DateTime.fromMillisecondsSinceEpoch(samples.last.time);

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

  double? _altGained;
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

  int compareTo(FlightLog other) {
    if (goodFile && other.goodFile) {
      return other.startTime.compareTo(startTime);
    } else {
      return other.filename.compareTo(filename);
    }
  }

  FlightLog.fromJson(String filename, Map<String, dynamic> data, {this.rawJson}) {
    _filename = filename;

    debugPrint("Loading: $filename");

    try {
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

      var date = DateTime.fromMillisecondsSinceEpoch(samples.first.time);
      title = DateFormat("MMM d - yyyy").format(date);

      // --- Calculate Stuff
      durationTime = Duration(milliseconds: samples.last.time - samples.first.time);

      durationDist = 0;
      for (int i = 0; i < samples.length - 1; i++) {
        durationDist = durationDist + samples[i].distanceTo(samples[i + 1]);
      }

      if (samples.length > 1) {
        maxAlt = samples.reduce((a, b) => a.alt > b.alt ? a : b).alt;
      } else {
        maxAlt = samples.first.alt;
      }

      if (durationTime.inMilliseconds > 0) {
        meanSpd = durationDist / durationTime.inSeconds;
      } else {
        meanSpd = 0;
      }

      // --- Sliding window search for bestClimb
      int left = 0;
      int right = 0;
      bestClimb = 0;
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
        if (newClimb > bestClimb) {
          bestClimb = newClimb;
        }

        // scoot window
        left++;
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
      goodFile = true;
    } catch (e, trace) {
      debugPrint("Error Loading Flight Log: $e");
      samples = [];
      waypoints = [];
      title = "Broken File! $filename";
      goodFile = false;
      DatadogSdk.instance.logs?.error("Broken FlightLog File",
          errorMessage: e.toString(),
          errorStackTrace: trace,
          attributes: {"filename": filename, "dataLength": rawJson?.length});
    }
  }

  String colorWheel(double pos) {
    // Select color from rainbow
    List<double> color = [];
    pos = pos % 1.0;
    if (pos < 1 / 3) {
      color = [pos * 3.0, (1.0 - pos * 3.0), 0.0];
    } else if (pos < 2 / 3) {
      pos -= 1 / 3;
      color = [(1.0 - pos * 3.0), 0.0, pos * 3.0];
    } else {
      pos -= 2 / 3;
      color = [0.0, pos * 3.0, (1.0 - pos * 3.0)];
    }
    color = [
      max(0, min(255, round(color[0] * 255))),
      max(0, min(255, round(color[1] * 255))),
      max(0, min(255, round(color[2] * 255))),
    ];
    return color[0].toInt().toRadixString(16).padLeft(2, "0") +
        color[1].toInt().toRadixString(16).padLeft(2, "0") +
        color[2].toInt().toRadixString(16).padLeft(2, "0");
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
