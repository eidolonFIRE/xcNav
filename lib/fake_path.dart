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

  /// Degrees
  double hdg = 0;

  // Wind
  late double windSpd;
  late double windHdg;

  @override
  FakeFlight() {
    rand = Random(DateTime.now().millisecondsSinceEpoch);

    initFakeFlight(Geo());
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

    windSpd = rand.nextDouble() * 3 + 2;
    windHdg = rand.nextDouble() * 360;

    debugPrint("Fake Wind: $windSpd, $windHdg");
  }

  Position genFakeLocationFlight(LatLng? target, Geo prevGeo) {
    debugPrint("Gen fake path...");
    if (target != null) {
      final delta = ((latlngCalc.bearing(latlng, target)) - hdg + 180) % (360) - 180;
      // debugPrint("Delta Degrees to Target $delta");
      hdg += randomCentered() * 5 + min(15.0, max(-15.0, delta)) * (rand.nextDouble() + 0.2);
    } else {
      hdg += randomCentered() * 30 + 10;
    }

    latlng = latlngCalc.offset(latlng, (spd + randomCentered()) * 3, hdg + randomCentered());
    latlng = latlngCalc.offset(latlng, windSpd * 3 + randomCentered(), windHdg + randomCentered());

    vario = min(6, max(-7, vario + randomCentered() / 2)) * 0.99;
    if (alt < 1) vario = randomCentered() + 1;
    if (alt - (prevGeo.ground ?? 0) < 500) vario += 0.1;
    if (alt - (prevGeo.ground ?? 0) > 4000) vario -= 0.1;
    alt = max(prevGeo.ground ?? 0, alt * 0.99999 + vario) + randomCentered() * 2;

    return fakeGeoToLoc(FakeGeo(latlng.longitude, latlng.latitude, alt));
  }
}
