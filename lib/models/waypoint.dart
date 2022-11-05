import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';

enum WaypointAction {
  none,
  update,
  delete,
}

// Custom high-speed dirty hash for checking flightplan changes
String hashWaypointsData(Map<WaypointID, Waypoint> waypoints) {
  // build long string
  String str = "Plan";

  for (final each in waypoints.entries) {
    str += each.key + each.value.id + (each.value.icon ?? "") + (each.value.color?.toString() ?? "");
    for (LatLng g in each.value.latlng) {
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

typedef WaypointID = String;

class Waypoint {
  late String name;
  late List<LatLng> _latlng;
  late String? _icon;
  late int? color;
  late final WaypointID id;

  double? _length;
  List<Barb>? _barbs;
  double? _barbInterval;

  List<double>? _elevation;

  /// Cached distances between latlng points
  List<double>? _segments;

  bool get isPath => _latlng.length > 1;

  String? get icon => isPath ? "PATH" : _icon;
  set icon(String? newIcon) {
    _icon = newIcon;
  }

  Waypoint({required this.name, required List<LatLng> latlngs, String? icon, this.color, WaypointID? newId}) {
    latlng = latlngs;
    _icon = icon;
    id = newId ?? makeId();
  }

  @override
  // ignore: hash_and_equals
  bool operator ==(other) => other is Waypoint && other.id == id;

  Waypoint.fromJson(json) {
    id = json["id"] ?? makeId();
    name = json["name"];
    _icon = json["icon"];
    color = json["color"];
    _latlng = [];
    List<dynamic> rawList = json["latlng"];
    for (List<dynamic> e in rawList) {
      _latlng.add(LatLng(e[0] is int ? (e[0] as int).toDouble() : e[0] as double,
          e[1] is int ? (e[1] as int).toDouble() : e[1] as double));
    }
  }

  static WaypointID makeId() {
    // TODO: this could be better
    return DateTime.now().millisecondsSinceEpoch.toString();
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
    _barbInterval = null;
    _segments = null;
    _elevation = null;
  }

  /// Get full waypoint length.
  /// If waypoint is single point, length = 0
  /// (this getter will cache)
  double get length {
    return _length ??= lengthBetweenIndexs(0, latlng.length - 1);
  }

  List<Barb> getBarbs(interval) {
    if (interval != _barbInterval || _barbs == null) {
      _barbs = _makeBarbs(interval);
    }
    return _barbs!;
  }

  /// Elevation per latlng point. (will be lazy loaded so it may return [0, ...] at first)
  List<double> get elevation {
    if (_elevation != null) {
      return _elevation!;
    } else {
      final futures = latlng.map((e) => sampleDem(e, true)).toList();
      Future.wait(futures).then((values) {
        _elevation = values.map((e) => e ?? 0).toList();
      });

      // Return a dummy list for now
      return List.filled(latlng.length, 0);
    }
  }

  /// Segment distances between latlng points
  List<double> get segments {
    if (_segments == null) {
      // Bake the list
      _segments = [];
      for (int t = 0; t < latlng.length - 1; t++) {
        _segments!.add(latlngCalc.distance(latlng[t], latlng[t + 1]));
      }
    }
    return _segments!;
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
      return ETA.fromSpeed(dist, speed, pathIntercept: intercept);
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

  /// Linear interpolate down the path by some distance.
  /// If `initialLatlng` is given, that point will precede the selected path points.
  Barb interpolate(double distance, int startIndex, {int? endIndex, LatLng? initialLatlng}) {
    if (!isPath) return Barb(latlng[0], 0);

    List<LatLng> points = latlng.sublist(startIndex, endIndex);
    List<double> segs = segments.sublist(startIndex, endIndex == null ? null : (endIndex - 1));

    if (points.length == 1) return Barb(points.first, 0);
    if (points.isEmpty) return Barb(latlng[0], 0);

    if (initialLatlng != null) {
      points.insert(0, initialLatlng);
      segs.insert(0, latlngCalc.distance(initialLatlng, latlng[0]));
    }

    // Check for overflow
    // if (distance >= segs.reduce((a, b) => a + b)) {
    //   return Barb(points.last, latlngCalc.bearing(points[points.length - 2], points.last) * pi / 180);
    // }

    // Iter through segs until we find the segment we are in the middle of
    int segIndex = 0;
    double distTicker = 0;
    // debugPrint("${segs}");
    while (segs[segIndex] + distTicker < distance && segIndex < segs.length - 1) {
      // we can still jump to the next segment
      distTicker += segs[segIndex];
      segIndex++;
    }
    // debugPrint("seg: $segIndex, dist: $distTicker / $distance");

    final brg = latlngCalc.bearing(points[segIndex], points[segIndex + 1]);
    return Barb(latlngCalc.offset(points[segIndex], distance - distTicker, brg), brg * pi / 180);
  }

  /// Cumulative segment distances between path vertices
  double lengthBetweenIndexs(int start, int end) {
    if (start >= end) return 0;
    return segments.sublist(start, end).reduce((a, b) => a + b);
  }

  List<Barb> _makeBarbs(double interval) {
    if (latlng.length < 2) return [];

    List<Barb> barbs = [];

    // // Add head and tail
    // barbs.add(Barb(latlng.first, latlngCalc.bearing(latlng.first, latlng[1]) * pi / 180));

    // // Add intermediary points
    // for (int i = 0; i < latlng.length - 1; i++) {
    //   final brg = latlngCalc.bearing(latlng[i], latlng[i + 1]);
    //   final dist = latlngCalc.distance(latlng[i], latlng[i + 1]);
    //   barbs.add(Barb(latlngCalc.offset(latlng[i], dist / 2, brg), brg * pi / 180));
    // }
    // TODO: support metric barbs
    for (double dist = 0; dist <= length; dist += interval) {
      barbs.add(interpolate(dist, 0));
    }

    barbs.add(Barb(latlng.last, latlngCalc.bearing(latlng[latlng.length - 2], latlng.last) * pi / 180));

    _barbInterval = interval;
    return barbs;
  }

  dynamic toJson() {
    return {
      "id": id,
      "name": name,
      "latlng": latlng
          .map((e) => [
                // (reduce decimals of precision to shrink message size bloat for paths)
                ((e.latitude * 100000).round()) / 100000,
                ((e.longitude * 100000).round()) / 100000
              ])
          .toList(),
      "icon": icon,
      "color": color,
    };
  }
}
