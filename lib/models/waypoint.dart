import 'dart:convert';
import 'dart:math';
import 'package:latlong2/latlong.dart';
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
    str += i.toString() +
        wp.name +
        (wp.icon ?? "") +
        (wp.color?.toString() ?? "") +
        (wp.isOptional ? "O" : "X");
    for (LatLng g in wp.latlng) {
      // large tolerance for floats
      str +=
          "${g.latitude.toStringAsFixed(5)}${g.longitude.toStringAsFixed(5)}";
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

class Waypoint {
  late String name;
  late List<LatLng> latlng;
  late bool isOptional;
  late String? icon;
  late int? color;

  double? _length;

  Waypoint(this.name, this.latlng, this.isOptional, this.icon, this.color);

  Waypoint.fromJson(json) {
    name = json["name"];
    isOptional = json["optional"];
    icon = json["icon"];
    color = json["color"];
    latlng = [];
    List<dynamic> rawList = json["latlng"];
    for (List<dynamic> e in rawList) {
      List<double> raw = e.cast<double>();
      latlng.add(LatLng(raw[0], raw[1]));
    }
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  /// Get full waypoint length.
  /// If waypoint is single point, length = 0
  /// (this getter will cache)
  double get length {
    return _length ??= lengthBetweenIndexs(0, latlng.length - 1);
  }

  double lengthBetweenIndexs(int start, int end) {
    // TODO: cache distances between all the points (vs recalculating every time)
    double dist = 0;
    for (int t = start; t < min(latlng.length - 1, end); t++) {
      dist += latlngCalc.distance(latlng[t], latlng[t + 1]);
    }
    return dist;
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
      "optional": isOptional,
      "icon": icon,
      "color": color,
    };
  }
}
