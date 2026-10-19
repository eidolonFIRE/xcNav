import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/gps_jump_filter.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';

final _t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

Position _pos(double lat, double lng, int ms, {double alt = 1000}) => Position(
      longitude: lng,
      latitude: lat,
      timestamp: _t0.add(Duration(milliseconds: ms)),
      accuracy: 5,
      altitude: alt,
      altitudeAccuracy: 5,
      headingAccuracy: 1,
      heading: 0,
      speed: 10,
      speedAccuracy: 1,
    );

Geo _geo(double lat, double lng, int ms, {double alt = 1000}) => Geo.fromPosition(_pos(lat, lng, ms, alt: alt), null, null, null);

// ~111 m per 0.001 deg latitude
const double _deg100m = 0.0009;

/// Fix [east] / [north] meters from (37, -122).
Position _offset(double east, double north, int ms) =>
    _pos(37 + north / 111195, -122 + east / (111195 * cos(37 * pi / 180)), ms);

/// Fix [north] meters north of (37, -122), [i] seconds in.
Position _north(int i, double north) => _offset(0, north, i * 1000);

/// Feed fixes through the filter the way MyTelemetry does.
List<GpsFixVerdict> _replay(GpsJumpFilter filter, List<Position> positions) {
  Geo? last;
  final List<GpsFixVerdict> verdicts = [];
  for (final position in positions) {
    final verdict = filter.check(last, position);
    verdicts.add(verdict);
    if (verdict != GpsFixVerdict.reject) {
      last = Geo.fromPosition(position, verdict == GpsFixVerdict.reanchor ? null : last, null, null);
    }
  }
  return verdicts;
}

void main() {
  group("GpsJumpFilter", () {
    test("accepts first fix", () {
      expect(GpsJumpFilter().check(null, _pos(37, -122, 0)), GpsFixVerdict.accept);
    });

    test("accepts normal flight motion", () {
      final filter = GpsJumpFilter();
      // ~10 m/s
      expect(filter.check(_geo(37, -122, 0), _pos(37 + _deg100m / 10, -122, 1000)), GpsFixVerdict.accept);
    });

    test("rejects far jump with nearly identical timestamp", () {
      final filter = GpsJumpFilter();
      expect(filter.check(_geo(37, -122, 0), _pos(37 + _deg100m * 10, -122, 20)), GpsFixVerdict.reject);
    });

    test("rejects duplicate / out-of-order timestamps", () {
      final filter = GpsJumpFilter();
      final last = _geo(37, -122, 1000);
      expect(filter.check(last, _pos(37, -122, 1000)), GpsFixVerdict.reject);
      expect(filter.check(last, _pos(37, -122, 500)), GpsFixVerdict.reject);
    });

    test("rejects impossible altitude jump", () {
      final filter = GpsJumpFilter();
      expect(filter.check(_geo(37, -122, 0), _pos(37, -122, 1000, alt: 1500)), GpsFixVerdict.reject);
    });

    test("re-anchors after repeated rejections", () {
      final filter = GpsJumpFilter(maxConsecutiveRejects: 3);
      final last = _geo(37, -122, 0);
      // Each bad fix is also far from the one before it, so they don't look like a shifted track.
      for (int i = 1; i <= 3; i++) {
        expect(filter.check(last, _pos(37.0 + i, -122, i * 100)), GpsFixVerdict.reject);
      }
      expect(filter.check(last, _pos(41, -122, 400)), GpsFixVerdict.reanchor);
      expect(filter.consecutiveRejects, 0);
    });

    test("accepts plausible motion after a long gap", () {
      final filter = GpsJumpFilter();
      // 30 s later, 300 m away in a different direction
      expect(filter.check(_geo(37, -122, 0), _pos(37, -122 + _deg100m * 3, 30000)), GpsFixVerdict.accept);
    });

    test("accepts steady flight", () {
      final verdicts = _replay(GpsJumpFilter(), [for (int i = 0; i < 30; i++) _north(i, i * 10)]);
      expect(verdicts, everyElement(GpsFixVerdict.accept));
    });

    test("accepts a tight turn", () {
      // 12 m/s around a 10 m radius: 14 m/s^2 (1.5 G) of centripetal acceleration
      const r = 10.0;
      const v = 12.0;
      final verdicts = _replay(GpsJumpFilter(), [
        for (int i = 0; i < 30; i++) _offset(r * sin(i * v / r), r * cos(i * v / r), i * 1000),
      ]);
      expect(verdicts, everyElement(GpsFixVerdict.accept));
    });

    test("accepts a high G turn at constant speed", () {
      // 20 m/s, 3 G of centripetal acceleration
      const v = 20.0;
      const r = v * v / (3 * 9.81);
      final verdicts = _replay(GpsJumpFilter(), [
        for (int i = 0; i < 30; i++) _offset(r * sin(i * v / r), r * cos(i * v / r), i * 1000),
      ]);
      expect(verdicts, everyElement(GpsFixVerdict.accept));
    });

    test("accepts 1 G of speed change", () {
      // Accelerate straight north from 10 m/s at 9.81 m/s^2 for 3 s.
      final verdicts = _replay(GpsJumpFilter(), [
        for (int i = 0; i < 10; i++) _north(i, i * 10),
        for (int i = 1; i <= 3; i++) _north(9 + i, 90 + 10.0 * i + 9.81 / 2 * i * i),
      ]);
      expect(verdicts, everyElement(GpsFixVerdict.accept));
    });

    test("rejects a sudden speed change straight ahead", () {
      // 10 m/s, then 30 m/s a second later: 2 G
      final verdicts = _replay(GpsJumpFilter(), [
        for (int i = 0; i < 10; i++) _north(i, i * 10),
        _north(10, 120),
      ]);
      expect(verdicts.last, GpsFixVerdict.reject);
    });

    test("rejects a single spike and keeps the anchor", () {
      final verdicts = _replay(GpsJumpFilter(), [
        for (int i = 0; i < 10; i++) _north(i, i * 10),
        _offset(40, 100, 10000),
        for (int i = 11; i < 15; i++) _north(i, i * 10),
      ]);
      expect(verdicts[10], GpsFixVerdict.reject);
      expect(verdicts.sublist(11), everyElement(GpsFixVerdict.accept));
    });

    test("re-anchors right away when the GPS solution shifts", () {
      // Flying north at 10 m/s, then every fix lands 60 m east of where it should be.
      final verdicts = _replay(GpsJumpFilter(), [
        for (int i = 0; i < 10; i++) _north(i, i * 10),
        for (int i = 10; i < 15; i++) _offset(60, i * 10, i * 1000),
      ]);
      expect(verdicts.sublist(0, 10), everyElement(GpsFixVerdict.accept));
      expect(verdicts[10], GpsFixVerdict.reject);
      expect(verdicts[11], GpsFixVerdict.reanchor);
      expect(verdicts.sublist(12), everyElement(GpsFixVerdict.accept));
    });

    test("re-anchors when anchor is stale", () {
      final filter = GpsJumpFilter();
      expect(filter.check(_geo(37, -122, 0), _pos(40, -122, 20000)), GpsFixVerdict.reanchor);
    });
  });

  group("MyTelemetry jump rejection", () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // MyTelemetry starts the IMU on construction; stub the sensors plugin.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel("dev.fluttercommunity.plus/sensors/method"), (_) async => null);
      SharedPreferences.setMockInitialValues({
        "profile.name": "Mr Test",
        "profile.id": "1234",
        "profile.secretID": "1234abcd",
      });
      settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
      settingsMgr.forceGpsAltitude.value = true;
      settingsMgr.autoRecordFlight.value = false;
    });

    test("bad jump does not poison smoothed speed / vario", () {
      final telemetry = MyTelemetry();
      for (int i = 0; i < 10; i++) {
        expect(telemetry.updateGeo(_pos(37 + i * _deg100m / 10, -122, i * 1000)), isTrue);
      }
      final speedBefore = telemetry.speedSmooth.value;
      final varioBefore = telemetry.varioSmooth.value;
      final recordLen = telemetry.recordGeo.length;

      // 10 km jump, 500 m climb, 5 ms later
      expect(telemetry.updateGeo(_pos(37.1, -122, 9005, alt: 1500)), isFalse);

      expect(telemetry.speedSmooth.value, speedBefore);
      expect(telemetry.varioSmooth.value, varioBefore);
      expect(telemetry.recordGeo.length, recordLen);
      expect(telemetry.speedSmooth.value, lessThan(20));

      // Next good fix is accepted relative to the last good one
      expect(telemetry.updateGeo(_pos(37 + 10 * _deg100m / 10, -122, 10000)), isTrue);
      expect(telemetry.speedSmooth.value, lessThan(20));
    });
  });
}
