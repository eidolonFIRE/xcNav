import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/airspace.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/services/openaip_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/widgets/elevation_plot.dart';

/// Square from (37, -122) to (38, -121), shaped like an OpenAIP v2 core API item.
Map<String, dynamic> openAipItem(
    {String name = "TEST CLASS C",
    int type = 0,
    int icaoClass = 2,
    Map<String, dynamic>? lower,
    Map<String, dynamic>? upper,
    double west = -122,
    double east = -121}) {
  return {
    "_id": "abc123",
    "name": name,
    "type": type,
    "icaoClass": icaoClass,
    "geometry": {
      "type": "Polygon",
      "coordinates": [
        [
          [west, 37.0],
          [east, 37.0],
          [east, 38.0],
          [west, 38.0],
          [west, 37.0],
        ]
      ]
    },
    "lowerLimit": lower ?? {"value": 1200, "unit": 1, "referenceDatum": 0},
    "upperLimit": upper ?? {"value": 45, "unit": 6, "referenceDatum": 2},
  };
}

void main() {
  group("AltLimit", () {
    test("converts units and datum", () {
      final agl = AltLimit.fromOpenAip({"value": 1000, "unit": 1, "referenceDatum": 0})!;
      expect(agl.toMsl(100), closeTo(404.8, 0.01));
      expect(agl.toString(), "1000ft AGL");

      final msl = AltLimit.fromOpenAip({"value": 500, "unit": 0, "referenceDatum": 1})!;
      expect(msl.toMsl(100), 500);
      expect(msl.toString(), "500m MSL");

      final fl = AltLimit.fromOpenAip({"value": 65, "unit": 6, "referenceDatum": 2})!;
      expect(fl.toMsl(100), closeTo(1981.2, 0.01));
      expect(fl.toString(), "FL65");

      const gnd = AltLimit(0, AltLimitUnit.feet, AltLimitDatum.gnd);
      expect(gnd.toString(), "GND");
      expect(gnd.toMsl(100), 100);
    });

    test("rejects bad data", () {
      expect(AltLimit.fromOpenAip(null), isNull);
      expect(AltLimit.fromOpenAip({"unit": 1}), isNull);
    });
  });

  group("Airspace", () {
    test("parses OpenAIP item", () {
      final airspace = Airspace.fromOpenAip(openAipItem())!;
      expect(airspace.name, "TEST CLASS C");
      expect(airspace.label, "Class C");
      // closing point dropped
      expect(airspace.points.length, 4);
      expect(airspace.points.first, const LatLng(37, -122));
      expect(airspace.containsPoint(const LatLng(37.5, -121.5)), isTrue);
      expect(airspace.containsPoint(const LatLng(36.5, -121.5)), isFalse);
      expect(airspace.isRelevant, isTrue);
    });

    test("rejects bad geometry", () {
      expect(Airspace.fromOpenAip({...openAipItem(), "geometry": null}), isNull);
      expect(
          Airspace.fromOpenAip({
            ...openAipItem(),
            "geometry": {
              "type": "Polygon",
              "coordinates": [
                [
                  [0, 0],
                  [1, 1]
                ]
              ]
            }
          }),
          isNull);
    });

    test("filters irrelevant airspace", () {
      // FIR
      expect(Airspace.fromOpenAip(openAipItem(type: 10))!.isRelevant, isFalse);
      // Alert Area
      expect(Airspace.fromOpenAip(openAipItem(type: 17, icaoClass: 8))!.isRelevant, isFalse);
      // Class A, starts at FL180
      expect(
          Airspace.fromOpenAip(openAipItem(icaoClass: 0, lower: {"value": 180, "unit": 6, "referenceDatum": 2}))!
              .isRelevant,
          isFalse);
    });

    test("only shows class E down to the surface", () {
      final classESurface = openAipItem(type: 4, icaoClass: 4, lower: {"value": 0, "unit": 1, "referenceDatum": 0});
      expect(Airspace.fromOpenAip(classESurface)!.isRelevant, isTrue);
      expect(Airspace.fromOpenAip(classESurface)!.dashed, isTrue);
      final classE700 = openAipItem(type: 26, icaoClass: 4, lower: {"value": 700, "unit": 1, "referenceDatum": 0});
      expect(Airspace.fromOpenAip(classE700)!.isRelevant, isFalse);
      final classE1200 = openAipItem(type: 26, icaoClass: 4, lower: {"value": 1200, "unit": 1, "referenceDatum": 0});
      expect(Airspace.fromOpenAip(classE1200)!.isRelevant, isFalse);
      final classEMsl = openAipItem(type: 26, icaoClass: 4, lower: {"value": 5500, "unit": 1, "referenceDatum": 1});
      expect(Airspace.fromOpenAip(classEMsl)!.isRelevant, isFalse);
    });

    test("simplifies dense outlines", () {
      // 1000 vertex circle, ~5km radius
      final circle =
          List.generate(1000, (i) => [-121.5 + 0.05 * cos(i * 2 * pi / 1000), 37.5 + 0.04 * sin(i * 2 * pi / 1000)]);
      final airspace = Airspace.fromOpenAip({
        ...openAipItem(),
        "geometry": {
          "type": "Polygon",
          "coordinates": [
            [...circle, circle.first]
          ]
        }
      })!;
      expect(airspace.points.length, lessThan(100));
      expect(airspace.points.length, greaterThan(10));
      expect(airspace.containsPoint(const LatLng(37.5, -121.5)), isTrue);
    });

    test("json round trip", () {
      final airspace = Airspace.fromOpenAip(openAipItem())!;
      final copy = Airspace.fromJson(jsonDecode(jsonEncode(airspace.toJson())));
      expect(copy.name, airspace.name);
      expect(copy.type, airspace.type);
      expect(copy.icaoClass, airspace.icaoClass);
      expect(copy.points, airspace.points);
      expect(copy.lower.toString(), airspace.lower.toString());
      expect(copy.upper.toString(), airspace.upper.toString());
    });
  });

  group("airspaceCrossSection", () {
    final airspace = Airspace.fromOpenAip(openAipItem(lower: {"value": 100, "unit": 0, "referenceDatum": 0}))!;

    test("splits into continuous runs and applies ground to AGL limits", () {
      // in, in, out, in
      final probes = [
        const AirspaceProbe(0, LatLng(37.5, -121.8), 10),
        const AirspaceProbe(1, LatLng(37.5, -121.5), 20),
        const AirspaceProbe(2, LatLng(37.5, -120.5), 30),
        const AirspaceProbe(3, LatLng(37.5, -121.2), 40),
      ];
      final sections = airspaceCrossSection(probes, [airspace]);
      expect(sections.length, 2);
      expect(sections[0].points.map((e) => e.x), [0, 1]);
      expect(sections[0].points.map((e) => e.bottom), [110, 120]);
      expect(sections[0].points.first.top, closeTo(4500 * 0.3048, 0.01));
      expect(sections[1].points.map((e) => e.x), [3]);
    });

    test("skips far away airspace", () {
      final probes = [const AirspaceProbe(0, LatLng(10, 10), 0)];
      expect(airspaceCrossSection(probes, [airspace]), isEmpty);
    });
  });

  group("OpenAipService", () {
    test("fetches all pages from the v2 API", () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        final page = int.parse(request.url.queryParameters["page"]!);
        return http.Response(
            jsonEncode({
              "page": page,
              "limit": 1000,
              "totalCount": 3,
              "totalPages": 2,
              if (page == 1) "nextPage": 2,
              "items": page == 1 ? [openAipItem(), openAipItem(type: 10)] : [openAipItem(name: "SECOND")],
            }),
            200);
      });
      final service = OpenAipService(apiKey: "test-key", client: client);
      final result = await service.fetchAirspaces(const LatLng(37.5, -121.5));

      expect(result!.map((e) => e.name), ["TEST CLASS C", "TEST CLASS C", "SECOND"]);
      expect(requests.length, 2);
      expect(requests.first.url.host, "api.core.openaip.net");
      expect(requests.first.url.path, "/api/airspaces");
      expect(requests.first.url.queryParameters["pos"], "37.5000,-121.5000");
      expect(requests.first.headers["x-openaip-api-key"], "test-key");
    });

    test("keeps paging on a full page without nextPage", () async {
      final pages = <int>[];
      final client = MockClient((request) async {
        final page = int.parse(request.url.queryParameters["page"]!);
        pages.add(page);
        return http.Response(
            jsonEncode({
              "page": page,
              "limit": 1000,
              "items": List.generate(page == 1 ? 1000 : 5, (_) => openAipItem()),
            }),
            200);
      });
      final result =
          await OpenAipService(apiKey: "test-key", client: client).fetchAirspaces(const LatLng(37.5, -121.5));
      expect(pages, [1, 2]);
      expect(result!.length, 1005);
    });

    test("returns null on error", () async {
      final service = OpenAipService(apiKey: "test-key", client: MockClient((_) async => http.Response("nope", 401)));
      expect(await service.fetchAirspaces(const LatLng(37.5, -121.5)), isNull);
    });
  });

  group("ElevationPlot", () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    });

    testWidgets("draws airspace cross section", (tester) async {
      final start = DateTime(2026, 1, 1, 12).millisecondsSinceEpoch;
      final geoData = List.generate(
          20, (i) => Geo(lat: 37.5, lng: -121.5, alt: 500 + i * 10.0, timestamp: start + i * 30000)..ground = 200);
      final groundData = List.generate(10, (i) => ElevSample(LatLng(37.5, -121.5 + i * 0.1), i * 20000.0, 250));
      final airspace = Airspace.fromOpenAip(openAipItem(lower: {"value": 2500, "unit": 1, "referenceDatum": 1}))!;

      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SizedBox(
                  width: 400,
                  height: 300,
                  child:
                      ElevationPlot(geoData, groundData, 100, airspaces: [airspace], liveVario: 0, liveSpeed: 10)))));

      expect(tester.takeException(), isNull);
      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter.runtimeType.toString() == "_AirspacePainter"),
          findsOneWidget);
    });
  });
}
