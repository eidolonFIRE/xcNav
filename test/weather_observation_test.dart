import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/weather_observation_service.dart';

void main() {
  test("iterTiles - 1x1", () {
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(10, 10), const LatLng(10.1, 10.1))).toList();
    expect(tiles, const [Point(50, 50)]);
  });

  test("iterTiles - 2x1", () {
    /// 3 skips
    ///   s
    /// s X +
    ///   s
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(0, 0), const LatLng(1.01 / 5, 0.99 / 5)))
            .toList();
    expect(tiles, const [Point(0, 0), Point(1, 0)]);
  });

  test("iterTiles - 3x1", () {
    /// 2 skips
    ///   s
    /// + X +
    ///   s
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(-0.9 / 5, 0), const LatLng(1.01 / 5, 0.99 / 5)))
            .toList();
    expect(tiles, const [Point(0, 0), Point(1, 0), Point(-1, 0)]);
  });

  test("iterTiles - 4x1", () {
    /// 9 skips
    ///     s
    ///   s s s
    /// s + X + +
    ///   s s s
    ///     s
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(-0.9 / 5, 0), const LatLng(2.01 / 5, 0.99 / 5)))
            .toList();
    expect(tiles, const [Point(0, 0), Point(1, 0), Point(-1, 0), Point(2, 0)]);
  });

  test("iterTiles - 5x1", () {
    /// 8 skips
    ///     s
    ///   s s s
    /// + + X + +
    ///   s s s
    ///     s
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(-1.9 / 5, 0), const LatLng(2.01 / 5, 0.99 / 5)))
            .toList();
    expect(tiles, const [Point(0, 0), Point(1, 0), Point(-1, 0), Point(2, 0), Point(-2, 0)]);
  });

  test("iterTiles - 1x2", () {
    /// 3 skips
    ///   +
    /// s X s
    ///   s
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(10, 10), const LatLng(10.1, 10.3))).toList();
    expect(tiles, const [Point(50, 50), Point(50, 51)]);
  });

  test("iterTiles - 2x2", () {
    /// 5 skips, 4 clips
    ///     -
    ///   s + +
    /// - s X + -
    ///   s s s
    ///     -
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(10, 10), const LatLng(10.3, 10.3))).toList();
    expect(tiles, const [Point(50, 50), Point(51, 50), Point(50, 51), Point(51, 51)]);
  });

  test("iterTiles - 3x2", () {
    /// 3 skips
    ///
    ///   + + +
    ///   + X +
    ///   s s s
    ///
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(-0.9 / 5, 0), const LatLng(1.01 / 5, 1.01 / 5)))
            .toList();
    expect(tiles, const [Point(0, 0), Point(1, 0), Point(0, 1), Point(-1, 0), Point(1, 1), Point(-1, 1)]);
  });

  test("iterTiles - 4x2", () {
    /// 13 skips
    ///   s s s
    /// s + + + +
    /// s + X + +
    /// s s s s s
    ///   s s s
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(-0.9 / 5, 0), const LatLng(2.01 / 5, 1.01 / 5)))
            .toList();
    expect(tiles, const [
      Point(0, 0),
      Point(1, 0),
      Point(0, 1),
      Point(-1, 0),
      Point(2, 0),
      Point(1, 1),
      Point(-1, 1),
      Point(2, 1)
    ]);
  });

  test("iterTiles - 5x2", () {
    /// 11 skips
    ///   s s s
    /// + + + + +
    /// + + X + +
    /// s s s s s
    ///   s s s
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(-1.9 / 5, 0), const LatLng(2.01 / 5, 1.01 / 5)))
            .toList();
    expect(tiles, const [
      Point(0, 0),
      Point(1, 0),
      Point(0, 1),
      Point(-1, 0),
      Point(2, 0),
      Point(-2, 0),
      Point(1, 1),
      Point(-1, 1),
      Point(2, 1),
      Point(-2, 1)
    ]);
  });

  test("iterTiles - 3x3", () {
    /// No skips, 4 clips
    ///     -
    ///   + + +
    /// - + X + -
    ///   + + +
    ///     -
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(9.8, 9.8), const LatLng(10.3, 10.3))).toList();
    expect(tiles, const [
      Point(50, 50),
      Point(51, 50),
      Point(50, 51),
      Point(49, 50),
      Point(50, 49),
      Point(51, 51),
      Point(49, 51),
      Point(49, 49),
      Point(51, 49)
    ]);
  });

  test("iterTiles - 4x3", () {
    /// 9 skips, 4 clips
    ///       -
    ///     s s s
    ///   s + + + +
    /// - s + X + + -
    ///   s + + + +
    ///     s s s
    ///       -
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(9.8, 9.8), const LatLng(10.4, 10.3))).toList();
    expect(tiles, const [
      Point(50, 50),
      Point(51, 50),
      Point(50, 51),
      Point(49, 50),
      Point(50, 49),
      Point(52, 50),
      Point(51, 51),
      Point(49, 51),
      Point(49, 49),
      Point(51, 49),
      Point(52, 51),
      Point(52, 49)
    ]);
  });

  test("iterTiles - 3x4", () {
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(9.8, 9.8), const LatLng(10.3, 10.4))).toList();
    expect(tiles, const [
      Point(50, 50),
      Point(51, 50),
      Point(50, 51),
      Point(49, 50),
      Point(50, 49),
      Point(50, 52),
      Point(51, 51),
      Point(49, 51),
      Point(49, 49),
      Point(51, 49),
      Point(49, 52),
      Point(51, 52)
    ]);
  });

  test("iterTiles - 4x4", () {
    /// 9 skips
    ///
    ///   s + + + +
    ///   s + + + +
    ///   s + X + +
    ///   s + + + +
    ///   s s s s s
    ///
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(-1 / 5, -1 / 5), const LatLng(2.9 / 5, 2.9 / 5)))
            .toList();
    expect(tiles, const [
      Point(0, 0),
      Point(1, 0),
      Point(0, 1),
      Point(-1, 0),
      Point(0, -1),
      Point(2, 0),
      Point(0, 2),
      Point(1, 1),
      Point(-1, 1),
      Point(-1, -1),
      Point(1, -1),
      Point(2, 1),
      Point(-1, 2),
      Point(1, 2),
      Point(2, -1),
      Point(2, 2)
    ]);
  });

  test("iterTiles - 5x5", () {
    /// 0 skips
    ///
    ///   + + + + +
    ///   + + + + +
    ///   + + X + +
    ///   + + + + +
    ///   + + + + +
    ///
    final tiles =
        WeatherObservationService.iterTiles(LatLngBounds(const LatLng(-2 / 5, -2 / 5), const LatLng(2.9 / 5, 2.9 / 5)))
            .toList();
    expect(tiles, const [
      Point(0, 0),
      Point(1, 0),
      Point(0, 1),
      Point(-1, 0),
      Point(0, -1),
      Point(2, 0),
      Point(0, 2),
      Point(-2, 0),
      Point(0, -2),
      Point(1, 1),
      Point(-1, 1),
      Point(-1, -1),
      Point(1, -1),
      Point(2, 1),
      Point(-1, 2),
      Point(-2, -1),
      Point(1, -2),
      Point(1, 2),
      Point(-2, 1),
      Point(-1, -2),
      Point(2, -1),
      Point(2, 2),
      Point(-2, 2),
      Point(-2, -2),
      Point(2, -2)
    ]);
  });
}
