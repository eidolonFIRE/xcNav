import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/ble_devices/ble_device_value.dart';

void main() {
  test('trimToRange - no change', () {
    final bleValue = BleLoggedValue<int>();

    bleValue.addValue(0, DateTime.fromMillisecondsSinceEpoch(0));
    bleValue.addValue(30, DateTime.fromMillisecondsSinceEpoch(1000));
    bleValue.addValue(20, DateTime.fromMillisecondsSinceEpoch(2000));

    bleValue.trimToRange(DateTimeRange(
      start: DateTime.fromMillisecondsSinceEpoch(000),
      end: DateTime.fromMillisecondsSinceEpoch(2000),
    ));

    expect(bleValue.log.length, 3);
    expect(bleValue.log[0].time, 0);
    expect(bleValue.log[2].time, 2000);
  });

  test('trimToRange - no change one value', () {
    final bleValue = BleLoggedValue<int>();

    bleValue.addValue(30, DateTime.fromMillisecondsSinceEpoch(1000));

    bleValue.trimToRange(DateTimeRange(
      start: DateTime.fromMillisecondsSinceEpoch(000),
      end: DateTime.fromMillisecondsSinceEpoch(2000),
    ));

    expect(bleValue.log.length, 1);
    expect(bleValue.log[0].time, 1000);
  });

  test('trimToRange - interpolate start', () {
    final bleValue = BleLoggedValue<int>();

    bleValue.addValue(10, DateTime.fromMillisecondsSinceEpoch(0));
    bleValue.addValue(30, DateTime.fromMillisecondsSinceEpoch(1000));

    bleValue.trimToRange(DateTimeRange(
      start: DateTime.fromMillisecondsSinceEpoch(500),
      end: DateTime.fromMillisecondsSinceEpoch(2000),
    ));

    expect(bleValue.log.length, 2);
    expect(bleValue.log[0].value, 20);
    expect(bleValue.log[0].time, 500);
    expect(bleValue.log[1].value, 30);
    expect(bleValue.log[1].time, 1000);
  });

  test('trimToRange - interpolate end', () {
    final bleValue = BleLoggedValue<int>();

    bleValue.addValue(10, DateTime.fromMillisecondsSinceEpoch(0));
    bleValue.addValue(30, DateTime.fromMillisecondsSinceEpoch(1000));

    bleValue.trimToRange(DateTimeRange(
      start: DateTime.fromMillisecondsSinceEpoch(000),
      end: DateTime.fromMillisecondsSinceEpoch(500),
    ));

    expect(bleValue.log.length, 2);
    expect(bleValue.log[0].value, 10);
    expect(bleValue.log[0].time, 0);
    expect(bleValue.log[1].value, 20);
    expect(bleValue.log[1].time, 500);
  });

  test('trimToRange - int', () {
    final bleValue = BleLoggedValue<int>();

    bleValue.addValue(0, DateTime.fromMillisecondsSinceEpoch(0));
    bleValue.addValue(30, DateTime.fromMillisecondsSinceEpoch(1000));
    bleValue.addValue(20, DateTime.fromMillisecondsSinceEpoch(2000));

    bleValue.trimToRange(DateTimeRange(
      start: DateTime.fromMillisecondsSinceEpoch(500),
      end: DateTime.fromMillisecondsSinceEpoch(1500),
    ));

    expect(bleValue.log.length, 3);
    expect(bleValue.log[0].value, 15);
    expect(bleValue.log[0].time, 500);
    expect(bleValue.log[1].value, 30);
    expect(bleValue.log[1].time, 1000);
    expect(bleValue.log[2].value, 25);
    expect(bleValue.log[2].time, 1500);
  });

  test('trimToRange - double', () {
    final bleValue = BleLoggedValue<double>();

    bleValue.addValue(0, DateTime.fromMillisecondsSinceEpoch(0));
    bleValue.addValue(3.0, DateTime.fromMillisecondsSinceEpoch(1000));
    bleValue.addValue(2.0, DateTime.fromMillisecondsSinceEpoch(2000));

    bleValue.trimToRange(DateTimeRange(
      start: DateTime.fromMillisecondsSinceEpoch(500),
      end: DateTime.fromMillisecondsSinceEpoch(1500),
    ));

    expect(bleValue.log.length, 3);
    expect(bleValue.log[0].value, 1.5);
    expect(bleValue.log[0].time, 500);
    expect(bleValue.log[1].value, 3.0);
    expect(bleValue.log[1].time, 1000);
    expect(bleValue.log[2].value, 2.5);
    expect(bleValue.log[2].time, 1500);
  });

  test('compress - double', () {
    final bleValue = BleLoggedValue<double>();

    bleValue.addValue(0.0, DateTime.fromMillisecondsSinceEpoch(0));
    bleValue.addValue(1.0, DateTime.fromMillisecondsSinceEpoch(1000));
    bleValue.addValue(0.5, DateTime.fromMillisecondsSinceEpoch(2000));
    bleValue.addValue(1.5, DateTime.fromMillisecondsSinceEpoch(3000));
    bleValue.addValue(1.0, DateTime.fromMillisecondsSinceEpoch(4000));

    bleValue.compress(epsilon: 0.5);

    expect(bleValue.log.length, 3);
    expect(bleValue.log[0].time, 0);
    expect(bleValue.log[0].value, 0.0);
    expect(bleValue.log[1].value, 1.0);
    expect(bleValue.log[2].value, 1.0);
    expect(bleValue.log[2].time, 4000);
  });

  test('compress - int', () {
    final bleValue = BleLoggedValue<int>();

    bleValue.addValue(00, DateTime.fromMillisecondsSinceEpoch(0));
    bleValue.addValue(10, DateTime.fromMillisecondsSinceEpoch(1000));
    bleValue.addValue(05, DateTime.fromMillisecondsSinceEpoch(2000));
    bleValue.addValue(15, DateTime.fromMillisecondsSinceEpoch(3000));
    bleValue.addValue(10, DateTime.fromMillisecondsSinceEpoch(4000));

    bleValue.compress(epsilon: 5);

    expect(bleValue.log.length, 3);
    expect(bleValue.log[0].time, 0);
    expect(bleValue.log[0].value, 00);
    expect(bleValue.log[1].value, 10);
    expect(bleValue.log[2].value, 10);
    expect(bleValue.log[2].time, 4000);
  });
}
