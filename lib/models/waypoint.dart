import 'dart:convert';
import 'dart:math';
import 'package:bisection/bisect.dart';
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
    if (each.value.ephemeral) continue;
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

class BarbData {
  LatLng latlng;

  /// Radians
  double hdg;
  BarbData(this.latlng, this.hdg);
}

typedef WaypointID = String;

class Waypoint {
  late String name;
  late List<LatLng> _latlng;
  late String? _icon;
  late int? color;
  late final WaypointID id;

  /// Ephemeral waypoints will not be synchronized to the backend, or saved to file.
  late final bool ephemeral;

  double? _length;

  bool _isReversed = false;
  List<LatLng>? _latlngOriented;

  List<double>? _elevation;

  /// Cached distances between oriented latlng points
  List<double>? _segsOriented;

  bool get isPath => _latlng.length > 1;

  String? get icon => isPath ? "PATH" : _icon;
  set icon(String? newIcon) {
    _icon = newIcon;
  }

  Waypoint(
      {required this.name,
      required List<LatLng> latlngs,
      String? icon,
      this.color,
      WaypointID? newId,
      this.ephemeral = false}) {
    latlng = latlngs;
    _icon = icon;
    id = newId ?? makeId();
  }

  Waypoint.from(Waypoint other) {
    name = other.name;
    latlng = other.latlng.toList();
    _icon = other.icon;
    color = other.color;
    id = other.id;
    ephemeral = other.ephemeral;
  }

  @override
  // ignore: hash_and_equals
  bool operator ==(other) => other is Waypoint && other.id == id;

  Waypoint.fromJson(json) {
    ephemeral = false;
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

  WaypointID makeId() {
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36) + hashCode.toRadixString(36);
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  List<LatLng> get latlng => _latlng;
  set latlng(List<LatLng> newLatlngs) {
    _latlng = newLatlngs;
    _latlngOriented = null;
    _length = null;
    _segsOriented = null;
    _elevation = null;
  }

  List<LatLng> get latlngOriented {
    return _latlngOriented ??= _isReversed ? _latlng.reversed.toList() : _latlng;
  }

  /// Get full waypoint length.
  /// If waypoint is single point, length = 0
  /// (this getter will cache)
  double get length {
    return _length ??= lengthBetweenIndexs(0, latlng.length - 1);
  }

  void toggleDirection() {
    _isReversed = !_isReversed;
    _latlngOriented = null;
    _segsOriented = null;
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
  List<double> get segsOriented {
    if (_segsOriented == null) {
      // Bake the list
      _segsOriented = [0];
      for (int t = 0; t < latlngOriented.length - 1; t++) {
        _segsOriented!.add(_segsOriented!.last + latlngCalc.distance(latlngOriented[t], latlngOriented[t + 1]));
      }
    }
    return _segsOriented!;
  }

  Color getColor() {
    return Color(color ?? Colors.black.value);
  }

  /// ETA from a location to a waypoint
  /// If target is a path, result is dist to nearest intercept + remaining path
  ETA eta(Geo geo, double speed) {
    final intercept = geo.getIntercept(latlng, isReversed: _isReversed);
    double dist = intercept.dist + lengthBetweenIndexs(intercept.index, latlng.length - 1);
    return ETA.fromSpeed(dist, speed, pathIntercept: intercept);
  }

  /// Linear interpolate down the path by some distance.
  /// If `initialLatlng` is given, that point will precede the selected path points.
  BarbData interpolate(double distance, int startIndex, {LatLng? initialLatlng}) {
    double initialSeg = 0;
    if (initialLatlng != null) {
      /// Imaginary added segment to the beginning
      initialSeg = latlngCalc.distance(initialLatlng, latlngOriented[startIndex]);

      // Early-out for first imaginary segment
      if (distance <= initialSeg || !isPath) {
        final brg = latlngCalc.bearing(initialLatlng, latlngOriented[startIndex]);
        return BarbData(latlngCalc.offset(initialLatlng, distance, brg), brg * pi / 180);
      }
    }

    /// value of segments not in use
    final offsetSegs = segsOriented[startIndex];
    int segIndex = max(
        0,
        bisect_left<double>(segsOriented, distance + offsetSegs - initialSeg,
                hi: segsOriented.length - 1, compare: (a, b) => (a - b).toInt()) -
            1);
    final distRemaining = distance - segsOriented[segIndex] + offsetSegs - initialSeg;

    /// If we start from the last point, use the last segment heading
    final brg = segIndex >= latlngOriented.length - 1
        ? latlngCalc.bearing(latlngOriented[segIndex - 1], latlngOriented[segIndex])
        : latlngCalc.bearing(latlngOriented[segIndex], latlngOriented[segIndex + 1]);
    return BarbData(latlngCalc.offset(latlngOriented[segIndex], distRemaining, brg), brg * pi / 180);
  }

  /// Cumulative segment distances between path vertices
  double lengthBetweenIndexs(int start, int end) {
    if (start >= end) return 0;
    return segsOriented[end] - segsOriented[start];
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
