import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/ble_devices/ble_device_value.dart';
import 'package:xcnav/ble_devices/ble_device_xc170.dart';

void main() {
  test('SensorCalibration', () {
    final mapValue = MapValue([
      [0.0, 0.0],
      [100.0, 1.0],
      [200.0, 2.0],
    ]);

    expect(mapValue.mapValue(50.0), closeTo(0.5, 0.001));
    expect(mapValue.mapValue(100.0), closeTo(1.0, 0.001));
    expect(mapValue.mapValue(101.0), closeTo(1.01, 0.001));
    expect(mapValue.mapValue(150.0), closeTo(1.5, 0.001));

    expect(mapValue.mapValue(250.0), 2.0);

    expect(mapValue.mapValue(0.0), 0);
  });

  test('MapValue validate sorts and rejects bad curves', () {
    final sorted = MapValue.validate([
      [200.0, 2.0],
      [0.0, 0.0],
    ]);
    expect(sorted!.points, [
      [0.0, 0.0],
      [200.0, 2.0]
    ]);

    expect(
        MapValue.validate([
          [0.0, 0.0]
        ]),
        isNull);
    expect(
        MapValue.validate([
          [10.0, 0.0],
          [10.0, 1.0]
        ]),
        isNull);
  });

  test('MapValue json round trip', () {
    final mapValue = MapValue<double>([
      [0.0, 5.0],
      [100.0, 110.0],
    ]);
    final parsed = MapValue.fromJson(mapValue.toJson());
    expect(parsed!.points, mapValue.points);

    expect(MapValue.fromJson("garbage"), isNull);
    expect(
        MapValue.fromJson([
          [0, "x"],
          [1, 2]
        ]),
        isNull);
  });

  test('Xc170 CHT / EGT calibration saved to prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final telemetry = Xc170TelemetryCharacteristic(uuid: "test");
    telemetry.loadCalibration(prefs);
    expect(telemetry.cht.calibration, isNull);
    expect(telemetry.egt.calibration, isNull);

    telemetry.setChtCalibration(MapValue<double>([
      [0.0, 10.0],
      [200.0, 210.0],
    ]));
    telemetry.setEgtCalibration(MapValue<double>([
      [0.0, 0.0],
      [500.0, 600.0],
    ]));

    telemetry.cht.addValue(100.0, DateTime.fromMillisecondsSinceEpoch(0));
    expect(telemetry.cht.log.last.value, closeTo(110.0, 0.001));
    expect(telemetry.cht.lastRawValue, 100.0);

    // Reload in a fresh instance
    final reloaded = Xc170TelemetryCharacteristic(uuid: "test");
    reloaded.loadCalibration(prefs);
    expect(reloaded.cht.calibration!.points, telemetry.cht.calibration!.points);
    expect(reloaded.egt.calibration!.mapValue(250.0), closeTo(300.0, 0.001));

    // Clear
    reloaded.setChtCalibration(null);
    expect(prefs.getString(Xc170TelemetryCharacteristic.chtCalibrationKey), isNull);
    final cleared = Xc170TelemetryCharacteristic(uuid: "test");
    cleared.loadCalibration(prefs);
    expect(cleared.cht.calibration, isNull);
    expect(cleared.egt.calibration, isNotNull);
  });
}
