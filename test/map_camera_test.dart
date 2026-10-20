import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/map_camera.dart';

void main() {
  const size = Size(400, 800);
  const center = LatLng(37.5, -122.3);

  Matcher closeToLatLng(LatLng expected, {double tolerance = 1e-7}) => predicate<LatLng?>(
      (actual) =>
          actual != null &&
          (actual.latitude - expected.latitude).abs() < tolerance &&
          (actual.longitude - expected.longitude).abs() < tolerance,
      "close to $expected");

  group("LatLngBounds", () {
    test("corners in any order", () {
      final bounds = LatLngBounds(const LatLng(10, 20), const LatLng(5, 25));
      expect(bounds.north, 10);
      expect(bounds.south, 5);
      expect(bounds.east, 25);
      expect(bounds.west, 20);
      expect(bounds.center, const LatLng(7.5, 22.5));
    });

    test("fromPoints / contains / extend", () {
      final bounds = LatLngBounds.fromPoints([const LatLng(1, 1), const LatLng(-1, 3), const LatLng(0, 2)]);
      expect(bounds.southWest, const LatLng(-1, 1));
      expect(bounds.northEast, const LatLng(1, 3));
      expect(bounds.contains(const LatLng(0, 2)), true);
      expect(bounds.contains(const LatLng(2, 2)), false);
      bounds.extend(const LatLng(2, 2));
      expect(bounds.contains(const LatLng(2, 2)), true);
      expect(bounds.isOverlapping(LatLngBounds(const LatLng(1.5, 2.5), const LatLng(5, 5))), true);
      expect(bounds.isOverlapping(LatLngBounds(const LatLng(5, 5), const LatLng(6, 6))), false);
    });
  });

  group("mercator", () {
    test("round trip", () {
      for (final p in [const LatLng(0, 0), center, const LatLng(-45.1, 170.2), const LatLng(80, -179)]) {
        expect(unprojectMercator(projectMercator(p)), closeToLatLng(p));
      }
    });

    test("world corners", () {
      expect(projectMercator(const LatLng(0, -180)), const Offset(0, mapWorldTileSize / 2));
      expect(projectMercator(const LatLng(0, 0)), const Offset(mapWorldTileSize / 2, mapWorldTileSize / 2));
    });
  });

  group("MapCamera projection", () {
    test("center is in the middle of the screen", () {
      for (final cam in [
        const MapCamera(center: center, zoom: 10, size: size),
        const MapCamera(center: center, zoom: 10, bearing: 37, tilt: 50, size: size),
      ]) {
        final p = cam.latLngToScreen(center)!;
        expect(p.dx, closeTo(200, 1e-6));
        expect(p.dy, closeTo(400, 1e-6));
      }
    });

    test("north up, flat: one world pixel per screen pixel", () {
      const cam = MapCamera(center: center, zoom: 12, size: size);
      final east = const Distance().offset(center, 1000, 90);
      final p = cam.latLngToScreen(east)!;
      expect(p.dy, closeTo(400, 0.5));
      // 1km east, at this latitude and zoom
      expect(p.dx - 200, closeTo(1000 / cam.metersPerPixel, 1));
    });

    test("bearing turns the map", () {
      // Heading east: east is straight up the screen, north is to the left
      const cam = MapCamera(center: center, zoom: 12, bearing: 90, size: size);
      final east = cam.latLngToScreen(const Distance().offset(center, 1000, 90))!;
      expect(east.dx, closeTo(200, 0.5));
      expect(east.dy, lessThan(400));
      final north = cam.latLngToScreen(const Distance().offset(center, 1000, 0))!;
      expect(north.dy, closeTo(400, 0.5));
      expect(north.dx, lessThan(200));
    });

    test("tilt: nearby (bottom) looks bigger than far away (top)", () {
      const cam = MapCamera(center: center, zoom: 12, tilt: 50, size: size);
      final north = cam.latLngToScreen(const Distance().offset(center, 1000, 0))!;
      final south = cam.latLngToScreen(const Distance().offset(center, 1000, 180))!;
      expect(400 - north.dy, lessThan(south.dy - 400));
      // Points straight ahead stay on the center line
      expect(north.dx, closeTo(200, 1e-6));
    });

    test("screenToLatLng inverts latLngToScreen", () {
      final rand = Random(1);
      for (int i = 0; i < 50; i++) {
        final cam = MapCamera(
            center: center,
            zoom: 5 + rand.nextDouble() * 12,
            bearing: rand.nextDouble() * 360,
            tilt: rand.nextDouble() * 60,
            size: size);
        final screen = Offset(rand.nextDouble() * size.width, rand.nextDouble() * size.height);
        final latlng = cam.screenToLatLng(screen);
        expect(latlng, isNotNull);
        final back = cam.latLngToScreen(latlng!)!;
        expect((back - screen).distance, lessThan(1e-3), reason: "$cam $screen");
      }
    });

    test("isOnScreen", () {
      const cam = MapCamera(center: center, zoom: 12, size: size);
      expect(cam.isOnScreen(center), true);
      expect(cam.isOnScreen(const Distance().offset(center, 100000, 0)), false);
    });

    test("terrain exaggeration scales heights", () {
      const plain = MapCamera(center: center, zoom: 12, tilt: 60, size: size, centerElevation: 100);
      final tall = plain.copyWith(terrainExaggeration: 1.5);
      final point = const Distance().offset(center, 2000, 0);
      // 300m above the center, drawn 1.5 times as tall, looks like 450m above it
      final screen = tall.latLngToScreen(point, elevation: 400)!;
      expect((screen - plain.latLngToScreen(point, elevation: 550)!).distance, lessThan(1e-9));
      expect(tall.screenToLatLng(screen, elevationAt: (_) => 400), closeToLatLng(point, tolerance: 1e-6));
    });

    test("isNearView leaves out the distance toward the horizon", () {
      const cam = MapCamera(center: center, zoom: 12, tilt: 75, size: size);
      final ws = cam.worldSize;
      LatLng offset(Offset world) =>
          unprojectMercator(projectMercator(center, worldSize: ws) + world, worldSize: ws);
      // The camera is 1.5 screen heights (1200px) from the center
      expect(cam.isNearView(offset(const Offset(0, -2400))), true);
      expect(cam.isOnScreen(offset(const Offset(0, -4800))), true);
      expect(cam.isNearView(offset(const Offset(0, -4800))), false);
      // Off screen, unless within the margin
      expect(cam.isNearView(offset(const Offset(250, 0))), false);
      expect(cam.isNearView(offset(const Offset(250, 0)), margin: 100), true);
    });

    test("visibleBounds holds the screen corners", () {
      const cam = MapCamera(center: center, zoom: 10, bearing: 30, size: size);
      final bounds = cam.visibleBounds;
      for (final corner in [Offset.zero, const Offset(400, 0), const Offset(400, 800), const Offset(0, 800)]) {
        final p = cam.screenToLatLng(corner)!;
        expect(bounds.contains(p), true);
      }
      expect(bounds.contains(center), true);
    });
  });

  group("MapCamera.fit", () {
    final bounds = LatLngBounds(const LatLng(37.0, -122.5), const LatLng(37.5, -122.0));

    test("bounds fit inside the padding", () {
      for (final bearing in [0.0, 45.0]) {
        final cam = MapCamera.fit(bounds, size, padding: const EdgeInsets.all(20), bearing: bearing);
        for (final corner in [bounds.northWest, bounds.northEast, bounds.southEast, bounds.southWest]) {
          final p = cam.latLngToScreen(corner)!;
          expect(p.dx, inInclusiveRange(19.9, 380.1), reason: "bearing $bearing");
          expect(p.dy, inInclusiveRange(19.9, 780.1), reason: "bearing $bearing");
        }
      }
    });

    test("snug on the limiting side", () {
      final cam = MapCamera.fit(bounds, size, padding: const EdgeInsets.all(20));
      final west = cam.latLngToScreen(bounds.northWest)!.dx;
      final east = cam.latLngToScreen(bounds.northEast)!.dx;
      // Box is wider than tall on a tall screen: width fills the space
      expect(east - west, closeTo(360, 0.5));
    });

    test("uneven padding shifts the center", () {
      final cam = MapCamera.fit(bounds, size, padding: const EdgeInsets.only(left: 100));
      final west = cam.latLngToScreen(bounds.northWest)!.dx;
      final east = cam.latLngToScreen(bounds.northEast)!.dx;
      expect(west, closeTo(100, 0.5));
      expect(east, closeTo(400, 0.5));
    });

    test("single point uses max zoom", () {
      final cam = MapCamera.fit(LatLngBounds(center, center), size, maxZoom: 13);
      expect(cam.zoom, 13);
      expect(cam.center, closeToLatLng(center));
    });
  });

  test("tileXY / tileToLatLng", () {
    final (x, y) = tileXY(center, 10);
    final nw = tileToLatLng(x.floor(), y.floor(), 10);
    final se = tileToLatLng(x.floor() + 1, y.floor() + 1, 10);
    expect(LatLngBounds(nw, se).contains(center), true);
  });
}
