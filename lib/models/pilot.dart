import 'package:flutter/material.dart';
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
  late Color color;
  List<Geo> flightTrace = [];

  // Flightplan
  int? selectedWaypoint;

  Pilot(this.id, this.name, this.geo) {
    // TODO: assign random colors
    color = Colors.green;
  }

  void updateTelemetry(dynamic telemetry, double timestamp) {
    // TODO: update geo and fuel
  }
}
