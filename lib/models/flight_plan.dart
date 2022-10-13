import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

import 'package:xcnav/providers/active_plan.dart';

class FlightPlan {
  String name;
  late bool goodFile;
  late final List<Waypoint> waypoints;
  double? _length;

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
    // max zoom value
    if (points.length == 1) {
      points.add(LatLng(points.first.latitude, points.first.longitude + 0.02));
      points.add(LatLng(points.first.latitude, points.first.longitude - 0.02));
    }
    return LatLngBounds.fromPoints(points)..pad(0.2);
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
    double length = 0;
    int? prevIndex;
    for (int i = 0; i < waypoints.length; i++) {
      // skip optional waypoints
      Waypoint wpIndex = waypoints[i];
      if (wpIndex.isOptional) continue;

      if (prevIndex != null) {
        // Will take the last point of the previous waypoint
        LatLng prevLatlng = waypoints[prevIndex].latlng.last;
        length += latlngCalc.distance(wpIndex.latlng.first, prevLatlng);
      }

      // include lengths for paths
      length += wpIndex.length;

      prevIndex = i;
    }
    return length;
  }

  FlightPlan(this.name) {
    waypoints = [];
    goodFile = true;
  }

  FlightPlan.fromActivePlan(this.name, ActivePlan activePlan) {
    waypoints = activePlan.waypoints.toList();
    _calcLength();
    goodFile = true;
  }

  FlightPlan.fromJson(this.name, dynamic data) {
    try {
      List<dynamic> dataSamples = data["waypoints"];
      waypoints = dataSamples.map((e) => Waypoint.fromJson(e)).toList();

      _calcLength();

      goodFile = true;
    } catch (e) {
      goodFile = false;
    }
  }

  FlightPlan.fromKml(this.name, XmlElement document, List<XmlElement> folders,
      {bool setAllOptional = false}) {
    waypoints = [];

    void scanElement(XmlElement element) {
      element.findAllElements("Placemark").forEach((element) {
        String name = element.getElement("name")?.text.trim() ?? "untitled";
        if (element.getElement("Point") != null ||
            element.getElement("LineString") != null) {
          final List<LatLng> points =
              (element.getElement("Point") ?? element.getElement("LineString"))!
                  .getElement("coordinates")!
                  .text
                  .trim()
                  .split(RegExp(r'[\n ]'))
                  .where((element) => element.isNotEmpty)
                  .map((e) {
            final raw = e.split(",");
            return LatLng(double.parse(raw[1]), double.parse(raw[0]));
          }).toList();

          // (substr 1 to trim off the # symbol)
          final styleUrl = element.getElement("styleUrl")!.text.substring(1);

          int? color;

          // First try old style
          final styleElement = document.findAllElements("Style").where((e) =>
              e.getAttribute("id") != null &&
              e.getAttribute("id")!.startsWith(styleUrl));
          if (styleElement.isNotEmpty) {
            String? colorText = (styleElement.first.getElement("IconStyle") ??
                    styleElement.first.getElement("LineStyle"))
                ?.getElement("color")
                ?.text;
            if (colorText != null) {
              colorText = colorText.substring(0, 2) +
                  colorText.substring(6, 8) +
                  colorText.substring(4, 6) +
                  colorText.substring(2, 4);
              color = int.parse((colorText), radix: 16) | 0xff000000;
            }
          } else {
            // Try the new goggle style format

            // first styleMap and the destination url
            final styleMap = document
                .findAllElements("StyleMap")
                .where((e) => e.getAttribute("id")! == styleUrl)
                .first;
            final finalStyleUrl = styleMap
                .findAllElements("Pair")
                .where((e) => e.getElement("key")!.text == "normal")
                .first
                .getElement("styleUrl")!
                .text
                .substring(1);
            // grab destination url
            final finalStyleElement = document
                .findAllElements("gx:CascadingStyle")
                .where((e) => e.getAttribute("kml:id") == finalStyleUrl)
                .first;
            if (points.length > 1) {
              // LineStyle
              final finalColorString = finalStyleElement
                  .getElement("Style")!
                  .getElement("LineStyle")!
                  .getElement("color")!
                  .text;
              color = int.parse((finalColorString), radix: 16) | 0xff000000;
            } else {
              // IconStyle
              String href = finalStyleElement
                  .getElement("Style")!
                  .getElement("IconStyle")!
                  .getElement("Icon")!
                  .getElement("href")!
                  .text;
              String? finalColorString = RegExp(r'color=([a-f0-9]{6})')
                  .firstMatch(href)
                  ?.group(1)
                  .toString();
              if (finalColorString != null) {
                color = int.parse((finalColorString), radix: 16) | 0xff000000;
              }
            }
          }

          if (points.isNotEmpty) {
            if (points.length > 1) {
              // Trim length strings from title
              debugPrint("path ${name}");
              final match = RegExp(
                      r'(.*)[\s]+(?:[-])[\s]*([0-9\.]+)[\s]*(miles|mi|km|Miles|Mi|Km)$')
                  .firstMatch(name);
              name = match?.group(1) ?? name;
            }
            waypoints.add(Waypoint(name, points, setAllOptional, null, color));
          } else {
            debugPrint("Dropping $name with no points.");
          }
        }

        _calcLength();
      });
    }

    // try {
    if (folders.isNotEmpty) {
      for (final each in folders) {
        scanElement(each);
      }
    } else {
      // if no folders selected, scan whole document
      scanElement(document);
    }

    goodFile = true;
    // } catch (e) {
    //   debugPrint("Error loading kml file: ${e.toString()}");
    //   goodFile = false;
    // }
  }
}
