import 'dart:convert';

import 'package:latlong2/latlong.dart';
// import

class Waypoint {
  String name;
  List<LatLng> latlng;
  bool isOptional;
  String? icon;
  int? color;

  // --- calculated later for polylines
  double? length;

  Waypoint(this.name, this.latlng, this.isOptional, this.icon, this.color);

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
