import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

void main() {
  // Common Setup
  // setUpAll(() {

  // });

  test("hash", () {
    final Map<WaypointID, Waypoint> waypoints = {};

    waypoints["1"] = (Waypoint(newId: "1", name: "test", latlngs: [LatLng(37.3, -121.123456789)]));
    expect(hashWaypointsData(waypoints), "8ebbbb");
    waypoints["2a"] = (Waypoint(newId: "2a", name: "", latlngs: [LatLng(3, 1), LatLng(1, 0)], color: 0, icon: "PATH"));
    expect(hashWaypointsData(waypoints), "b8e2af");
  });

  test("segment lengths", () {
    final waypoint =
        Waypoint(name: "", latlngs: [LatLng(37, -121), LatLng(36.5, -121), LatLng(36.5, -121.5), LatLng(37, -121.25)]);
    expect(waypoint.lengthBetweenIndexs(0, 3), closeTo(160091.44, 0.01));
    expect(waypoint.lengthBetweenIndexs(0, 1), closeTo(55486.48, 0.01));
    expect(waypoint.lengthBetweenIndexs(2, 3), closeTo(59809.46, 0.01));

    // flip the path around
    waypoint.toggleDirection();
    expect(waypoint.lengthBetweenIndexs(0, 3), closeTo(160091.44, 0.01));
    expect(waypoint.lengthBetweenIndexs(2, 3), closeTo(55486.48, 0.01));
    expect(waypoint.lengthBetweenIndexs(0, 1), closeTo(59809.46, 0.01));
  });

  test("interpolate", () {
    final waypoint =
        Waypoint(name: "", latlngs: [LatLng(37, -121), LatLng(36.5, -121), LatLng(36.5, -121.5), LatLng(37, -121.25)]);
    expect(waypoint.interpolate(0, 0).hdg, closeTo(3.14, 0.01));
    expect(waypoint.interpolate(0, 0).latlng.toString(), "LatLng(latitude:37.0, longitude:-121.0)");
    expect(waypoint.interpolate(10000, 0).hdg, closeTo(3.14, 0.01));
    expect(waypoint.interpolate(10000, 0).latlng.toString(), "LatLng(latitude:36.909891, longitude:-121.0)");
    expect(waypoint.interpolate(50000, 0).hdg, closeTo(3.14, 0.01));
    expect(waypoint.interpolate(50000, 0).latlng.toString(), "LatLng(latitude:36.549442, longitude:-121.0)");
    expect(waypoint.interpolate(100000, 0).hdg, closeTo(-1.56, 0.01));
    expect(waypoint.interpolate(100000, 0).latlng.toString(), "LatLng(latitude:36.500007, longitude:-121.496853)");
    expect(waypoint.interpolate(200000, 0).hdg, closeTo(0.37, 0.01));
    expect(waypoint.interpolate(200000, 0).latlng.toString(), "LatLng(latitude:37.333815, longitude:-121.082915)");

    expect(waypoint.interpolate(0, 1).hdg, closeTo(3.14, 0.01));
    expect(waypoint.interpolate(0, 1).latlng.toString(), "LatLng(latitude:36.5, longitude:-121.0)");
    expect(waypoint.interpolate(10000, 1).hdg, closeTo(-1.56, 0.01));
    expect(waypoint.interpolate(10000, 1).latlng.toString(), "LatLng(latitude:36.500182, longitude:-121.111618)");
    expect(waypoint.interpolate(50000, 1).hdg, closeTo(0.37, 0.01));
    expect(waypoint.interpolate(50000, 1).latlng.toString(), "LatLng(latitude:36.543557, longitude:-121.478454)");
    expect(waypoint.interpolate(100000, 1).hdg, closeTo(0.37, 0.01));
    expect(waypoint.interpolate(100000, 1).latlng.toString(), "LatLng(latitude:36.961801, longitude:-121.270223)");

    expect(waypoint.interpolate(0, 2).hdg, closeTo(-1.56, 0.01));
    expect(waypoint.interpolate(0, 2).latlng.toString(), "LatLng(latitude:36.5, longitude:-121.5)");
    expect(waypoint.interpolate(50000, 2).hdg, closeTo(0.37, 0.01));
    expect(waypoint.interpolate(50000, 2).latlng.toString(), "LatLng(latitude:36.918284, longitude:-121.292003)");

    expect(waypoint.interpolate(0, 3).hdg, closeTo(0.37, 0.01));
    expect(waypoint.interpolate(0, 3).latlng.toString(), "LatLng(latitude:37.000301, longitude:-121.25093)");
    expect(waypoint.interpolate(10000, 3).hdg, closeTo(0.37, 0.01));
    expect(waypoint.interpolate(10000, 3).latlng.toString(), "LatLng(latitude:37.083894, longitude:-121.208969)");
  });

  test("interpolate with initial start latlng", () {
    final initial = LatLng(37.25, -121);
    final waypoint =
        Waypoint(name: "", latlngs: [LatLng(37, -121), LatLng(36.5, -121), LatLng(36.5, -121.5), LatLng(37, -121.25)]);
    expect(waypoint.interpolate(0, 0, initialLatlng: initial).hdg, closeTo(3.14, 0.01));
    expect(waypoint.interpolate(0, 0, initialLatlng: initial).latlng.toString(),
        "LatLng(latitude:37.25, longitude:-121.0)");
    expect(waypoint.interpolate(10000, 0, initialLatlng: initial).hdg, closeTo(3.14, 0.01));
    expect(waypoint.interpolate(10000, 0, initialLatlng: initial).latlng.toString(),
        "LatLng(latitude:37.159895, longitude:-121.0)");
    expect(waypoint.interpolate(100000, 0, initialLatlng: initial).hdg, closeTo(-1.56, 0.01));
    expect(waypoint.interpolate(100000, 0, initialLatlng: initial).latlng.toString(),
        "LatLng(latitude:36.500245, longitude:-121.187167)");
    expect(waypoint.interpolate(200000, 0, initialLatlng: initial).hdg, closeTo(0.37, 0.01));
    expect(waypoint.interpolate(200000, 0, initialLatlng: initial).latlng.toString(),
        "LatLng(latitude:37.101978, longitude:-121.199878)");

    expect(waypoint.interpolate(100000, 1, initialLatlng: initial).hdg, closeTo(-1.56, 0.01));
    expect(waypoint.interpolate(100000, 1, initialLatlng: initial).latlng.toString(),
        "LatLng(latitude:36.500245, longitude:-121.187167)");

    expect(waypoint.interpolate(50000, 2, initialLatlng: initial).hdg, closeTo(-2.64, 0.01));
    expect(waypoint.interpolate(50000, 2, initialLatlng: initial).latlng.toString(),
        "LatLng(latitude:36.852721, longitude:-121.265114)");

    expect(waypoint.interpolate(50000, 3, initialLatlng: initial).hdg, closeTo(0.37, 0.01));
    expect(waypoint.interpolate(50000, 3, initialLatlng: initial).latlng.toString(),
        "LatLng(latitude:37.121141, longitude:-121.19024)");
  });

  test("Eta - Point", () {
    final waypoint = Waypoint(name: "", latlngs: [LatLng(37, -121)]);
    final eta = waypoint.eta(Geo(lat: 37.2, lng: -121), 10);
    expect(eta.distance, closeTo(22195.9, 0.1));
    expect(eta.time?.inSeconds, closeTo(2219, 0.1));
    expect(eta.pathIntercept?.index, 0);
    expect(eta.pathIntercept?.dist, closeTo(22195.9, 0.1));
    expect(eta.pathIntercept?.latlng.toString(), "LatLng(latitude:37.0, longitude:-121.0)");
  });

  test("Eta - Path", () {
    final waypoint = Waypoint(name: "", latlngs: [LatLng(37, -121.1), LatLng(37, -121.2)]);
    final eta = waypoint.eta(Geo(lat: 37.2, lng: -121), 10);
    expect(eta.distance, closeTo(32811.01, 0.1));
    expect(eta.time?.inSeconds, closeTo(3281, 0.1));
    expect(eta.pathIntercept?.index, 0);
    expect(eta.pathIntercept?.dist, closeTo(23909.85, 0.1));
    expect(eta.pathIntercept?.latlng.toString(), "LatLng(latitude:37.0, longitude:-121.1)");

    waypoint.toggleDirection();

    final eta2 = waypoint.eta(Geo(lat: 37.2, lng: -121), 10);
    expect(eta2.distance, closeTo(23909.85, 0.1));
    expect(eta2.time?.inSeconds, closeTo(2390, 0.1));
    expect(eta2.pathIntercept?.index, 1);
    expect(eta2.pathIntercept?.dist, closeTo(23909.85, 0.1));
    expect(eta2.pathIntercept?.latlng.toString(), "LatLng(latitude:37.0, longitude:-121.1)");
  });
}
