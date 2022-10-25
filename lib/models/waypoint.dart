import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';

enum WaypointAction {
  none,
  add,
  modify,
  delete,
  sort,
}

// Custom high-speed dirty hash for checking flightplan changes
String hashFlightPlanData(List<Waypoint> waypoints) {
  // build long string
  String str = "Plan";

  for (int i = 0; i < waypoints.length; i++) {
    Waypoint wp = waypoints[i];
    // TODO: need to remove "X" but in-step with server
    str += i.toString() + wp.name + (wp.icon ?? "") + (wp.color?.toString() ?? "") + "X";
    for (LatLng g in wp.latlng) {
      // large tolerance for floats
      str += "${g.latitude.toStringAsFixed(5)}${g.longitude.toStringAsFixed(5)}";
    }
  }

  // fold string into hash
  int hash = 0;
  for (int i = 0, len = str.length; i < len; i++) {
    hash = ((hash << 5) - hash) + str.codeUnitAt(i);
    hash &= 0xffffff;
  }
  return (hash < 0 ? hash * -2 : hash).toRadixString(16);
}

class Barb {
  LatLng latlng;

  /// Radians
  double hdg;
  Barb(this.latlng, this.hdg);
}

class Waypoint {
  late String name;
  late List<LatLng> _latlng;
  late String? icon;
  late int? color;

  double? _length;
  List<Barb>? _barbs;

  double? _elevation;

  bool get isPath => _latlng.length > 1;

  Waypoint(this.name, this._latlng, this.icon, this.color);

  Waypoint.fromJson(json) {
    name = json["name"];
    icon = json["icon"];
    color = json["color"];
    _latlng = [];
    List<dynamic> rawList = json["latlng"];
    for (List<dynamic> e in rawList) {
      _latlng.add(LatLng(e[0] is int ? (e[0] as int).toDouble() : e[0] as double,
          e[1] is int ? (e[1] as int).toDouble() : e[1] as double));
    }
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  List<LatLng> get latlng => _latlng;
  set latlng(List<LatLng> newLatlngs) {
    _latlng = newLatlngs;
    _length = null;
    _barbs = null;
  }

  /// Get full waypoint length.
  /// If waypoint is single point, length = 0
  /// (this getter will cache)
  double get length {
    return _length ??= lengthBetweenIndexs(0, latlng.length - 1);
  }

  List<Barb> get barbs {
    return _barbs ??= makeBarbs();
  }

  double get elevation {
    if (_elevation != null) {
      return _elevation!;
    } else {
      sampleDem(latlng[0], true).then((value) => _elevation = value);
      return 0;
    }
  }

  Color getColor() {
    return Color(color ?? Colors.black.value);
  }

  /// ETA from a location to a waypoint
  /// If target is a path, result is dist to nearest intercept + remaining path
  ETA eta(Geo geo, double speed, {bool isReversed = false}) {
    if (latlng.length > 1) {
      // --- to path
      final intercept = geo.nearestPointOnPath(latlng, isReversed);
      double dist = geo.distanceToLatlng(intercept.latlng) +
          lengthBetweenIndexs(intercept.index, isReversed ? 0 : latlng.length - 1);
      return ETA.fromSpeed(dist, speed);
    } else {
      // --- to point
      if (latlng.isNotEmpty) {
        double dist = geo.distanceToLatlng(latlng[0]);
        return ETA.fromSpeed(dist, speed);
      } else {
        return ETA.fromSpeed(0, speed);
      }
    }
  }

  double lengthBetweenIndexs(int start, int end) {
    // TODO: cache distances between all the points (vs recalculating every time)
    double dist = 0;
    for (int t = max(0, min(start, end)); t < min(latlng.length - 1, max(start, end)); t++) {
      dist += latlngCalc.distance(latlng[t], latlng[t + 1]);
    }
    return dist;
  }

  List<Barb> makeBarbs() {
    if (latlng.length < 2) return [];

    List<Barb> barbs = [];

    // Add head and tail
    barbs.add(Barb(latlng.first, latlngCalc.bearing(latlng.first, latlng[1]) * pi / 180));
    barbs.add(Barb(latlng.last, latlngCalc.bearing(latlng[latlng.length - 2], latlng.last) * pi / 180));

    // Add intermediary points
    for (int i = 0; i < latlng.length - 1; i++) {
      final brg = latlngCalc.bearing(latlng[i], latlng[i + 1]);
      final dist = latlngCalc.distance(latlng[i], latlng[i + 1]);
      barbs.add(Barb(latlngCalc.offset(latlng[i], dist / 2, brg), brg * pi / 180));
    }
    return barbs;
  }

  dynamic toJson() {
    return {
      "name": name,
      "latlng": latlng
          .map((e) => [
                // (reduce decimals of precision to shrink message size bloat for paths)
                ((e.latitude * 100000).round()) / 100000,
                ((e.longitude * 100000).round()) / 100000
              ])
          .toList(),
      // TODO: remove this in step with backend
      "optional": false,
      "icon": icon,
      "color": color,
    };
  }
}
