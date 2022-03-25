import 'package:flutter/material.dart';
import 'package:location/location.dart';
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
  late Color color;
  List<Geo> flightTrace = [];

  // Flightplan
  int? selectedWaypoint;

  Pilot(this.id, this.name, this.geo) {
    // TODO: assign random colors
    color = Colors.green;
  }

  void updateTelemetry(dynamic telemetry, int timestamp) {
    Map<String, dynamic> gps = telemetry["gps"];
    fuel = (telemetry["fuel"] ?? 0.0) + 0.0;
    geo = Geo.fromLocationData(
        LocationData.fromMap({
          'latitude': gps["lat"],
          'longitude': gps["lng"],
          // 'accuracy': ,
          'altitude': gps["alt"],
          // 'speed': ,
          // 'speed_accuracy': ,
          // 'heading': ,
          'time': timestamp.toDouble(),
          // 'isMock'] == : ,
          // 'verticalAccuracy': ,
          // 'headingAccuracy': ,
          // 'elapsedRealtimeNanos': ,
          // 'elapsedRealtimeUncertaintyNanos': ,
          // 'satelliteNumber': ,
          // 'provider': ,
        }),
        geo);
  }
}
