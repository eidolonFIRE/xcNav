import 'dart:math';

import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

// --- Models
import 'package:xcnav/models/geo.dart';

class FlightLog {
  late String _filename;
  late List<Geo> samples;
  late bool goodFile;

  static var calc = const Distance(roundResult: false);

  // computed
  late String title;
  Duration? durationTime;
  double? durationDist;

  get filename => _filename;

  FlightLog.fromJson(String filename, dynamic data) {
    _filename = filename;

    try {
      List<dynamic> _dataSamples = data["samples"];
      samples = _dataSamples.map((e) => Geo.fromJson(e)).toList();

      var date = DateTime.fromMillisecondsSinceEpoch(samples[0].time);
      title = DateFormat("yyyy, MMM d").format(date);

      // --- Calculate Stuff
      durationTime =
          Duration(milliseconds: samples.last.time - samples[0].time);

      durationDist = 0;
      for (int i = 0; i < samples.length - 1; i++) {
        durationDist = durationDist! + samples[i].distanceTo(samples[i + 1]);
      }

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
    const numStyles = 16;
    List<String> styles = [];
    for (int i = 0; i < numStyles; i++) {
      final String lineColor =
          "ff" + colorWheel(-i / (numStyles - 1) * 2 / 3 + 1 / 3);

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

    const step = 6;
    const velRange = [15, 35];
    for (int i = 0; i < samples.length; i += step) {
      // assemble kml point list
      List<String> points = [];
      for (int t = 0; t <= step; t++) {
        if (i + t >= samples.length) continue;
        final p = samples[i + t];
        points.add("${p.lng},${p.lat},${p.alt}");
      }
      final pointsString = points.join("\n");

      // calc data for this segment
      final start = samples[i];
      final end = samples[min(samples.length - 1, i + step)];
      final dist =
          calc.distance(LatLng(start.lat, start.lng), LatLng(end.lat, end.lng));
      final time = end.time - start.time;
      final avgSpeed = dist / time * km2Miles;

      // select line style (color) based on the segment's average speed
      final style = "style" +
          (max(
                  0,
                  min(
                      numStyles - 1,
                      (numStyles *
                              (avgSpeed - velRange[0]) /
                              (velRange[1] - velRange[0]))
                          .floor())))
              .toString();
      linestrings.add("""<Placemark>
    <name>$i</name>
    <styleUrl>#$style</styleUrl>
    <LineString>
    <extrude>1</extrude>
    <tessellate>1</tessellate>
    <altitudeMode>absolute</altitudeMode>
    <coordinates>
    $pointsString
    </coordinates>
    </LineString>
    </Placemark>""");
    }

    return """<?xml version="1.0"?>
    <kml xmlns="http://www.opengis.net/kml/2.2">
    <Document>
    ${styles.join("\n")}
    ${linestrings.join("\n")}
    </Document>
    </kml>""";
  }
}
