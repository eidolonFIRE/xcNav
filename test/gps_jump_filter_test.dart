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
      for (int i = 1; i <= 3; i++) {
        expect(filter.check(last, _pos(38, -122, i * 100)), GpsFixVerdict.reject);
      }
      expect(filter.check(last, _pos(38, -122, 400)), GpsFixVerdict.reanchor);
      expect(filter.consecutiveRejects, 0);
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
