import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/path_intercept.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/widgets/elevation_plot.dart';
import 'package:xcnav/widgets/waypoint_marker.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
  });

  final start = DateTime(2026, 1, 1, 12).millisecondsSinceEpoch;
  final geoData = List.generate(20,
      (i) => Geo(lat: 37, lng: -121, alt: 500 + i * 10.0, timestamp: start + i * 30000)..ground = 200 + (i % 5) * 20.0);
  final groundData = List.generate(10, (i) => ElevSample(const LatLng(37, -121), i * 20000.0, 250 + i * 15.0));

  Future pumpPlot(WidgetTester tester, ElevationPlot plot) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 400, height: 300, child: plot))));
  }

  testWidgets("renders track, ground, and pilot icon", (tester) async {
    await pumpPlot(tester, ElevationPlot(geoData, groundData, 100, liveVario: 1.5, liveSpeed: 12));

    expect(tester.takeException(), isNull);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    // past ground, future ground, pilot track, vario trendline
    expect(chart.data.lineBarsData.length, 4);
    expect(chart.data.minX, lessThanOrEqualTo(geoData.first.time));
    expect(chart.data.maxX, greaterThanOrEqualTo(geoData.last.time + groundData.last.dist));
    expect(find.byType(Image), findsOneWidget);
    // vario and glide slope live in the elevation view's instrument row, not next to the pilot
    expect(find.byType(RichText).evaluate().where((e) => (e.widget as RichText).text.toPlainText().contains("/s")),
        isEmpty);
  });

  testWidgets("no trendline when stationary", (tester) async {
    await pumpPlot(tester, ElevationPlot(geoData, const [], 100, liveVario: 0, liveSpeed: 0));

    expect(tester.takeException(), isNull);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.length, 3);
  });

  testWidgets("shows point waypoint marker", (tester) async {
    final wp = Waypoint(name: "test", latlngs: [const LatLng(37.1, -121)]);
    await pumpPlot(
        tester,
        ElevationPlot(geoData, groundData, 100,
            waypoint: wp, waypointETA: ETA(10000, null), liveVario: 0, liveSpeed: 10));

    expect(tester.takeException(), isNull);
    expect(find.byType(WaypointMarker), findsOneWidget);
  });

  testWidgets("waypoint marker follows ground when DEM not loaded", (tester) async {
    final wp = Waypoint(name: "test", latlngs: [const LatLng(37.1, -121)]);
    // 1000m * distScale 100 lands on groundData[5] (elev 325)
    await pumpPlot(
        tester,
        ElevationPlot(geoData, groundData, 100,
            waypoint: wp, waypointETA: ETA(1000, null), liveVario: 0, liveSpeed: 10));

    expect(tester.takeException(), isNull);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final expectedTipY = 300 - 300 * (325 - chart.data.minY) / (chart.data.maxY - chart.data.minY);
    final pin =
        tester.widget<Positioned>(find.ancestor(of: find.byType(WaypointMarker), matching: find.byType(Positioned)));
    expect(pin.top! + 64, closeTo(expectedTipY, 0.01));
  });

  testWidgets("path waypoint traces ground along the path", (tester) async {
    final wp = Waypoint(name: "path", latlngs: [const LatLng(37.01, -121), const LatLng(37.03, -121)]);
    // path starts 300m out (scaled 30000), ends 1500m out (scaled 150000)
    final eta = ETA(1500, null, pathIntercept: PathIntercept(index: 0, latlng: wp.latlng[0], dist: 300));
    await pumpPlot(
        tester, ElevationPlot(geoData, groundData, 100, waypoint: wp, waypointETA: eta, liveVario: 0, liveSpeed: 10));

    expect(tester.takeException(), isNull);
    final path = tester.widget<LineChart>(find.byType(LineChart)).data.lineBarsData.last;
    final x0 = geoData.last.time;
    expect(path.spots.map((e) => e.x - x0).toList(), [30000, 40000, 60000, 80000, 100000, 120000, 140000, 150000]);
    // interior spots follow groundData exactly
    expect(path.spots[1].y, groundData[2].elev);
    expect(path.spots[6].y, groundData[7].elev);
  });

  testWidgets("hides pilot icon", (tester) async {
    await pumpPlot(tester, ElevationPlot(geoData, groundData, 100, showPilotIcon: false, liveVario: 0, liveSpeed: 10));

    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsNothing);
    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.minX, geoData.first.time);
  });
}
