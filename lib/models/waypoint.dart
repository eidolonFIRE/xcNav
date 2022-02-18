import 'dart:convert';
import 'package:latlong2/latlong.dart';

// Custom high-speed dirty hash for checking flightplan changes
String hashFlightPlanData(List<Waypoint> waypoints) {
  // build long string
  String str = "Plan";

  for (int i = 0; i < waypoints.length; i++) {
    Waypoint wp = waypoints[i];
    str += i.toString() + wp.name + (wp.isOptional ? "O" : "X");
    for (LatLng g in wp.latlng) {
      // large tolerance for floats
      str += g.latitude.toStringAsFixed(4) + g.longitude.toStringAsFixed(4);
    }
  }

  // fold string into hash
  int hash = 0;
  for (int i = 0, len = str.length; i < len; i++) {
    hash = ((hash << 5) - hash) + str.codeUnitAt(i);
    hash |= 0;
  }
  return (hash < 0 ? hash * -2 : hash).toRadixString(16);
}

class Waypoint {
  late String name;
  late List<LatLng> latlng;
  late bool isOptional;
  late String? icon;
  late int? color;

  // --- calculated later for polylines
  double? length;

  Waypoint(this.name, this.latlng, this.isOptional, this.icon, this.color) {
    // TODO: calculate length
  }

  Waypoint.fromJson(json) {
    name = json["name"];
    isOptional = json["optional"];
    icon = json["icon"];
    color = json["color"];
    latlng = [];
    List<dynamic> rawList = json["geo"];
    for (List<double> e in rawList) {
      List<double> raw = e;
      latlng.add(LatLng(raw[0], raw[1]));
    }

    // TODO: calculate length
  }

  @override
  String toString() {
    return jsonEncode({
      "name": name,
      "latlng": latlng.map((e) => [e.latitude, e.longitude]).toList(),
      "isOptional": isOptional,
      "icon": icon,
      "color": color,
    });
  }
}
