import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'dart:math';

const _meters2Feet = 3.28084;

class FakeGeo {
  FakeGeo(this.lng, this.lat, this.alt);

  double lng;
  double lat;
  double alt;
}

LocationData fakeGeoToLoc(FakeGeo geo) {
  return LocationData.fromMap({
    "latitude": geo.lat,
    "longitude": geo.lng,
    "altitude": geo.alt,
    "time": DateTime.now().millisecondsSinceEpoch.toDouble()
  });
}

class FakeFlight {
  // Create a fake flight track
  // FakeGeo prev_e = null;
  Random rand = Random();

  late double randPhaseA;
  late double randPhaseB;
  late FakeGeo fakeCenter;
  bool fake_in_flight = false;
  double fake_in_flight_timer = 10;
  double mainPhase = 0;
  double fake_ground = 66 / _meters2Feet;

  late double lat;
  late double lng;
  late double alt;

  @override
  FakeFlight() {
    randPhaseA = rand.nextDouble() / 100;
    randPhaseB = rand.nextDouble() * 3.15159;
    fakeCenter = FakeGeo(-121.2971, 37.6738, fake_ground);
    lat = fakeCenter.lat;
    lng = fakeCenter.lng;
    alt = fake_ground;
  }

  double randomCentered() {
    return rand.nextDouble() * 2 - 1;
  }

  LocationData genFakeLocationFlight() {
    fake_in_flight_timer -= 1;
    if (fake_in_flight_timer <= 0) {
      fake_in_flight = !fake_in_flight;
      if (fake_in_flight) {
        // duration in the air
        fake_in_flight_timer = rand.nextInt(40) + 60;
      } else {
        // duration on the ground
        fake_in_flight_timer = rand.nextInt(10) + 20;
      }
    }

    if (fake_in_flight) {
      mainPhase += 0.016;
      if (fake_in_flight_timer > 30) {
        alt += (rand.nextDouble() + 1) * 5;
      } else if (fake_in_flight_timer < 10) {
        alt = max(fake_ground, alt * 0.9 - 100);
      }
    } else {
      fakeCenter.lat += randomCentered() / 20000.0;
      fakeCenter.lng += randomCentered() / 20000.0;
    }

    lat = fakeCenter.lat +
        sin(mainPhase + randPhaseA) /
            70 *
            (sin(mainPhase * 10.0 + randPhaseB) / 20 + 1);
    lng = fakeCenter.lng +
        cos(mainPhase + randPhaseA) /
            50 *
            (sin(mainPhase * 10.0 + randPhaseB) / 20 + 1);

    return fakeGeoToLoc(FakeGeo(lng, lat, alt));
  }
}
