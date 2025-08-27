import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/ble_devices/ble_device_value.dart';

void main() {
  test('SensorCalibration', () {
    final calibration = SensorCalibration([
      [0.0, 0.0],
      [100.0, 1.0],
      [200.0, 2.0],
    ]);

    expect(calibration.calibrateValue(50.0).value, closeTo(0.5, 0.001));
    expect(calibration.calibrateValue(100.0).value, closeTo(1.0, 0.001));
    expect(calibration.calibrateValue(101.0).value, closeTo(1.01, 0.001));
    expect(calibration.calibrateValue(150.0).value, closeTo(1.5, 0.001));

    expect(calibration.calibrateValue(250.0).value, 2.0);
    expect(calibration.calibrateValue(250.0).status, ValueInRange.aboveRange);

    expect(calibration.calibrateValue(0.0).value, 0);
    expect(calibration.calibrateValue(0.0).status, ValueInRange.belowRange);
  });
}
