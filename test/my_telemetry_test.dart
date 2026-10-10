import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/settings_service.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
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
}
