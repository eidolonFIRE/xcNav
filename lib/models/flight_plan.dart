import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xml/xml.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

class FlightPlan {
  late final String _filename;
  late bool goodFile;
  late String title;
  late final List<Waypoint> waypoints;
  double? length;

  get filename => _filename;

  void _calcLength() {
    // --- Calculate Stuff
    double _length = 0;
    int? prevIndex;
    for (int i = 0; i < waypoints.length; i++) {
      // skip optional waypoints
      Waypoint wpIndex = waypoints[i];
      if (wpIndex.isOptional) continue;

      if (prevIndex != null) {
        // Will take the last point of the current waypoint, nearest point of the next
        LatLng prevLatlng = waypoints[prevIndex].latlng.first;
        _length += latlngCalc.distance(wpIndex.latlng.first, prevLatlng);

        // add path distance
        _length += wpIndex.length;
      }
      prevIndex = i;
    }
    length = _length;
  }

  FlightPlan.fromJson(String filename, dynamic data) {
    _filename = filename;

    try {
      List<dynamic> _dataSamples = data["waypoints"];
      waypoints = _dataSamples.map((e) => Waypoint.fromJson(e)).toList();

      title = data["title"];

      _calcLength();

      goodFile = true;
    } catch (e) {
      title = "Broken File!";
      goodFile = false;
    }
  }

  FlightPlan.fromKml(String filename, String rawData) {
    _filename = filename;
    waypoints = [];

    // try {
    final document =
        XmlDocument.parse(rawData).getElement("kml")!.getElement("Document");

    title = document!.getElement("name")?.text ?? "Untitled";

    document.findAllElements("Placemark").forEach((element) {
      final String name = element.getElement("name")!.text;
      if (element.getElement("Point") != null ||
          element.getElement("LineString") != null) {
        final List<LatLng> points =
            (element.getElement("Point") ?? element.getElement("LineString"))!
                .getElement("coordinates")!
                .text
                .trim()
                .split("\n")
                .map((e) {
          final _raw = e.split(",");
          return LatLng(double.parse(_raw[1]), double.parse(_raw[0]));
        }).toList();

        final styleElement = document.findAllElements("Style").where((_e) => _e
            .getAttribute("id")!
            .startsWith(element.getElement("styleUrl")!.text.substring(1)));
        String? colorText = (styleElement.first.getElement("IconStyle") ??
                styleElement.first.getElement("LineStyle"))
            ?.getElement("color")
            ?.text;
        if (colorText != null) {
          colorText = colorText.substring(0, 2) +
              colorText.substring(6, 8) +
              colorText.substring(4, 6) +
              colorText.substring(2, 4);
        }
        final int color =
            int.parse((colorText ?? Colors.black.value.toString()), radix: 16) |
                0xff000000;

        // TODO: parse icon
        if (points.isNotEmpty) {
          waypoints.add(Waypoint(
              name, points, name.toLowerCase().startsWith("opt"), null, color));
        } else {
          debugPrint("Dropping $name with no points.");
        }
      }

      _calcLength();
    });
    goodFile = true;
    // } catch (e) {
    //   debugPrint("$e");
    //   title = "Broken File!";
    //   goodFile = false;
    // }
  }
}
