import 'dart:convert';

import 'package:latlong2/latlong.dart';

class Airport {
  final String name;

  /// IATA / ICAO
  final String code;
  final LatLng latlng;
  final double? alt;

  Airport(this.name, this.code, this.latlng, this.alt);
}

Map<String, Airport>? _airports;

void loadAirports(String data) async {
  final Map<String, dynamic> jsonResult = jsonDecode(data);

  _airports = {};
  for (final each in jsonResult.entries) {
    _airports![each.key] = Airport(each.value[0], each.key, LatLng(each.value[1], each.value[2]), each.value[3]);
  }
}

Airport? getAirport(String code) {
  return _airports?[code];
}
