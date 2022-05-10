import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:xcnav/models/geo.dart';

class Pilot {
  // basic info
  String id;
  String name;

  // telemetry
  Geo geo;
  double? fuel;

  // visuals
  Image? avatar;
  String? avatarHash;
  List<Geo> flightTrace = [];

  // Flightplan
  int? selectedWaypoint;

  Pilot(this.id, this.name, this.geo);

  void updateTelemetry(dynamic telemetry, int timestamp) {
    Map<String, dynamic> gps = telemetry["gps"];
    fuel = (telemetry["fuel"] ?? 0.0) + 0.0;
    // Don't use LatLng(0,0)
    if (gps["lat"] != 0.0 || gps["lng"] != 0.0) {
      geo = Geo.fromPosition(
          Position(
            longitude: gps["lng"],
            latitude: gps["lat"],
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
            accuracy: 1,
            altitude: gps["alt"],
            heading: 0,
            speed: 0,
            speedAccuracy: 1,
          ),
          geo,
          null,
          null);
    } else {
      debugPrint("skipped");
    }
  }
}
