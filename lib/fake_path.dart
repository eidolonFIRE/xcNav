import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:xcnav/models/geo.dart';
import 'package:latlong2/latlong.dart';

class FakeGeo {
  FakeGeo(this.lng, this.lat, this.alt);

  double lng;
  double lat;
  double alt;
}

Position fakeGeoToLoc(FakeGeo geo) {
  return Position(
    latitude: geo.lat,
    longitude: geo.lng,
    altitude: geo.alt,
    timestamp: DateTime.now(),
    accuracy: 1,
    speed: 0,
    speedAccuracy: 0,
    heading: 0,
  );
}

/// Create a fake flight track
class FakeFlight {
  late Random rand;

  // Position
  late FakeGeo center;
  late LatLng latlng;
  late double alt;
  double vario = 0;
  late double spd;
  double hdg = 0;

  // Wind
  late double windSpd;
  late double windHdg;

  @override
  FakeFlight() {
    rand = Random(DateTime.now().millisecondsSinceEpoch);

    initFakeFlight(Geo.fromValues(0, 0, 0, 0, 0, 0, 0));
    spd = 11.15 + 4.5 * rand.nextDouble();
  }

  double randomCentered() {
    return rand.nextDouble() * 2 - 1;
  }

  /// Sets the starting point for the fake flight data
  void initFakeFlight(Geo geo) {
    center = FakeGeo(geo.lng, geo.lat, geo.alt);

    latlng = LatLng(center.lat, center.lng);
    alt = center.alt;

    windSpd = rand.nextDouble() * 5 + 5;
    windHdg = rand.nextDouble() * 360;

    debugPrint("Fake Wind: $windSpd, $windHdg");
  }

  Position genFakeLocationFlight() {
    hdg += randomCentered() * 30 + 10;

    latlng = latlngCalc.offset(
        latlng, (spd + randomCentered()) * 5, hdg + randomCentered());
    latlng = latlngCalc.offset(
        latlng, windSpd * 5 + randomCentered(), windHdg + randomCentered());

    vario = min(10, max(-10, vario + randomCentered())) * 0.95;
    alt = max(0, alt * 0.99 + vario);

    return fakeGeoToLoc(FakeGeo(latlng.longitude, latlng.latitude, alt));
  }
}
