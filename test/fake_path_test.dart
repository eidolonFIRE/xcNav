import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/fake_path.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/units.dart';

void main() {
  group("parseTargetAlt", () {
    test("feet", () {
      expect(FakeFlight.parseTargetAlt("name 1000ft"), closeTo(1000 / meters2Feet, 0.001));
      expect(FakeFlight.parseTargetAlt("name 1000 FT"), closeTo(1000 / meters2Feet, 0.001));
    });

    test("meters", () {
      expect(FakeFlight.parseTargetAlt("ridge 300m"), 300);
      expect(FakeFlight.parseTargetAlt("ridge 12.5 m"), 12.5);
    });

    test("last match wins", () {
      expect(FakeFlight.parseTargetAlt("100m then 2000ft"), closeTo(2000 / meters2Feet, 0.001));
    });

    test("no altitude", () {
      expect(FakeFlight.parseTargetAlt("Launch 3:15 PM"), isNull);
      expect(FakeFlight.parseTargetAlt("home"), isNull);
      expect(FakeFlight.parseTargetAlt("100mph"), isNull);
      expect(FakeFlight.parseTargetAlt("left"), isNull);
    });
  });

  group("target altitude", () {
    Geo prevGeo() => Geo(lat: 37, lng: -122, alt: 0)..ground = 0;

    test("climb limited to 800ft/min", () {
      final flight = FakeFlight();
      flight.initFakeFlight(Geo(lat: 37, lng: -122, alt: 100));
      for (int i = 0; i < 10; i++) {
        final before = flight.alt;
        flight.genFakeLocationFlight(const LatLng(37.1, -122), prevGeo(), targetAlt: 2000);
        expect((flight.alt - before) / FakeFlight.stepSeconds, lessThanOrEqualTo(FakeFlight.maxClimb + 0.2));
        expect(flight.vario, closeTo(FakeFlight.maxClimb, 0.001));
      }
      expect(FakeFlight.maxClimb * 60 * meters2Feet, closeTo(800, 0.001));
    });

    test("descent limited to 7:1 glide", () {
      final flight = FakeFlight();
      flight.initFakeFlight(Geo(lat: 37, lng: -122, alt: 2000));
      for (int i = 0; i < 10; i++) {
        flight.genFakeLocationFlight(const LatLng(37.1, -122), prevGeo(), targetAlt: 100);
        expect(flight.vario, closeTo(-flight.spd / FakeFlight.glideRatio, 0.001));
      }
    });

    test("settles at target", () {
      final flight = FakeFlight();
      flight.initFakeFlight(Geo(lat: 37, lng: -122, alt: 100));
      for (int i = 0; i < 200; i++) {
        flight.genFakeLocationFlight(const LatLng(37.1, -122), prevGeo(), targetAlt: 300);
      }
      expect(flight.alt, closeTo(300, 3));
    });
  });
}
