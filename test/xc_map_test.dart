import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/dem_service.dart';
import 'package:xcnav/models/map_camera.dart';
import 'package:xcnav/models/map_shapes.dart';
import 'package:xcnav/views/map/map_markers.dart';
import 'package:xcnav/views/map/map_symbols.dart';
import 'package:xcnav/views/map/xc_map.dart';
import 'package:xcnav/widgets/static_map.dart';

import 'dem_service_test.dart' show demTile;

void main() {
  const center = LatLng(37.5, -122.3);
  const markerPoint = LatLng(37.51, -122.29);

  Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: Align(alignment: Alignment.topLeft, child: SizedBox(width: 400, height: 600, child: child))));

  testWidgets("markers sit on their point and follow the camera", (tester) async {
    expect(XcMap.useFakeMap, true);
    final controller = XcMapController();
    int markerTaps = 0;
    final List<LatLng> mapTaps = [];

    await tester.pumpWidget(host(XcMap(
      controller: controller,
      initialCenter: center,
      initialZoom: 12,
      onTap: (latlng, _) => mapTaps.add(latlng),
      children: [
        MarkerLayer(markers: [
          MapMarker(
              point: markerPoint,
              width: 20,
              height: 30,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                  onTap: () => markerTaps++, child: Container(key: const Key("marker"), color: Colors.red)))
        ])
      ],
    )));
    await tester.pump();

    final camera = controller.camera.value!;
    expect(camera.size, const Size(400, 600));
    expect(camera.center, center);

    // Pin style: bottom center of the marker on the point
    final expected = camera.latLngToScreen(markerPoint)!;
    final rect = tester.getRect(find.byKey(const Key("marker")));
    expect(rect.bottomCenter.dx, closeTo(expected.dx, 0.01));
    expect(rect.bottomCenter.dy, closeTo(expected.dy, 0.01));

    // Taps on the marker don't reach the map
    await tester.tap(find.byKey(const Key("marker")));
    expect(markerTaps, 1);
    expect(mapTaps, isEmpty);

    // Taps elsewhere do, with the right position
    await tester.tapAt(const Offset(100, 500));
    expect(mapTaps.length, 1);
    final tapped = camera.screenToLatLng(const Offset(100, 500))!;
    expect(mapTaps.first.latitude, closeTo(tapped.latitude, 1e-9));
    expect(mapTaps.first.longitude, closeTo(tapped.longitude, 1e-9));

    // Camera moves repaint the markers in their new spots
    await controller.moveTo(center: markerPoint);
    await tester.pump();
    final moved = tester.getRect(find.byKey(const Key("marker")));
    expect(moved.bottomCenter.dx, closeTo(200, 0.01));
    expect(moved.bottomCenter.dy, closeTo(300, 0.01));
  });

  testWidgets("markers off screen aren't painted or hit", (tester) async {
    final controller = XcMapController();
    int taps = 0;
    await tester.pumpWidget(host(XcMap(
      controller: controller,
      initialCenter: center,
      initialZoom: 12,
      children: [
        MarkerLayer(markers: [
          MapMarker(
              point: const LatLng(38.5, -122.3),
              width: 20,
              height: 20,
              child: GestureDetector(onTap: () => taps++, child: Container(key: const Key("far"), color: Colors.red)))
        ])
      ],
    )));
    await tester.pump();
    expect(find.byKey(const Key("far")).hitTestable(), findsNothing);
  });

  testWidgets("dragging a handle reports map positions", (tester) async {
    final controller = XcMapController();
    LatLng point = markerPoint;
    final tracker = MapDragTracker();

    await tester.pumpWidget(host(StatefulBuilder(
        builder: (context, setState) => XcMap(
              controller: controller,
              initialCenter: center,
              initialZoom: 12,
              children: [
                MarkerLayer(markers: [
                  MapMarker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: MapDragHandle(
                          onDragStart: (global) => tracker.start(controller, global, point),
                          onDragUpdate: (global) {
                            final latlng = tracker.update(controller, global);
                            if (latlng != null) setState(() => point = latlng);
                          },
                          onDragEnd: tracker.end,
                          child: Container(key: const Key("handle"), color: Colors.red)))
                ])
              ],
            ))));
    await tester.pump();

    final start = tester.getCenter(find.byKey(const Key("handle")));
    // Grab off center: the point should move by the drag, not jump to the finger
    await tester.dragFrom(start + const Offset(5, 5), const Offset(-60, 80));
    await tester.pump();

    final camera = controller.camera.value!;
    final expected = camera.screenToLatLng(start + const Offset(-60, 80))!;
    expect(point.latitude, closeTo(expected.latitude, 1e-6));
    expect(point.longitude, closeTo(expected.longitude, 1e-6));
    expect(tester.getCenter(find.byKey(const Key("handle"))).dx, closeTo(start.dx - 60, 0.5));
  });

  testWidgets("rotating markers turn with the map", (tester) async {
    final controller = XcMapController();
    await tester.pumpWidget(host(XcMap(
      controller: controller,
      initialCenter: center,
      initialZoom: 12,
      children: [
        MarkerLayer(markers: [
          MapMarker(
              point: center,
              width: 40,
              height: 10,
              rotateWithMap: true,
              child: Container(key: const Key("arrow"), color: Colors.red)),
          MapMarker(point: center, width: 40, height: 10, child: Container(key: const Key("upright"))),
        ])
      ],
    )));
    await tester.pump();
    await controller.moveTo(bearing: 90);
    await tester.pump();

    // A 90 degree turn swaps the box on screen
    final arrow = tester.getRect(find.byKey(const Key("arrow")));
    expect(arrow.width, closeTo(10, 0.01));
    expect(arrow.height, closeTo(40, 0.01));
    final upright = tester.getRect(find.byKey(const Key("upright")));
    expect(upright.width, closeTo(40, 0.01));
    expect(arrow.center, upright.center);
  });

  testWidgets("static map previews fit their bounds", (tester) async {
    final bounds = LatLngBounds(const LatLng(37.0, -122.5), const LatLng(37.5, -122.0));
    await tester.pumpWidget(host(StaticMap(
      bounds: bounds,
      padding: EdgeInsets.zero,
      shapes: [
        ShapeLayer("line", lines: [MapPolyline(points: [bounds.southWest, bounds.northEast], color: Colors.red)])
      ],
      children: [
        MarkerLayer(markers: [
          MapMarker(point: bounds.northEast, width: 10, height: 10, child: Container(key: const Key("ne")))
        ])
      ],
    )));
    await tester.pump();
    // Wider than tall, so it spans the width
    expect(tester.getCenter(find.byKey(const Key("ne"))).dx, closeTo(400, 0.5));
  });

  testWidgets("symbols are drawn by Flutter in tests, and taps reach them", (tester) async {
    final controller = XcMapController();
    int taps = 0;
    int longPresses = 0;
    final List<LatLng> mapTaps = [];
    await tester.pumpWidget(host(XcMap(
      controller: controller,
      initialCenter: center,
      initialZoom: 12,
      onTap: (latlng, _) => mapTaps.add(latlng),
      symbols: [
        SymbolLayer("test", symbols: [
          MapSymbol(
              id: "a",
              point: markerPoint,
              width: 20,
              height: 20,
              imageKey: "a",
              onTap: () => taps++,
              onLongPress: () => longPresses++,
              child: Container(key: const Key("symbol"), color: Colors.red)),
        ]),
      ],
    )));
    await tester.pump();

    final at = tester.getCenter(find.byKey(const Key("symbol")));
    expect(at, offsetMoreOrLessEquals(controller.camera.value!.latLngToScreen(markerPoint)!, epsilon: 0.01));
    await tester.tapAt(at);
    expect(taps, 1);
    await tester.longPressAt(at);
    expect(longPresses, 1);
    expect(mapTaps, isEmpty);
  });

  test("on 3D terrain, points in view sit on the ground", () {
    const camera = MapCamera(center: center, zoom: 12, tilt: 60, size: Size(400, 600), centerElevation: 0);
    final controller = XcMapController.fixed(camera);
    final z = terrainDemZoom(camera.zoom);
    final (x, y) = tileXY(markerPoint, z);
    for (int dx = -1; dx <= 1; dx++) {
      for (int dy = -1; dy <= 1; dy++) {
        debugAddDemTile(x.floor() + dx, y.floor() + dy, z, demTile(1000), 4);
      }
    }

    expect(controller.elevationAt(markerPoint), 1000);
    final screen = controller.latLngToScreen(markerPoint)!;
    expect(screen, camera.latLngToScreen(markerPoint, elevation: 1000));
    expect((screen - camera.latLngToScreen(markerPoint)!).distance, greaterThan(10), reason: "raised off the flat map");
    expect(const Distance().distance(controller.screenToLatLng(screen)!, markerPoint), lessThan(1));

    // Far out of view: not worth loading
    expect(controller.elevationAt(const LatLng(38.5, -122.3)), isNull);
    // Flat map
    expect(XcMapController.fixed(camera.copyWith(flat: true)).elevationAt(markerPoint), isNull);
  });
}
