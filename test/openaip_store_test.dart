// ObjectBox tests need the native library. On desktop, get it with ObjectBox's install script:
//   bash <(curl -s https://raw.githubusercontent.com/objectbox/objectbox-dart/main/install.sh)
// or put `objectbox.dll` / `libobjectbox.so` / `libobjectbox.dylib` (objectbox-c 4.3.1) into `lib/`.
// Without it, the ObjectBox group is skipped.

import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/airport_info.dart';
import 'package:xcnav/models/airspace.dart';
import 'package:xcnav/services/openaip_service.dart';
import 'package:xcnav/services/openaip_store.dart';

const bayArea = LatLng(37.5, -122.0);
const reno = LatLng(39.5, -119.8);

Airspace square(String id, LatLng center, {double size = 0.1, String? name}) => Airspace(
        id: id,
        name: name ?? id,
        type: 4,
        icaoClass: 3,
        lower: const AltLimit(0, AltLimitUnit.feet, AltLimitDatum.gnd),
        upper: const AltLimit(2500, AltLimitUnit.feet, AltLimitDatum.msl),
        points: [
          LatLng(center.latitude - size, center.longitude - size),
          LatLng(center.latitude - size, center.longitude + size),
          LatLng(center.latitude + size, center.longitude + size),
          LatLng(center.latitude + size, center.longitude - size),
        ]);

AirportInfo airport(String id, LatLng latlng, {String name = "AIRPORT"}) => AirportInfo(
    id: id,
    name: name,
    code: id.toUpperCase(),
    type: 2,
    latlng: latlng,
    elevation: 12,
    private: true,
    frequencies: const [AirportFrequency(value: "122.800", type: 4, name: "CTAF", primary: true)]);

final everywhere = LatLngBoundsSimple.around(const LatLng(38, -121), 1000000);

void storeTests(String name, Future<OpenAipStore> Function() makeStore) {
  group(name, () {
    late OpenAipStore store;
    final t0 = DateTime(2026, 1, 1);

    setUp(() async => store = await makeStore());
    tearDown(() => store.close());

    test("round trips airspaces and airports", () {
      store.putDownload(
          center: bayArea,
          radius: 150000,
          downloadedAt: t0,
          airspaces: [square("a1", bayArea, name: "PALO ALTO CLASS D")],
          airports: [airport("kpao", bayArea, name: "PALO ALTO")]);

      final a = store.airspacesIn(everywhere).single;
      expect(a.id, "a1");
      expect(a.name, "PALO ALTO CLASS D");
      expect(a.type, 4);
      expect(a.icaoClass, 3);
      expect(a.lower.toString(), "GND");
      expect(a.upper.toString(), "2500ft MSL");
      expect(a.points, square("a1", bayArea).points);

      final p = store.airportsIn(everywhere).single;
      expect(p.code, "KPAO");
      expect(p.name, "PALO ALTO");
      expect(p.latlng, bayArea);
      expect(p.elevation, 12);
      expect(p.private, isTrue);
      expect(p.frequencies.single.value, "122.800");
      expect(p.frequencies.single.typeName, "CTAF");
    });

    test("queries by area", () {
      store.putDownload(
          center: bayArea,
          radius: 150000,
          downloadedAt: t0,
          airspaces: [square("bay", bayArea), square("reno", reno)],
          airports: [airport("bay", bayArea), airport("reno", reno)]);

      final nearBay = LatLngBoundsSimple.around(bayArea, 50000);
      expect(store.airspacesIn(nearBay).map((e) => e.id), ["bay"]);
      expect(store.airportsIn(nearBay).map((e) => e.id), ["bay"]);
      // overlapping, but not containing
      expect(store.airspacesIn(LatLngBoundsSimple(37.65, 37.55, -121.95, -122.05)).map((e) => e.id), ["bay"]);
    });

    test("finds recent areas near a point", () {
      store.putDownload(center: bayArea, radius: 150000, downloadedAt: t0, airspaces: [], airports: []);

      expect(store.areaNear(bayArea, 75000, t0), isNotNull);
      expect(store.areaNear(const LatLng(37.6, -122.1), 75000, t0), isNotNull);
      expect(store.areaNear(reno, 75000, t0), isNull);
      expect(store.areaNear(bayArea, 75000, t0.add(const Duration(days: 1))), isNull);
    });

    test("grows with new areas", () {
      store.putDownload(
          center: bayArea,
          radius: 150000,
          downloadedAt: t0,
          airspaces: [square("bay", bayArea)],
          airports: [airport("bay", bayArea)]);
      store.putDownload(
          center: reno,
          radius: 150000,
          downloadedAt: t0.add(const Duration(days: 1)),
          airspaces: [square("reno", reno)],
          airports: [airport("reno", reno)]);

      expect(store.areaCount, 2);
      expect(store.airspacesIn(everywhere).map((e) => e.id).toSet(), {"bay", "reno"});
      expect(store.airportsIn(everywhere).map((e) => e.id).toSet(), {"bay", "reno"});
      expect(store.areaNear(bayArea, 75000, t0), isNotNull);
      expect(store.areaNear(reno, 75000, t0), isNotNull);
    });

    test("re-download replaces, removes deleted items, and keeps items outside", () {
      store.putDownload(
          center: bayArea,
          radius: 150000,
          downloadedAt: t0,
          airspaces: [square("keep", bayArea, name: "OLD NAME"), square("deleted", bayArea), square("reno", reno)],
          airports: [airport("keep", bayArea), airport("deleted", bayArea), airport("reno", reno)]);

      store.putDownload(
          center: bayArea,
          radius: 150000,
          downloadedAt: t0.add(const Duration(days: 31)),
          airspaces: [square("keep", bayArea, name: "NEW NAME")],
          airports: [airport("keep", bayArea)]);

      expect(store.airspaceCount, 2);
      expect(store.airspacesIn(everywhere).map((e) => e.id).toSet(), {"keep", "reno"});
      expect(store.airspacesIn(everywhere).firstWhere((e) => e.id == "keep").name, "NEW NAME");
      expect(store.airportsIn(everywhere).map((e) => e.id).toSet(), {"keep", "reno"});
      // the old area record is covered by the new one
      expect(store.areaCount, 1);
    });

    test("clear", () {
      store.putDownload(
          center: bayArea,
          radius: 150000,
          downloadedAt: t0,
          airspaces: [square("bay", bayArea)],
          airports: [airport("bay", bayArea)]);
      store.clear();
      expect(store.airspaceCount, 0);
      expect(store.airportCount, 0);
      expect(store.areaCount, 0);
    });
  });
}

void main() {
  storeTests("MemoryOpenAipStore", () async => MemoryOpenAipStore());

  // --- ObjectBox
  final tempDirs = <Directory>[];
  Future<ObjectBoxOpenAipStore> openTemp() async {
    final dir = Directory.systemTemp.createTempSync("openaip_test");
    tempDirs.add(dir);
    return ObjectBoxOpenAipStore.open(dir.path);
  }

  tearDownAll(() {
    for (final dir in tempDirs) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group("ObjectBox", () {
    storeTests("ObjectBoxOpenAipStore", openTemp);

    test("persists between sessions", () async {
      final first = await openTemp();
      final dir = tempDirs.last;
      first.putDownload(
          center: bayArea,
          radius: 150000,
          downloadedAt: DateTime(2026, 1, 1),
          airspaces: [square("bay", bayArea)],
          airports: [airport("bay", bayArea)]);
      first.close();

      final second = await ObjectBoxOpenAipStore.open(dir.path);
      expect(second.airspacesIn(everywhere).single.id, "bay");
      expect(second.airportsIn(everywhere).single.id, "bay");
      expect(second.areaNear(bayArea, 75000, DateTime(2026, 1, 1)), isNotNull);
      second.close();
    });
  }, skip: !_objectBoxLibPresent() ? "ObjectBox native library not installed" : null);

  // --- Service using the store
  group("OpenAipService", () {
    int requests = 0;
    http.Response respond(http.Request request) {
      final pos = request.url.queryParameters["pos"]!.split(",").map(double.parse).toList();
      final center = LatLng(pos[0], pos[1]);
      final items = request.url.path.endsWith("airspaces")
          ? [_aipAirspace("as_${request.url.queryParameters["pos"]}", center)]
          : [_aipAirport("ap_${request.url.queryParameters["pos"]}", center)];
      return http.Response(jsonEncode({"page": 1, "limit": 1000, "items": items}), 200);
    }

    final client = MockClient((request) async {
      requests++;
      return respond(request);
    });
    setUp(() {
      requests = 0;
      SharedPreferences.setMockInitialValues({});
    });

    test("uses cached data without a network", () async {
      final store = MemoryOpenAipStore()
        ..putDownload(
            center: bayArea,
            radius: 150000,
            downloadedAt: DateTime(2026, 1, 1),
            airspaces: [square("bay", bayArea)],
            airports: [airport("bay", bayArea)]);
      final service = OpenAipService(apiKey: "unset", client: client, store: store);
      await withClock(Clock.fixed(DateTime(2027, 1, 1)), () => service.refresh(bayArea));
      expect(requests, 0);
      expect(service.airspaces.single.id, "bay");
      expect(service.airports.single.id, "bay");
    });

    test("stores everything, shows only relevant", () async {
      final classE1200 = Airspace(
          id: "e1200",
          name: "CLASS E",
          type: 26,
          icaoClass: 4,
          lower: const AltLimit(1200, AltLimitUnit.feet, AltLimitDatum.gnd),
          upper: const AltLimit(180, AltLimitUnit.flightLevel, AltLimitDatum.std),
          points: square("e1200", bayArea).points);
      final store = MemoryOpenAipStore()
        ..putDownload(
            center: bayArea,
            radius: 150000,
            downloadedAt: DateTime(2026, 1, 1),
            airspaces: [square("bay", bayArea), classE1200],
            airports: []);
      final service = OpenAipService(apiKey: "unset", client: client, store: store);
      await service.refresh(bayArea);
      expect(store.airspaceCount, 2);
      expect(service.airspaces.map((e) => e.id), ["bay"]);
    });

    test("keeps earlier areas when flying somewhere new", () async {
      final store = MemoryOpenAipStore();
      final service = OpenAipService(apiKey: "test-key", client: client, store: store);
      final t0 = DateTime(2026, 1, 1);

      await withClock(Clock.fixed(t0), () => service.refresh(bayArea));
      expect(requests, 2);
      expect(service.airspaces.length, 1);

      await withClock(Clock.fixed(t0.add(const Duration(hours: 1))), () => service.refresh(reno));
      expect(requests, 4);
      expect(service.airspaces.length, 1);
      expect(store.areaCount, 2);
      expect(store.airspaceCount, 2);

      // Back in the bay area: no download, data comes from the store.
      await withClock(Clock.fixed(t0.add(const Duration(days: 29))), () => service.refresh(bayArea));
      expect(requests, 4);
      expect(service.airspaces.single.points.first.latitude, closeTo(bayArea.latitude - 0.1, 0.001));

      // Stale after 30 days
      await withClock(Clock.fixed(t0.add(const Duration(days: 31))), () => service.refresh(bayArea));
      expect(requests, 6);
    });

    test("backs off when rate limited, and remembers it after a restart", () async {
      int limited = 0;
      final rateLimited = MockClient((request) async {
        limited++;
        return http.Response("Too Many Requests", 429);
      });
      final t0 = DateTime(2026, 1, 1);
      final service = OpenAipService(
          apiKey: "test-key", client: rateLimited, store: MemoryOpenAipStore(), rateLimitWait: Duration.zero);

      await withClock(Clock.fixed(t0), () => service.refresh(bayArea));
      // retries, then stops after the first endpoint fails
      expect(limited, 4);
      await withClock(Clock.fixed(t0.add(const Duration(minutes: 9))), () => service.refresh(bayArea));
      expect(limited, 4);
      await withClock(Clock.fixed(t0.add(const Duration(minutes: 11))), () => service.refresh(bayArea));
      expect(limited, 8);
      // doubled: next try 20 minutes after the second failure
      await withClock(Clock.fixed(t0.add(const Duration(minutes: 30))), () => service.refresh(bayArea));
      expect(limited, 8);
      await withClock(Clock.fixed(t0.add(const Duration(minutes: 32))), () => service.refresh(bayArea));
      expect(limited, 12);

      // A fresh service (app restart) still waits
      await Future.delayed(Duration.zero);
      final restarted = OpenAipService(
          apiKey: "test-key", client: rateLimited, store: MemoryOpenAipStore(), rateLimitWait: Duration.zero);
      await restarted.init();
      await withClock(Clock.fixed(t0.add(const Duration(minutes: 40))), () => restarted.refresh(bayArea));
      expect(limited, 12);
    });

    test("retries a short rate limit", () async {
      int calls = 0;
      final flaky = MockClient((request) async {
        calls++;
        if (calls == 1) return http.Response("Too Many Requests", 429);
        return respond(request);
      });
      final service =
          OpenAipService(apiKey: "test-key", client: flaky, store: MemoryOpenAipStore(), rateLimitWait: Duration.zero);
      await withClock(Clock.fixed(DateTime(2026, 1, 1)), () => service.refresh(bayArea));
      expect(calls, 3);
      expect(service.airspaces, isNotEmpty);
      expect(service.airports, isNotEmpty);
    });

    test("honors Retry-After", () async {
      int limited = 0;
      final rateLimited = MockClient((request) async {
        limited++;
        return http.Response("Too Many Requests", 429, headers: {"retry-after": "3600"});
      });
      final t0 = DateTime(2026, 1, 1);
      final service = OpenAipService(
          apiKey: "test-key", client: rateLimited, store: MemoryOpenAipStore(), rateLimitWait: Duration.zero);
      await withClock(Clock.fixed(t0), () => service.refresh(bayArea));
      await withClock(Clock.fixed(t0.add(const Duration(minutes: 30))), () => service.refresh(bayArea));
      expect(limited, 1);
      await withClock(Clock.fixed(t0.add(const Duration(minutes: 61))), () => service.refresh(bayArea));
      expect(limited, 2);
    });

    test("clear", () async {
      final service = OpenAipService(apiKey: "test-key", client: client, store: MemoryOpenAipStore());
      await withClock(Clock.fixed(DateTime(2026, 1, 1)), () => service.refresh(bayArea));
      service.clear();
      expect(service.airspaces, isEmpty);
      expect(service.store.airspaceCount, 0);
    });
  });
}

bool _objectBoxLibPresent() {
  final name = Platform.isWindows
      ? "objectbox.dll"
      : Platform.isMacOS
          ? "libobjectbox.dylib"
          : "libobjectbox.so";
  return File("lib/$name").existsSync() || (Platform.isMacOS && File("/usr/local/lib/$name").existsSync());
}

Map<String, dynamic> _aipAirspace(String id, LatLng center) {
  final s = square(id, center);
  return {
    "_id": id,
    "name": id,
    "type": 4,
    "icaoClass": 3,
    "geometry": {
      "type": "Polygon",
      "coordinates": [
        [...s.points, s.points.first].map((e) => [e.longitude, e.latitude]).toList()
      ]
    },
    "lowerLimit": {"value": 0, "unit": 1, "referenceDatum": 0},
    "upperLimit": {"value": 2500, "unit": 1, "referenceDatum": 1},
  };
}

Map<String, dynamic> _aipAirport(String id, LatLng latlng) => {
      "_id": id,
      "name": id,
      "type": 2,
      "geometry": {
        "type": "Point",
        "coordinates": [latlng.longitude, latlng.latitude]
      },
    };
