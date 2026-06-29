import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/gaussian_filter.dart';
import 'package:xcnav/util.dart';

void main() {
  test('gaussian filter - flat offset', () {
    final List<TimestampValue<double>> data = [
      TimestampValue<double>(0, 1),
      TimestampValue<double>(0, 1),
      TimestampValue<double>(0, 1),
      TimestampValue<double>(0, 1)
    ];

    expect(gaussianFilterTimestamped(data, 3, 3), data);
  });
}
