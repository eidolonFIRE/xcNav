import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/ble_devices/ble_device_value.dart';

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
}
