import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:xcnav/models/geoid.dart';

Position _pos(double lat, double lng, double alt, {bool hasAltitude = true}) => Position(
      longitude: lng,
      latitude: lat,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      accuracy: 5,
      altitude: alt,
      altitudeAccuracy: 3,
      headingAccuracy: 1,
      heading: 90,
      speed: 10,
      speedAccuracy: 1,
      hasAltitude: hasAltitude,
    );

void main() {
  final grid = GeoidGrid.fromBytes(ByteData.sublistView(File(geoidAssetPath).readAsBytesSync()));

  test("grid dimensions", () {
    expect(grid.rows, 361);
    expect(grid.cols, 720);
    expect(grid.step, 0.5);
  });

  test("matches full-resolution EGM96", () {
    // Reference: bilinear on GeographicLib egm96-15.pgm. 0.5 deg grid max error is ~4 m.
    const refs = [
      (0.0, 0.0, 17.16),
      (39.74, -104.99, -16.98), // Denver
      (46.5, 7.9, 50.60), // Alps
      (4.7, 78.8, -106.96), // Indian Ocean low
      (-8.4, 147.4, 84.69), // New Guinea high
      (-33.9, 151.2, 22.30), // Sydney
      (90.0, 0.0, 13.61),
      (-90.0, 0.0, -29.53),
    ];
    for (final (lat, lon, n) in refs) {
      expect(grid.height(lat, lon), closeTo(n, 2.0), reason: "$lat, $lon");
    }
  });

  test("longitude wraps", () {
    expect(grid.height(10, -0.1), closeTo(grid.height(10, 359.9), 1e-9));
    expect(grid.height(10, 180), closeTo(grid.height(10, -180), 1e-9));
  });

  test("ellipsoidToMsl subtracts geoid height", () {
    final out = ellipsoidToMsl(_pos(39.74, -104.99, 1600), grid: grid);
    expect(out.altitude, closeTo(1600 + 16.98, 2.0));
    expect(out.latitude, 39.74);
    expect(out.longitude, -104.99);
    expect(out.heading, 90);
    expect(out.speed, 10);
    expect(out.timestamp, DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
  });

  test("ellipsoidToMsl leaves fix without altitude alone", () {
    final p = _pos(39.74, -104.99, 0, hasAltitude: false);
    expect(ellipsoidToMsl(p, grid: grid), same(p));
  });
}
