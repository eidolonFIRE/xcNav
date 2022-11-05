import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:flutter_svg/svg.dart';

import 'package:xcnav/models/waypoint.dart';

Marker _makeBarb(Color color, Barb barb, double size) {
  return Marker(
      point: barb.latlng,
      width: size,
      height: size,
      builder: (ctx) => Container(
          transformAlignment: const Alignment(0, 0),
          transform: Matrix4.rotationZ(barb.hdg)..scale(0.45),
          child: SvgPicture.asset(
            "assets/images/chevron.svg",
            color: color,
          )));
}

List<Marker> makePathBarbs(Iterable<Waypoint> waypoints, double size, double interval) {
  List<Marker> markers = [];

  for (final waypoint in waypoints) {
    if (waypoint.latlng.length < 2) continue;
    for (final barb in waypoint.getBarbs(interval)) {
      markers.add(_makeBarb(waypoint.getColor(), barb, size));
    }
  }

  return markers;
}
