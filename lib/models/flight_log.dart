import 'dart:math';

import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

// --- Models
import 'package:xcnav/models/geo.dart';

class FlightLog {
  late final String _filename;
  late List<Geo> samples;
  late final bool goodFile;

  static var calc = const Distance(roundResult: false);

  // computed
  late String title;
  Duration? durationTime;
  double? durationDist;
  double? maxAlt;

  get filename => _filename;

  FlightLog.fromJson(String filename, dynamic data) {
    _filename = filename;

    try {
      List<dynamic> dataSamples = data["samples"];
      samples = dataSamples.map((e) => Geo.fromJson(e)).toList();

      var date = DateTime.fromMillisecondsSinceEpoch(samples[0].time);
      title = DateFormat("MMM d - yyyy").format(date);

      // --- Calculate Stuff
      durationTime = Duration(milliseconds: samples.last.time - samples[0].time);

      durationDist = 0;
      for (int i = 0; i < samples.length - 1; i++) {
        durationDist = durationDist! + samples[i].distanceTo(samples[i + 1]);
      }

      maxAlt = samples.reduce((a, b) => a.alt > b.alt ? a : b).alt;

      goodFile = true;
    } catch (e) {
      samples = [];
      title = "Broken File!";
      goodFile = false;
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

    return """<?xml version="1.0"?>
    <kml xmlns="http://www.opengis.net/kml/2.2">
    <Document>
    ${styles.join("\n")}
    ${linestrings.join("\n")}
    </Document>
    </kml>""";
  }
}
