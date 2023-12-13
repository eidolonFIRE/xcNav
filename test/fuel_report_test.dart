import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/models/fuel_report.dart';

void main() {
  test('extrapolateEndurance', () {
    final report = FuelReport(DateTime(0), 10);
    final stat = FuelStat(1, Duration.zero, 0, 1, 1, 0, 0, 0);

    expect(stat.extrapolateEndurance(report, from: DateTime(0)), stat.extrapolateEndurance(report));

    expect(stat.extrapolateEndurance(report, from: DateTime(0).subtract(const Duration(hours: 1))),
        const Duration(hours: 11));
    expect(
        stat.extrapolateEndurance(report, from: DateTime(0).add(const Duration(hours: 0))), const Duration(hours: 10));
    expect(
        stat.extrapolateEndurance(report, from: DateTime(0).add(const Duration(hours: 1))), const Duration(hours: 9));
    expect(
        stat.extrapolateEndurance(report, from: DateTime(0).add(const Duration(hours: 2))), const Duration(hours: 8));
  });
}
