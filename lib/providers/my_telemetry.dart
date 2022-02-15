import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:location/location.dart';
import 'package:latlong2/latlong.dart';

import '../util/geo.dart';

class MyTelemetry with ChangeNotifier {
  // Live Readings
  Geo geo = Geo();

  // Calculated
  Geo? geoPrev;

  // Recorded
  List<Geo> record = [];
  List<LatLng> recordLatLng = [];

  void updateGeo(LocationData location) {
    // print("${location.elapsedRealtimeNanos}) ${location.latitude}, ${location.longitude}, ${location.altitude}");
    geoPrev = geo;
    geo = Geo.fromLocationData(location, geoPrev);
    record.add(geo);
    // TODO: simpliy point density
    if (recordLatLng.isEmpty ||
        (recordLatLng.isNotEmpty &&
            latlngCalc.distance(recordLatLng.last, geo.latLng) > 50)) {
      recordLatLng.add(geo.latLng);
    }

    notifyListeners();
  }

  Polyline buildFlightTrace() {
    return Polyline(
        points: recordLatLng,
        strokeWidth: 6,
        color: const Color.fromARGB(100, 255, 50, 50),
        isDotted: true);
  }
}
