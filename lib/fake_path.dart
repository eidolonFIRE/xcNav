import 'dart:math';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:xcnav/models/geo.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

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
    altitudeAccuracy: 0.0,
    headingAccuracy: 0.0,
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

  /// Parse a target altitude (MSL meters) from a waypoint name such as "name 1000ft" or "ridge 300m".
  /// The last match in the name wins.
  static double? parseTargetAlt(String name) {
    final matches = RegExp(r'(\d+(?:\.\d+)?)\s*(ft|m)\b', caseSensitive: false).allMatches(name);
    if (matches.isEmpty) return null;
    final match = matches.last;
    final value = double.parse(match.group(1)!);
    return match.group(2)!.toLowerCase() == "ft" ? value / meters2Feet : value;
  }

  /// Seconds between fake samples
  static const double stepSeconds = 3;

  /// Max climb rate: 800 ft/min
  static const double maxClimb = 800 / meters2Feet / 60;

  /// Glide ratio used when descending to a target altitude
  static const double glideRatio = 7;

  /// Vario (m/s) to fly toward [targetAlt], limited to [maxClimb] climb and a 7:1 glide.
  double varioToTargetAlt(double targetAlt) {
    final delta = targetAlt - alt;
    final maxSink = spd / glideRatio;
    // Ease in over the final step(s) so we don't oscillate around the target
    return min(maxClimb, max(-maxSink, delta / (stepSeconds * 2)));
  }

  Position genFakeLocationFlight(LatLng? target, Geo prevGeo, {double? targetAlt}) {
    // debugPrint("Gen fake path...");
    if (target != null) {
      final delta = ((latlngCalc.bearing(latlng, target)) - hdg + 180) % (360) - 180;
      // debugPrint("Delta Degrees to Target $delta");
      hdg += randomCentered() * 5 + min(15.0, max(-15.0, delta)) * (rand.nextDouble() + 0.2);
    } else {
      hdg += randomCentered() * 30 + 10;
    }

    latlng = latlngCalc.offset(latlng, (spd + randomCentered()) * 3, hdg + randomCentered());
    latlng = latlngCalc.offset(latlng, windSpd * 3 + randomCentered(), windHdg + randomCentered());

    if (targetAlt != null) {
      vario = varioToTargetAlt(targetAlt);
      alt = max(prevGeo.ground ?? 0, alt + vario * stepSeconds) + randomCentered() * 0.5;
    } else {
      vario = min(6, max(-7, vario + randomCentered() / 2)) * 0.99;
      if (alt < 1) vario = randomCentered() + 1;
      if (alt - (prevGeo.ground ?? 0) < 100) vario += 0.1;
      if (alt - (prevGeo.ground ?? 0) > 500) vario -= 0.1;
      alt = max(prevGeo.ground ?? 0, alt * 0.99999 + vario) + randomCentered() * 2;
    }

    return fakeGeoToLoc(FakeGeo(latlng.longitude, latlng.latitude, alt));
  }
}
