import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';

void main() {
  test('addition', () {
    final a = FuelStat.fromSamples(FuelReport(DateTime.fromMillisecondsSinceEpoch(0), 10),
        FuelReport(DateTime.fromMillisecondsSinceEpoch(0).add(const Duration(hours: 1)), 5), [
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ]);

    final b = FuelStat.fromSamples(FuelReport(DateTime.fromMillisecondsSinceEpoch(0).add(const Duration(hours: 1)), 5),
        FuelReport(DateTime.fromMillisecondsSinceEpoch(0).add(const Duration(hours: 2)), 3), [
      Geo(lat: 34.1, lng: 120.2, alt: 0.1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34.3, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.4, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ]);

    final sum = a + b;

    expect(sum.amount, 7);
    expect(sum.durationTime, const Duration(hours: 2));
    expect(sum.durationDist, 62106.051723064615);
    expect(sum.rate, 3.5);
    expect(sum.mpl, 11975.907325597582);
    expect(sum.meanAlt, 73.6);
    expect(sum.meanSpd, 13.1503911);
    expect(sum.altGained, 239.2);
  });

  test("extrapolateToTime", () {
    final reportA = FuelReport(DateTime.fromMillisecondsSinceEpoch(0), 10);
    final reportB = FuelReport(DateTime.fromMillisecondsSinceEpoch(0).add(const Duration(hours: 1)), 5);
    final stat = FuelStat.fromSamples(reportA, reportB, [
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ]);

    expect(stat.extrapolateToTime(reportB, reportB.time.add(const Duration(minutes: 30))), 2.5);
    expect(
        stat.extrapolateToTime(FuelReport(reportB.time.add(const Duration(minutes: 30)), 4),
            reportB.time.add(const Duration(minutes: 45))),
        2.75);
  });

  test("extrapolateEndurance", () {
    final reportA = FuelReport(DateTime.fromMillisecondsSinceEpoch(0), 10);
    final reportB = FuelReport(DateTime.fromMillisecondsSinceEpoch(0).add(const Duration(hours: 1)), 5);
    final stat = FuelStat.fromSamples(reportA, reportB, [
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ]);

    expect(stat.extrapolateEndurance(reportB), const Duration(minutes: 60));
    expect(stat.extrapolateEndurance(FuelReport(reportB.time.add(const Duration(minutes: 30)), 3)),
        const Duration(minutes: 36));
  });
}
