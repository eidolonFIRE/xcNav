import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';

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

  test('FuelReport - Basic', () {
    final controller = FuelReportController();

    final recordGeo = <Geo>[
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.1, timestamp: const Duration(minutes: 30).inMilliseconds),
      Geo(lat: 34.3, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 50).inMilliseconds),
      Geo(lat: 34.4, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 80).inMilliseconds),
    ];

    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(controller.getSumFuelStat(recordGeo), null);

    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);

    expect(controller.getSumFuelStat(recordGeo)?.amount, 2);
    expect(controller.getSumFuelStat(recordGeo)?.mpl, 4619.239121840687);
  });

  test('FuelReport - Overwrite first entry', () async {
    final controller = FuelReportController();

    final recordGeo = <Geo>[
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.1, timestamp: const Duration(minutes: 30).inMilliseconds),
      Geo(lat: 34.3, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 50).inMilliseconds),
      Geo(lat: 34.4, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 80).inMilliseconds),
    ];

    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 0).inMilliseconds), 12);
    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(controller.getSumFuelStat(recordGeo), null);

    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);

    expect(controller.getSumFuelStat(recordGeo)?.amount, 2);
    expect(controller.getSumFuelStat(recordGeo)?.mpl, 4619.239121840687);
  });

  test('FuelReport - Fuel Increases', () {
    final controller = FuelReportController();

    final recordGeo = <Geo>[
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.1, timestamp: const Duration(minutes: 30).inMilliseconds),
      Geo(lat: 34.3, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 50).inMilliseconds),
      Geo(lat: 34.4, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 80).inMilliseconds),
    ];

    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(controller.getSumFuelStat(recordGeo), null);

    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);
    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 30).inMilliseconds), 10);
    controller.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 35).inMilliseconds), 12);

    expect(controller.getSumFuelStat(recordGeo)?.amount, 2);
    expect(controller.getSumFuelStat(recordGeo)?.mpl, 4619.239121840687);
  });

  test('FuelReport - overwrite', () {
    final controller = FuelReportController();

    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 1, 0, 0), 12);
    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 10, 0, 0), 11);
    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 60, 0, 0), 10);
    controller.insertFuelReport(DateTime(2000, 0, 0, 2, 0, 0, 0), 9);

    expect(controller.fuelReports.length, 4);

    // overwrite first
    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 1, 0, 0), 12.1);
    expect(controller.fuelReports.length, 4);
    expect(controller.fuelReports[0].amount, 12.1);
    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 2, 0, 0), 12.2);
    expect(controller.fuelReports.length, 4);
    expect(controller.fuelReports[0].amount, 12.2);
    expect(controller.fuelReports[0].time, DateTime(2000, 0, 0, 0, 2, 0, 0));

    // overwrite middle
    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 10, 0, 0), 12.1);
    expect(controller.fuelReports.length, 4);
    expect(controller.fuelReports[1].amount, 12.1);
    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 12, 0, 0), 12.2);
    expect(controller.fuelReports.length, 4);
    expect(controller.fuelReports[1].amount, 12.2);
    expect(controller.fuelReports[1].time, DateTime(2000, 0, 0, 0, 12, 0, 0));

    // overwrite last
    controller.insertFuelReport(DateTime(2000, 0, 0, 2, 0, 0, 0), 12.1);
    expect(controller.fuelReports.length, 4);
    expect(controller.fuelReports[3].amount, 12.1);
    controller.insertFuelReport(DateTime(2000, 0, 0, 2, 2, 0, 0), 12.2);
    expect(controller.fuelReports.length, 4);
    expect(controller.fuelReports[3].amount, 12.2);
    expect(controller.fuelReports[3].time, DateTime(2000, 0, 0, 2, 2, 0, 0));
  });

  test("FuelReport - insert middle", () {
    final controller = FuelReportController();

    controller.insertFuelReport(DateTime(2000, 0, 0, 1, 0, 0, 0), 12);
    controller.insertFuelReport(DateTime(2000, 0, 0, 2, 0, 0, 0), 10);
    controller.insertFuelReport(DateTime(2000, 0, 0, 3, 0, 0, 0), 8);

    expect(controller.fuelReports.length, 3);

    // insert middle
    controller.insertFuelReport(DateTime(2000, 0, 0, 1, 30, 0, 0), 11);
    expect(controller.fuelReports.length, 4);
    expect(controller.fuelReports[0].amount, 12);
    expect(controller.fuelReports[0].time, DateTime(2000, 0, 0, 1, 00, 0, 0));
    expect(controller.fuelReports[1].amount, 11);
    expect(controller.fuelReports[1].time, DateTime(2000, 0, 0, 1, 30, 0, 0));
    expect(controller.fuelReports[2].amount, 10);
    expect(controller.fuelReports[2].time, DateTime(2000, 0, 0, 2, 0, 0, 0));
    expect(controller.fuelReports[3].amount, 8);
    expect(controller.fuelReports[3].time, DateTime(2000, 0, 0, 3, 0, 0, 0));
  });

  test("FuelReport - findFuelReportIndex", () {
    final controller = FuelReportController();

    const tol = Duration(minutes: 3);

    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 1, 0, 0), 12, tolerance: tol);
    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 10, 0, 0), 11, tolerance: tol);
    controller.insertFuelReport(DateTime(2000, 0, 0, 0, 60, 0, 0), 10, tolerance: tol);
    controller.insertFuelReport(DateTime(2000, 0, 0, 2, 0, 0, 0), 9, tolerance: tol);

    // close to a beginning
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 0, 0, 0, 0), tolerance: tol), 0);
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 0, 1, 0, 0), tolerance: tol), 0);
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 0, 2, 0, 0), tolerance: tol), 0);

    // close to a middle
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 0, 58, 0, 0), tolerance: tol), 2);
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 0, 60, 0, 0), tolerance: tol), 2);
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 0, 62, 0, 0), tolerance: tol), 2);

    // close to the end
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 1, 58, 0, 0), tolerance: tol), 3);
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 1, 60, 0, 0), tolerance: tol), 3);
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 1, 62, 0, 0), tolerance: tol), 3);

    // not close to any
    expect(
        controller.findFuelReportIndex(DateTime(2000, 0, 0, 0, 0, 0, 0).subtract(const Duration(minutes: 4)),
            tolerance: tol),
        null);
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 0, 40, 0, 0), tolerance: tol), null);
    expect(controller.findFuelReportIndex(DateTime(2000, 0, 0, 3, 0, 0, 0), tolerance: tol), null);
  });

  test("FuelReport - out of order reports are sorted", () {
    final recordGeo = <Geo>[
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ];
    final controller = FuelReportController(fuelReports: [
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 20).inMilliseconds), 10),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 0).inMilliseconds), 12),
    ]);

    expect(controller.fuelReports.map((e) => e.amount), [12, 10]);
    expect(controller.getFuelStats(recordGeo).length, 1);
    expect(controller.getSumFuelStat(recordGeo)?.amount, 2);
  });

  test("FuelReport - no samples", () {
    final controller = FuelReportController(fuelReports: [
      FuelReport(DateTime.fromMillisecondsSinceEpoch(0), 12),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 10).inMilliseconds), 10),
    ]);

    expect(controller.getFuelStats([]), isEmpty);
    expect(controller.getSumFuelStat([]), null);
  });

  group("FuelReport - cropReportsToTimeRange", () {
    DateTime t(int minutes) => DateTime(2000, 1, 1).add(Duration(minutes: minutes));
    FuelReportController make() => FuelReportController(fuelReports: [
          FuelReport(t(0), 12),
          FuelReport(t(60), 10),
          FuelReport(t(120), 8),
        ]);

    test("range covers all reports", () {
      final controller = make()..cropReportsToTimeRange(DateTimeRange(start: t(-10), end: t(130)));
      expect(controller.fuelReports.map((e) => e.time), [t(0), t(60), t(120)]);
      expect(controller.fuelReports.map((e) => e.amount), [12, 10, 8]);
    });

    test("crop both ends interpolates new ends", () {
      final controller = make()..cropReportsToTimeRange(DateTimeRange(start: t(30), end: t(90)));
      expect(controller.fuelReports.map((e) => e.time), [t(30), t(60), t(90)]);
      expect(controller.fuelReports.map((e) => e.amount), [11, 10, 9]);
    });

    test("range falls entirely between two reports", () {
      final controller = make()..cropReportsToTimeRange(DateTimeRange(start: t(75), end: t(105)));
      expect(controller.fuelReports.map((e) => e.time), [t(75), t(105)]);
      expect(controller.fuelReports.map((e) => e.amount), [9.5, 8.5]);
    });

    test("range outside all reports", () {
      final controller = make()..cropReportsToTimeRange(DateTimeRange(start: t(150), end: t(200)));
      expect(controller.fuelReports, isEmpty);
    });
  });
}
