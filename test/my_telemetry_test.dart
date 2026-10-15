import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // MyTelemetry starts the IMU on takeoff; stub the sensors plugin.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      "dev.fluttercommunity.plus/sensors/method",
      "dev.fluttercommunity.plus/sensors/accelerometer",
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    SharedPreferences.setMockInitialValues({
      "profile.name": "Mr Test",
      "profile.id": "1234",
      "profile.secretID": "1234abcd",
    });
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    settingsMgr.forceGpsAltitude.value = true;
  });

  test("smokes", () {
    final telemetry = MyTelemetry();
    final position = Position(
      longitude: 0,
      latitude: 0,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 1000,
      altitudeAccuracy: 1,
      headingAccuracy: 1,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    telemetry.updateGeo(position);
  });

  test("gps fix strength", () {
    final now = DateTime(2026, 1, 1, 12);
    withClock(Clock.fixed(now), () {
      expect(GpsFixQuality(accuracy: 4, time: now).strength, GpsStrength.good);
      expect(GpsFixQuality(accuracy: 20, time: now).strength, GpsStrength.fair);
      expect(GpsFixQuality(accuracy: 80, time: now).strength, GpsStrength.poor);
      expect(GpsFixQuality(accuracy: 4, time: now.subtract(const Duration(seconds: 11))).strength, GpsStrength.none);
    });
  });

  test("updateGeo records gps fix", () {
    final telemetry = MyTelemetry();
    expect(telemetry.gpsFix.value, isNull);
    telemetry.updateGeo(Position(
      longitude: 0,
      latitude: 0,
      timestamp: DateTime.now(),
      accuracy: 7,
      altitude: 1000,
      altitudeAccuracy: 1,
      headingAccuracy: 1,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
    ));
    expect(telemetry.gpsFix.value?.accuracy, 7);
    expect(telemetry.gpsFix.value?.strength, GpsStrength.good);
  });

  test("IMU only runs in flight", () {
    final telemetry = MyTelemetry();
    expect(telemetry.listenIMU, isNull);
    telemetry.updateGeo(Position(
      longitude: 0,
      latitude: 0,
      timestamp: DateTime.now(),
      accuracy: 1,
      altitude: 1000,
      altitudeAccuracy: 1,
      headingAccuracy: 1,
      heading: 0,
      speed: 0,
      speedAccuracy: 0,
    ));
    expect(telemetry.listenIMU, isNull);

    telemetry.startFlight();
    expect(telemetry.listenIMU, isNotNull);

    telemetry.stopFlight(bypassRecording: true);
    expect(telemetry.listenIMU, isNull);
  });
}
