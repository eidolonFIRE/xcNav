import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/util.dart';

void main() {
  // Common Setup
  // setUpAll(() {

  // });

  test("polygonContainsPoint - single point", () {
    const List<LatLng> polygon = [
      LatLng(33, -121),
    ];

    expect(polygonContainsPoint(const LatLng(33, -121), polygon), false);
  });

  test("polygonContainsPoint - triangle", () {
    const List<LatLng> polygon = [
      LatLng(33, -121),
      LatLng(33, -122),
      LatLng(34, -121.5),
    ];

    expect(polygonContainsPoint(const LatLng(35, -122), polygon), false);
    expect(polygonContainsPoint(const LatLng(33.1, -121.5), polygon), true);
    expect(polygonContainsPoint(const LatLng(33.9, -121.1), polygon), false);
    expect(polygonContainsPoint(const LatLng(33.1, -121.1), polygon), false);
  });
}
