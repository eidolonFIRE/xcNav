import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:xcnav/models/waypoint.dart';

Marker makeBarb(Waypoint waypoint, Barb barb, double size, bool reversed) {
  return Marker(
      point: barb.latlng,
      width: size,
      height: size,
      builder: (ctx) => Container(
          transformAlignment: const Alignment(0, 0),
          transform: Matrix4.rotationZ(barb.hdg + (reversed ? pi : 0)),
          child: Icon(
            Icons.arrow_drop_up,
            size: size,
            color: waypoint.getColor(),
          )));
}

List<Marker> makePathBarbs(List<Waypoint> waypoints, bool isReversed, double size) {
  List<Marker> markers = [];

  for (final waypoint in waypoints) {
    if (waypoint.latlng.length < 2) continue;
    for (final barb in waypoint.barbs) {
      markers.add(makeBarb(waypoint, barb, size, isReversed));
    }
  }

  return markers;
}
