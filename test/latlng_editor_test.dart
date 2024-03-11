import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:patrol_finders/patrol_finders.dart';
import 'package:xcnav/widgets/latlng_editor.dart';

void main() {
  Future setup(PatrolTester $, void Function(List<LatLng>) callback) async {
    await $.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LatLngEditor(onLatLngs: callback),
        ),
      ),
    );
  }

  patrolWidgetTest('basic', ($) async {
    List<LatLng> results = [];
    await setup($, (latlngs) {
      results = latlngs;
    });

    await $(TextFormField).enterText("");
    await $.waitUntilExists($("Lat, Long"));
    expect(results, []);

    await $(TextFormField).enterText("45, 123");
    await $.waitUntilExists($("45, 123"));
    expect(results, [const LatLng(45, 123)]);

    await $(TextFormField).enterText("0.45, 123");
    expect(results, [const LatLng(0.45, 123)]);

    await $(TextFormField).enterText("   0.45   ,    123   ");
    expect(results, [const LatLng(0.45, 123)]);
  });

  patrolWidgetTest('multiple', ($) async {
    List<LatLng> results = [];
    await setup($, (latlngs) {
      results = latlngs;
    });

    await $(TextFormField).enterText("");
    await $.waitUntilExists($("Lat, Long"));
    expect(results, []);

    await $(TextFormField).enterText("45, 123.45; -15,  -170;");
    expect(results, [const LatLng(45, 123.45), const LatLng(-15, -170)]);

    await $(TextFormField).enterText("45, 123.45; -15,  -170");
    expect(results, [const LatLng(45, 123.45), const LatLng(-15, -170)]);
  });

  patrolWidgetTest('bad_format', ($) async {
    List<LatLng> results = [];
    await setup($, (latlngs) {
      results = latlngs;
    });

    await $(TextFormField).enterText("");
    await $.waitUntilExists($("Lat, Long"));
    expect(results, []);

    await $(TextFormField).enterText(".2");
    await $.waitUntilExists($("Unrecognized Format"));
    expect(results, []);

    await $(TextFormField).enterText("0.2,, 123");
    await $.waitUntilExists($("Unrecognized Format"));
    expect(results, []);

    await $(TextFormField).enterText("12 123");
    await $.waitUntilExists($("Unrecognized Format"));
    expect(results, []);

    await $(TextFormField).enterText("--12, 123;");
    await $.waitUntilExists($("Unrecognized Format"));
    expect(results, []);
  });
}
