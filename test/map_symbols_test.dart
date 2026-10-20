import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/views/map/map_layers.dart';
import 'package:xcnav/views/map/map_symbols.dart';

void main() {
  const point = LatLng(37.5, -122.3);

  group("opaqueBounds / cropRgba", () {
    // 4x3, transparent except two pixels
    Uint8List image() {
      final rgba = Uint8List(4 * 3 * 4);
      void set(int x, int y, int value) => rgba.setRange((y * 4 + x) * 4, (y * 4 + x) * 4 + 4, [value, value, value, 255]);
      set(1, 0, 10);
      set(2, 1, 20);
      return rgba;
    }

    test("box around what's visible", () {
      expect(opaqueBounds(image(), 4, 3), const Rect.fromLTRB(1, 0, 3, 2));
      expect(opaqueBounds(Uint8List(4 * 3 * 4), 4, 3), isNull);
    });

    test("crop keeps the pixels in place", () {
      final cropped = cropRgba(image(), 4, const Rect.fromLTRB(1, 0, 3, 2));
      expect(cropped.length, 2 * 2 * 4);
      expect(cropped.sublist(0, 4), [10, 10, 10, 255]);
      expect(cropped.sublist(12, 16), [20, 20, 20, 255]);
      expect(cropped.sublist(4, 8), [0, 0, 0, 0]);
    });
  });

  group("SymbolLayer.toGeoJson", () {
    final image = SymbolImage(
        id: "xc_a", width: 10, height: 10, pixels: Uint8List(400), pixelRatio: 1, offset: const Offset(0, -5));

    test("only symbols with a picture, with how to draw them", () {
      final layer = SymbolLayer("x", symbols: [
        MapSymbol(
            id: "1",
            point: point,
            width: 10,
            height: 10,
            imageKey: "a",
            rotation: 90,
            opacity: 0.5,
            onTap: () {},
            child: const SizedBox()),
        const MapSymbol(id: "2", point: point, width: 10, height: 10, imageKey: "b", child: SizedBox()),
      ]);
      final features = layer.toGeoJson({"a": image})["features"] as List;
      expect(features.length, 1);
      expect(features[0]["geometry"]["coordinates"], [point.longitude, point.latitude]);
      expect(features[0]["properties"],
          {"id": "1", "image": "xc_a", "rotate": 90, "offset": [0, -5], "opacity": 0.5, "tap": true, "longTap": false});
    });
  });

  test("anchor follows the alignment", () {
    MapSymbol symbol(Alignment alignment) =>
        MapSymbol(id: "", point: point, width: 20, height: 40, alignment: alignment, imageKey: "", child: const SizedBox());
    expect(symbol(Alignment.center).anchor, const Offset(10, 20));
    // Pin: sits above the point
    expect(symbol(Alignment.topCenter).anchor, const Offset(10, 40));
    expect(symbol(Alignment.centerRight).anchor, const Offset(0, 20));
  });

  group("drawSymbol", () {
    Widget wrap(Widget child) => Directionality(textDirection: TextDirection.ltr, child: child);

    testWidgets("cropped picture, with the point where it belongs", (tester) async {
      final image = await tester.runAsync(() => drawSymbol(
          const MapSymbol(
              id: "",
              point: point,
              width: 10,
              height: 20,
              alignment: Alignment.topCenter,
              imageKey: "",
              child: ColoredBox(color: Color(0xFFFF0000))),
          2,
          wrap,
          id: "test"));
      expect(image!.id, "xc_test");
      expect(image.width, 20);
      expect(image.height, 40);
      expect(image.pixels.sublist(0, 4), [255, 0, 0, 255]);
      // The point is at the bottom middle: the picture's center is 10 (logical) pixels above it
      expect(image.offset, const Offset(0, -10));
    });

    testWidgets("drawing outside the box, within the overflow", (tester) async {
      final image = await tester.runAsync(() => drawSymbol(
          const MapSymbol(
              id: "",
              point: point,
              width: 10,
              height: 10,
              overflow: EdgeInsets.only(right: 30),
              imageKey: "",
              // A label to the right, nothing in the box itself
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned(left: 20, top: 0, width: 10, height: 10, child: ColoredBox(color: Colors.blue)),
              ])),
          1,
          wrap,
          id: "test"));
      expect(image!.width, 10);
      expect(image.height, 10);
      // Point in the middle of the box, the label 20px to the right of the box's left edge
      expect(image.offset, const Offset(20, 0));
    });

    testWidgets("nothing to see", (tester) async {
      final image = await tester.runAsync(() => drawSymbol(
          const MapSymbol(id: "", point: point, width: 10, height: 10, imageKey: "", child: SizedBox()), 1, wrap,
          id: "test"));
      expect(image, isNull);
    });

    testWidgets("waypoint pins load their svg first", (tester) async {
      // The svg loads in the background
      await tester.runAsync(() => rootBundle.load("assets/images/pin.svg"));
      final symbol = waypointSymbol(Waypoint(name: "test", latlngs: [point]), height: 48);
      final image = await tester.runAsync(() => SymbolImages.instance.get(symbol, 1, wrap));
      expect(image, isNotNull);
      // Pin shape: about as tall as asked, and its tip on the point
      expect(image!.height, closeTo(48, 2));
      expect(image.offset.dy, closeTo(-image.height / 2, 2));
    });
  });
}
