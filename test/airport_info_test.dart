import 'dart:convert';

import 'package:clock/clock.dart';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/dialogs/airport_info.dart';
import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/services/openaip_service.dart';
import 'package:xcnav/settings_service.dart';

import 'test_localization.dart';

/// Shaped like an OpenAIP v2 core API `/api/airports` item.
Map<String, dynamic> openAipAirport({String name = "PALO ALTO", String? icao = "KPAO", int type = 0}) => {
      "_id": "apt1",
      "name": name,
      if (icao != null) "icaoCode": icao,
      "type": type,
      "geometry": {
        "type": "Point",
        "coordinates": [-122.115, 37.461]
      },
      "elevation": {"value": 2, "unit": 0, "referenceDatum": 1},
      "frequencies": [
        {"value": "121.300", "unit": 2, "type": 0, "name": "NORCAL APPROACH", "primary": false, "publicUse": true},
        {"value": "118.600", "unit": 2, "type": 14, "name": "PALO ALTO TOWER", "primary": true, "publicUse": true},
        {"value": "120.600", "unit": 2, "type": 15, "name": "ATIS", "primary": false, "publicUse": true},
      ],
    };

void main() {
  group("AirportInfo", () {
    test("parses OpenAIP item", () {
      final airport = AirportInfo.fromOpenAip(openAipAirport())!;
      expect(airport.name, "PALO ALTO");
      expect(airport.code, "KPAO");
      expect(airport.shortName, "KPAO");
      expect(airport.latlng, const LatLng(37.461, -122.115));
      expect(airport.elevation, 2);
      expect(airport.hasTower, isTrue);
      // local traffic first (primary tower before ATIS), approach last
      expect(airport.frequencies.map((e) => e.value), ["118.600", "120.600", "121.300"]);
      expect(airport.frequencies.first.typeName, "Tower");
    });

    test("falls back to name without a code", () {
      final airport = AirportInfo.fromOpenAip(openAipAirport(name: "GRASS STRIP", icao: null))!;
      expect(airport.code, isNull);
      expect(airport.shortName, "GRASS STRIP");
    });

    test("hides heliports and closed airports", () {
      expect(AirportInfo.fromOpenAip(openAipAirport(type: 2))!.isRelevant, isTrue);
      expect(AirportInfo.fromOpenAip(openAipAirport(type: 7))!.isRelevant, isFalse);
      expect(AirportInfo.fromOpenAip(openAipAirport(type: 4))!.isRelevant, isFalse);
      expect(AirportInfo.fromOpenAip(openAipAirport(type: 8))!.isRelevant, isFalse);
    });

    test("rejects bad geometry", () {
      expect(AirportInfo.fromOpenAip({...openAipAirport(), "geometry": null}), isNull);
    });

    test("json round trip", () {
      final airport = AirportInfo.fromOpenAip(openAipAirport())!;
      final copy = AirportInfo.fromJson(jsonDecode(jsonEncode(airport.toJson())));
      expect(copy.name, airport.name);
      expect(copy.code, airport.code);
      expect(copy.latlng, airport.latlng);
      expect(copy.elevation, airport.elevation);
      expect(copy.frequencies.map((e) => "${e.value} ${e.type} ${e.name} ${e.primary}"),
          airport.frequencies.map((e) => "${e.value} ${e.type} ${e.name} ${e.primary}"));
    });
  });

  test("OpenAipService fetches airports from the v2 API", () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response(
          jsonEncode({
            "page": 1,
            "limit": 1000,
            "items": [openAipAirport()]
          }),
          200);
    });
    final result = await OpenAipService(apiKey: "test-key", client: client).fetchAirports(const LatLng(37.5, -121.5));
    expect(result!.single.code, "KPAO");
    expect(requests.single.path, "/api/airports");
  });

  test("OpenAipService keeps data for 30 days", () async {
    int requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response(jsonEncode({"page": 1, "limit": 1000, "items": []}), 200);
    });
    final service = OpenAipService(apiKey: "test-key", client: client);
    const center = LatLng(37.5, -121.5);
    final start = DateTime(2026, 1, 1);

    await withClock(Clock.fixed(start), () => service.refresh(center));
    // airspaces + airports
    expect(requests, 2);

    await withClock(Clock.fixed(start.add(const Duration(days: 29))), () => service.refresh(center));
    expect(requests, 2);

    await withClock(Clock.fixed(start.add(const Duration(days: 31))), () => service.refresh(center));
    expect(requests, 4);
  });

  group("Airport dialog", () {
    setUpAll(() async {
      await initTestLocalization();
      settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    });

    testWidgets("shows name and frequencies, adds waypoint", (tester) async {
      final airport = AirportInfo.fromOpenAip(openAipAirport())!;
      int added = 0;
      await tester.pumpWidget(testLocalization(
          child: Builder(
              builder: (context) => MaterialApp(
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  home: Scaffold(
                      body: Builder(
                          builder: (context) => TextButton(
                              onPressed: () => showAirportInfoDialog(context, airport, onAddWaypoint: () => added++),
                              child: const Text("open"))))))));
      await tester.pumpAndSettle();
      await tester.tap(find.text("open"));
      await tester.pumpAndSettle();

      expect(find.textContaining("PALO ALTO  KPAO", findRichText: true), findsOneWidget);
      expect(find.text("118.600"), findsOneWidget);
      expect(find.text("Tower"), findsOneWidget);
      expect(find.text("PALO ALTO TOWER"), findsOneWidget);

      await tester.tap(find.byKey(const Key("airportInfo_addWaypoint")));
      await tester.pumpAndSettle();
      expect(added, 1);
      expect(find.text("118.600"), findsNothing);
    });
  });
}
