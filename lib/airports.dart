import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/util.dart';

class Airport {
  final String name;

  /// IATA / ICAO
  final String code;
  final LatLng latlng;
  final double? alt;

  Airport(this.name, this.code, this.latlng, this.alt);
}

Map<String, Airport>? _airports;

void loadAirports(String data) {
  final Map<String, dynamic> jsonResult = jsonDecode(data);

  _airports = {};
  for (final each in jsonResult.entries) {
    final alt = parseAsDouble(each.value[3]);
    _airports![each.key] = Airport(each.value[0], each.key,
        LatLng(parseAsDouble(each.value[1])!, parseAsDouble(each.value[2])!), alt != null ? alt * 0.3048 : null);
  }
}

Airport? getAirport(String code) {
  return _airports?[code];
}

bool airportsLoaded() {
  return _airports != null;
}
