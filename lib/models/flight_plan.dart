import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xml/xml.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

class FlightPlan {
  late String _name;
  late bool goodFile;
  late final List<Waypoint> waypoints;
  double? _length;

  get name => _name;

  double get length {
    return _length ??= _calcLength();
  }

  // TODO: refactor this to be more elegant
  void refreshLength() {
    _length = _calcLength();
  }

  /// Path and filename
  Future<String> getFilename() {
    Completer<String> completer = Completer();
    getApplicationDocumentsDirectory().then((tempDir) {
      completer.complete("${tempDir.path}/flight_plans/$name.json");
    });
    return completer.future;
  }

  LatLngBounds? getBounds() {
    if (waypoints.isEmpty) return null;
    List<LatLng> points = [];
    for (final wp in waypoints) {
      points.addAll(wp.latlng);
    }
    return LatLngBounds.fromPoints(points)..pad(0.4);
  }

  void sortWaypoint(int oldIndex, int newIndex) {
    Waypoint temp = waypoints[oldIndex];
    waypoints.removeAt(oldIndex);
    waypoints.insert(newIndex, temp);
  }

  Polyline _buildTripSnakeSegment(List<LatLng> points) {
    return Polyline(
      points: points,
      color: Colors.black,
      strokeWidth: 3,
    );
  }

  List<Polyline> buildTripSnake() {
    List<Polyline> retval = [];

    List<LatLng> points = [];
    for (Waypoint wp in waypoints) {
      // skip optional waypoints
      if (wp.isOptional) continue;

      if (wp.latlng.isNotEmpty) {
        points.add(wp.latlng[0]);
      }
      if (wp.latlng.length > 1) {
        // pinch off trip snake
        retval.add(_buildTripSnakeSegment(points));
        // start again at last point
        points = [wp.latlng[wp.latlng.length - 1]];
      }
    }

    if (points.length > 1) retval.add(_buildTripSnakeSegment(points));
    return retval;
  }

  double _calcLength() {
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
    return _length;
  }

  FlightPlan.new(String name) {
    waypoints = [];
    _name = name;
    goodFile = true;
  }

  FlightPlan.fromActivePlan(ActivePlan activePlan, String name) {
    waypoints = activePlan.waypoints.toList();
    _name = name;
    _calcLength();
    goodFile = true;
  }

  FlightPlan.fromJson(String name, dynamic data) {
    _name = name;

    try {
      List<dynamic> _dataSamples = data["waypoints"];
      waypoints = _dataSamples.map((e) => Waypoint.fromJson(e)).toList();

      _calcLength();

      goodFile = true;
    } catch (e) {
      goodFile = false;
    }
  }

  FlightPlan.fromKml(String name, String rawData) {
    _name = name;
    waypoints = [];

    // try {
    var document = XmlDocument.parse(rawData).getElement("kml")!.getElement("Document")!;

    document.findAllElements("Placemark").forEach((element) {
      final String name = element.getElement("name")!.text;
      if (element.getElement("Point") != null || element.getElement("LineString") != null) {
        final List<LatLng> points = (element.getElement("Point") ?? element.getElement("LineString"))!
            .getElement("coordinates")!
            .text
            .trim()
            .split("\n")
            .map((e) {
          final _raw = e.split(",");
          return LatLng(double.parse(_raw[1]), double.parse(_raw[0]));
        }).toList();

        final styleElement = document
            .findAllElements("Style")
            .where((_e) => _e.getAttribute("id")!.startsWith(element.getElement("styleUrl")!.text.substring(1)));
        String? colorText = (styleElement.first.getElement("IconStyle") ?? styleElement.first.getElement("LineStyle"))
            ?.getElement("color")
            ?.text;
        if (colorText != null) {
          colorText = colorText.substring(0, 2) +
              colorText.substring(6, 8) +
              colorText.substring(4, 6) +
              colorText.substring(2, 4);
        }
        final int color = int.parse((colorText ?? Colors.black.value.toString()), radix: 16) | 0xff000000;

        if (points.isNotEmpty) {
          waypoints.add(Waypoint(name, points, name.toLowerCase().startsWith("opt"), null, color));
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

  Future rename(String name) {
    // remove old file
    getFilename().then((filename) {
      File planFile = File(filename);
      planFile.exists().then((value) {
        planFile.delete();
      });
    });

    _name = name;

    // save to new name
    return saveToFile();
  }

  Future saveToFile() {
    Completer completer = Completer();
    getFilename().then((filename) {
      File file = File(filename);

      file.create(recursive: true).then((value) => file
          .writeAsString(jsonEncode({"title": name, "waypoints": waypoints.map((e) => e.toJson()).toList()}))
          .then((_) => completer.complete()));
    });
    return completer.future;
  }
}
