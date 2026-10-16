import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/ga.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/util.dart';

GA makeGA(String id, {int? timestamp}) =>
    GA(id, const LatLng(37.1, -121.5), 500, 40, 90, GAtype.small, timestamp ?? DateTime.now().millisecondsSinceEpoch);

Future<ADSB> makeADSB(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(Builder(builder: (context) {
    ctx = context;
    return const SizedBox();
  }));
  return ADSB(ctx);
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
  });

  setUp(() => settingsMgr.adsbFilters.value = []);

  group("GA json", () {
    test("round trip", () {
      final ga = makeGA("ABC123", timestamp: 1700000000000);
      final json = ga.toJson();
      expect(json["latlng"], [37.1, -121.5]);
      expect(json["type"], GAtype.small.index);

      final parsed = GA.fromJson(json)!;
      expect(parsed.id, "ABC123");
      expect(parsed.latlng, ga.latlng);
      expect(parsed.alt, 500);
      expect(parsed.spd, 40);
      expect(parsed.hdg, 90);
      expect(parsed.type, GAtype.small);
      expect(parsed.timestamp, 1700000000000);
    });

    test("malformed", () {
      expect(GA.fromJson(null), isNull);
      expect(GA.fromJson({"id": "A", "latlng": [1], "alt": 1, "timestamp": 1}), isNull);
      expect(GA.fromJson({"id": "A", "latlng": [91, 0], "alt": 1, "timestamp": 1}), isNull);
      expect(GA.fromJson({"latlng": [1, 2], "alt": 1, "timestamp": 1}), isNull);
      expect(GA.fromJson({"id": "A", "latlng": [1, 2], "alt": 1, "timestamp": 1, "type": 99})!.type, GAtype.unknown);
    });
  });

  group("ADSB sources", () {
    testWidgets("uses server planes without a local receiver", (tester) async {
      final adsb = await makeADSB(tester);
      expect(adsb.hasLocalSource, isFalse);
      adsb.addServerPlanes([makeGA("S1")]);
      expect(adsb.planes.keys, ["S1"]);
      // Server planes are never echoed back.
      expect(adsb.takeObserved(), isEmpty);
    });

    testWidgets("ignores server planes with a local receiver", (tester) async {
      final adsb = await makeADSB(tester);
      adsb.heartbeat();
      expect(adsb.hasLocalSource, isTrue);
      adsb.addServerPlanes([makeGA("S1")]);
      expect(adsb.planes, isEmpty);
    });

    testWidgets("local receiver replaces server planes", (tester) async {
      final adsb = await makeADSB(tester);
      adsb.addServerPlanes([makeGA("S1")]);
      adsb.heartbeat();
      adsb.addLocalPlane(makeGA("L1"));
      expect(adsb.planes.keys, ["L1"]);
    });

    testWidgets("queues local planes for the server", (tester) async {
      final adsb = await makeADSB(tester);
      adsb.heartbeat();
      adsb.addLocalPlane(makeGA("L1", timestamp: 1));
      adsb.addLocalPlane(makeGA("L1", timestamp: 2));
      adsb.addLocalPlane(makeGA("L2"));
      final observed = adsb.takeObserved();
      expect(observed.map((e) => e.id), ["L1", "L2"]);
      expect(observed.first.timestamp, 2);
      expect(adsb.takeObserved(), isEmpty);
    });

    testWidgets("only takes planes in range", (tester) async {
      final adsb = await makeADSB(tester);
      adsb.heartbeat();
      adsb.addLocalPlane(makeGA("NEAR"));
      adsb.addLocalPlane(GA("FAR", latlngCalc.offset(const LatLng(37.1, -121.5), 9000, 0), 500, 40, 90, GAtype.small,
          DateTime.now().millisecondsSinceEpoch));
      final observed = adsb.takeObserved(near: latlngCalc.offset(const LatLng(37.1, -121.5), 1000, 180), range: 8000);
      expect(observed.map((e) => e.id), ["NEAR"]);
      expect(adsb.takeObserved(), isEmpty);
    });

    testWidgets("filtered planes are dropped", (tester) async {
      final adsb = await makeADSB(tester);
      settingsMgr.adsbFilters.value = ["L1", "S1"];
      adsb.addServerPlanes([makeGA("S1")]);
      adsb.addLocalPlane(makeGA("L1"));
      expect(adsb.planes, isEmpty);
      expect(adsb.takeObserved(), isEmpty);
    });
  });
}
