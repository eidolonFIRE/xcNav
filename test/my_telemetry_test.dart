import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';

void main() {
  test('FuelReport - Basic', () {
    WidgetsFlutterBinding.ensureInitialized();
    final myTelemetry = MyTelemetry();

    myTelemetry.recordGeo.addAll([
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.1, timestamp: const Duration(minutes: 30).inMilliseconds),
      Geo(lat: 34.3, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 50).inMilliseconds),
      Geo(lat: 34.4, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 80).inMilliseconds),
    ]);

    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(myTelemetry.sumFuelStat, null);

    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);

    expect(myTelemetry.sumFuelStat?.amount, 2);
    expect(myTelemetry.sumFuelStat?.mpl, 4619.239121840687);
  });

  test('FuelReport - Overwrite first entry', () {
    WidgetsFlutterBinding.ensureInitialized();
    final myTelemetry = MyTelemetry();

    myTelemetry.recordGeo.addAll([
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.1, timestamp: const Duration(minutes: 30).inMilliseconds),
      Geo(lat: 34.3, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 50).inMilliseconds),
      Geo(lat: 34.4, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 80).inMilliseconds),
    ]);

    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 0).inMilliseconds), 12);
    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(myTelemetry.sumFuelStat, null);

    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);

    expect(myTelemetry.sumFuelStat?.amount, 2);
    expect(myTelemetry.sumFuelStat?.mpl, 4619.239121840687);
  });

  test('FuelReport - Fuel Increases', () {
    WidgetsFlutterBinding.ensureInitialized();
    final myTelemetry = MyTelemetry();

    myTelemetry.recordGeo.addAll([
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.1, timestamp: const Duration(minutes: 30).inMilliseconds),
      Geo(lat: 34.3, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 50).inMilliseconds),
      Geo(lat: 34.4, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 80).inMilliseconds),
    ]);

    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(myTelemetry.sumFuelStat, null);

    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);
    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 30).inMilliseconds), 10);
    myTelemetry.insertFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 35).inMilliseconds), 12);

    expect(myTelemetry.sumFuelStat?.amount, 2);
    expect(myTelemetry.sumFuelStat?.mpl, 4619.239121840687);
  });

  test('FuelReport - overwrite', () {
    WidgetsFlutterBinding.ensureInitialized();
    final myTelemetry = MyTelemetry();

    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 1, 0, 0), 12);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 10, 0, 0), 11);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 60, 0, 0), 10);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 2, 0, 0, 0), 9);

    expect(myTelemetry.fuelReports.length, 4);

    // overwrite first
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 1, 0, 0), 12.1);
    expect(myTelemetry.fuelReports.length, 4);
    expect(myTelemetry.fuelReports[0].amount, 12.1);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 2, 0, 0), 12.2);
    expect(myTelemetry.fuelReports.length, 4);
    expect(myTelemetry.fuelReports[0].amount, 12.2);
    expect(myTelemetry.fuelReports[0].time, DateTime(2000, 0, 0, 0, 1, 0, 0));

    // overwrite middle
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 10, 0, 0), 12.1);
    expect(myTelemetry.fuelReports.length, 4);
    expect(myTelemetry.fuelReports[1].amount, 12.1);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 12, 0, 0), 12.2);
    expect(myTelemetry.fuelReports.length, 4);
    expect(myTelemetry.fuelReports[1].amount, 12.2);
    expect(myTelemetry.fuelReports[1].time, DateTime(2000, 0, 0, 0, 10, 0, 0));

    // overwrite last
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 2, 0, 0, 0), 12.1);
    expect(myTelemetry.fuelReports.length, 4);
    expect(myTelemetry.fuelReports[3].amount, 12.1);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 2, 2, 0, 0), 12.2);
    expect(myTelemetry.fuelReports.length, 4);
    expect(myTelemetry.fuelReports[3].amount, 12.2);
    expect(myTelemetry.fuelReports[3].time, DateTime(2000, 0, 0, 2, 0, 0, 0));
  });

  test("FuelReport - findFuelReportIndex", () {
    WidgetsFlutterBinding.ensureInitialized();
    final myTelemetry = MyTelemetry();

    const tol = Duration(minutes: 3);

    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 1, 0, 0), 12, tolerance: tol);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 10, 0, 0), 11, tolerance: tol);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 0, 60, 0, 0), 10, tolerance: tol);
    myTelemetry.insertFuelReport(DateTime(2000, 0, 0, 2, 0, 0, 0), 9, tolerance: tol);

    // close to a beginning
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 0, 0, 0, 0), tolerance: tol), 0);
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 0, 1, 0, 0), tolerance: tol), 0);
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 0, 2, 0, 0), tolerance: tol), 0);

    // close to a middle
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 0, 58, 0, 0), tolerance: tol), 2);
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 0, 60, 0, 0), tolerance: tol), 2);
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 0, 62, 0, 0), tolerance: tol), 2);

    // close to the end
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 1, 58, 0, 0), tolerance: tol), 3);
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 1, 60, 0, 0), tolerance: tol), 3);
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 1, 62, 0, 0), tolerance: tol), 3);

    // not close to any
    expect(
        myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 0, 0, 0, 0).subtract(const Duration(minutes: 4)),
            tolerance: tol),
        null);
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 0, 40, 0, 0), tolerance: tol), null);
    expect(myTelemetry.findFuelReportIndex(DateTime(2000, 0, 0, 3, 0, 0, 0), tolerance: tol), null);
  });
}
