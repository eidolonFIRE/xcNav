import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/views/map/poly_editor.dart';
import 'package:xcnav/views/map/xc_map.dart';

void main() {
  const a = LatLng(37.0, -122.0);
  const b = LatLng(37.0, -121.9);
  const c = LatLng(37.1, -121.9);

  test("cssColor", () {
    expect(cssColor(const Color(0xFFFF0000)), "rgba(255,0,0,1.000)");
    expect(cssColor(Colors.black.withAlpha(128)), "rgba(0,0,0,0.502)");
  });

  group("ShapeLayer.toGeoJson", () {
    test("polygons become a fill plus an outline", () {
      final geo = const ShapeLayer("x", polygons: [
        MapPolygon(
            points: [a, b, c],
            fillColor: Colors.red,
            borderColor: Colors.blue,
            borderWidth: 2,
            borderPattern: LinePattern.dashed,
            hitValue: "p1")
      ]).toGeoJson();
      final features = geo["features"] as List;
      expect(features.length, 2);

      final fill = features[0];
      expect(fill["geometry"]["type"], "Polygon");
      final ring = fill["geometry"]["coordinates"][0] as List;
      expect(ring.length, 4, reason: "ring is closed");
      expect(ring.first, [a.longitude, a.latitude], reason: "GeoJSON is lng, lat");
      expect(fill["properties"]["kind"], "fill");
      expect(fill["properties"]["hit"], "p1");

      final outline = features[1];
      expect(outline["geometry"]["type"], "LineString");
      expect(outline["properties"]["pattern"], "dashed");
      expect(outline["properties"]["width"], 2);
    });

    test("lines carry their style", () {
      final geo = const ShapeLayer("x", lines: [
        MapPolyline(points: [a, b], color: Colors.amber, width: 4, borderColor: Colors.black, borderWidth: 1),
        MapPolyline(points: [a], color: Colors.amber),
      ]).toGeoJson();
      final features = geo["features"] as List;
      expect(features.length, 1, reason: "single point lines are skipped");
      final props = features[0]["properties"];
      expect(props["kind"], "line");
      expect(props["width"], 4);
      expect(props["border"], 1);
      expect(props["borderColor"], cssColor(Colors.black));
      expect(props["pattern"], "solid");
    });

    test("no border means border width 0", () {
      final geo = const ShapeLayer("x", lines: [MapPolyline(points: [a, b], color: Colors.amber, borderWidth: 3)])
          .toGeoJson();
      expect((geo["features"] as List)[0]["properties"]["border"], 0.0);
    });
  });

  group("hitTestLines", () {
    const camera = MapCamera(center: LatLng(37.05, -121.95), zoom: 11, size: Size(400, 400));
    const layer = ShapeLayer("x", lines: [
      MapPolyline(points: [a, b], color: Colors.red, hitValue: "bottom"),
      MapPolyline(points: [b, c], color: Colors.red, hitValue: "right"),
      MapPolyline(points: [a, c], color: Colors.red),
    ]);

    test("hits near the line", () {
      final mid = camera.latLngToScreen(const LatLng(37.0, -121.95))!;
      expect(layer.hitTestLines(camera, mid + const Offset(0, 5)), ["bottom"]);
      expect(layer.hitTestLines(camera, mid + const Offset(0, 40)), isEmpty);
    });

    test("top-most first", () {
      final corner = camera.latLngToScreen(b)!;
      expect(layer.hitTestLines(camera, corner), ["right", "bottom"]);
    });

    test("lines without a hit value are ignored", () {
      final diag = camera.latLngToScreen(const LatLng(37.05, -121.95))!;
      expect(layer.hitTestLines(camera, diag), isEmpty);
    });
  });

  test("distanceToSegment", () {
    expect(distanceToSegment(const Offset(5, 5), Offset.zero, const Offset(10, 0)), 5);
    expect(distanceToSegment(const Offset(-3, 4), Offset.zero, const Offset(10, 0)), 5);
    expect(distanceToSegment(const Offset(3, 4), Offset.zero, Offset.zero), 5);
  });

  test("circlePoints", () {
    final ring = circlePoints(a, 1000, segments: 16);
    expect(ring.length, 16);
    for (final p in ring) {
      expect(const Distance().distance(a, p), closeTo(1000, 1));
    }
  });

  group("MapPolyEditor", () {
    test("handles for corners and midpoints", () {
      final points = [a, b, c];
      int changes = 0;
      final editor = MapPolyEditor(
          points: points, pointIcon: const SizedBox(), intermediateIcon: const SizedBox(), onChanged: () => changes++);
      final controller = XcMapController();
      expect(editor.edit(controller).length, 3 + 2);

      final closed = MapPolyEditor(
          points: points, pointIcon: const SizedBox(), intermediateIcon: const SizedBox(), closed: true);
      expect(closed.edit(controller).length, 3 + 3);

      editor.add(points, const LatLng(37.2, -121.8));
      expect(points.length, 4);
      editor.remove(0);
      expect(points, [b, c, const LatLng(37.2, -121.8)]);
      expect(changes, 2);
    });

    test("handle keys stay unique", () {
      final points = [a, b, c];
      final editor = MapPolyEditor(points: points, pointIcon: const SizedBox(), intermediateIcon: const SizedBox());
      final keys = editor.edit(XcMapController()).map((e) => e.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });
}
