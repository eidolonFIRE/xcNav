import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/gear.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';

void main() {
  test('Log Fidelity', () {
    final gear = Gear();
    gear.wingMakeModel = "1234ok";
    gear.tankSize = 12;
    gear.bladderSize = 1.2;

    final log = FlightLog(samples: [
      Geo(lat: 34, lng: 120, alt: 0.1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ], waypoints: [
      Waypoint(name: "test", latlngs: [LatLng(35, 121)], icon: "star", color: 0xFFD0E1B2),
      Waypoint(name: "test_path", latlngs: [LatLng(35, 121), LatLng(35.2, 121)], color: 0xFFA5C130)
    ], fuelReports: [
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 1).inMilliseconds), 10.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 10).inMilliseconds), 5.0),
    ], gear: gear);

    expect(log.toJson(), FlightLog.fromJson("", jsonDecode(log.toJson())).toJson());

    final loadedLog = FlightLog.fromJson("", jsonDecode(log.toJson()));
    final newLog = FlightLog(
        samples: loadedLog.samples,
        waypoints: loadedLog.waypoints,
        fuelReports: loadedLog.fuelReports,
        gear: loadedLog.gear,
        filename: loadedLog.filename);
    expect(jsonDecode(loadedLog.toJson()), jsonDecode(newLog.toJson()));
  });

  test("trim - start clean cut", () {
    final log = FlightLog(samples: [
      Geo(lat: 34, lng: 120, alt: 0.1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.05, lng: 120.15, alt: 0.25, spd: 23.0537096, timestamp: const Duration(minutes: 15).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ], fuelReports: [
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 1).inMilliseconds), 10.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 10).inMilliseconds), 5.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 20).inMilliseconds), 0.0),
    ]);

    expect(log.fuelReports.length, 3);

    final trimmed = log.trimLog(1, 3);

    // Check samples
    expect(trimmed.samples.length, 3);

    // Check fuel
    expect(trimmed.fuelReports.length, 2);
    expect(trimmed.fuelReports.first.amount, 5.0);
    expect(trimmed.fuelReports.first.time,
        DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 10).inMilliseconds));
  });

  test("trim - start interpolated", () {
    final log = FlightLog(samples: [
      Geo(lat: 34, lng: 120, alt: 0.1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.05, lng: 120.15, alt: 0.25, spd: 23.0537096, timestamp: const Duration(minutes: 15).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ], fuelReports: [
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 1).inMilliseconds), 10.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 13).inMilliseconds), 5.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 20).inMilliseconds), 0.0),
    ]);

    expect(log.fuelReports.length, 3);

    final trimmed = log.trimLog(1, 3);

    // Check samples
    expect(trimmed.samples.length, 3);

    // Check fuel
    expect(trimmed.fuelReports.length, 3);
    expect(trimmed.fuelReports.first.amount, 6.25);
    expect(trimmed.fuelReports.first.time,
        DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 10).inMilliseconds));
  });

  test("trim - end clean cut", () {
    final log = FlightLog(samples: [
      Geo(lat: 34, lng: 120, alt: 0.1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.05, lng: 120.15, alt: 0.25, spd: 23.0537096, timestamp: const Duration(minutes: 15).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ], fuelReports: [
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 1).inMilliseconds), 10.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 15).inMilliseconds), 5.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 20).inMilliseconds), 0.0),
    ]);

    expect(log.fuelReports.length, 3);

    final trimmed = log.trimLog(0, 2);

    // Check samples
    expect(trimmed.samples.length, 3);

    // Check fuel
    expect(trimmed.fuelReports.length, 2);
    expect(trimmed.fuelReports.last.amount, 5.0);
    expect(
        trimmed.fuelReports.last.time, DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 15).inMilliseconds));
  });

  test("trim - end interpolated", () {
    final log = FlightLog(samples: [
      Geo(lat: 34, lng: 120, alt: 0.1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.05, lng: 120.15, alt: 0.25, spd: 23.0537096, timestamp: const Duration(minutes: 15).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
    ], fuelReports: [
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 1).inMilliseconds), 10.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 14).inMilliseconds), 6.0),
      FuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 17).inMilliseconds), 0.0),
    ]);

    expect(log.fuelReports.length, 3);

    final trimmed = log.trimLog(0, 2);

    // Check samples
    expect(trimmed.samples.length, 3);

    // Check fuel
    expect(trimmed.fuelReports.length, 3);
    expect(trimmed.fuelReports.last.amount, 4.0);
    expect(
        trimmed.fuelReports.last.time, DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 15).inMilliseconds));
  });

  test("FuelReport - insert", () {
    final log = FlightLog(samples: [
      Geo(lat: 34, lng: 120, alt: 1, timestamp: const Duration().inMilliseconds),
      Geo(lat: 34, lng: 120.1, alt: 200, spd: 15.3974637, timestamp: const Duration(minutes: 10).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 240, spd: 24.0537096, timestamp: const Duration(minutes: 20).inMilliseconds),
      Geo(lat: 34.1, lng: 120.2, alt: 0.1, timestamp: const Duration(minutes: 30).inMilliseconds),
      Geo(lat: 34.3, lng: 120.1, alt: 0.2, spd: 15.3974637, timestamp: const Duration(minutes: 50).inMilliseconds),
      Geo(lat: 34.4, lng: 120.2, alt: 0.3, spd: 24.0537096, timestamp: const Duration(minutes: 80).inMilliseconds),
    ]);

    log.goodFile = true;

    expect(
        log.insertFuelReport(12, DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds)), true);

    expect(log.sumFuelStat, null);

    expect(log.insertFuelReport(10, DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds)),
        true);

    expect(log.fuelStats.length, 1);

    expect(log.sumFuelStat?.amount, 2);
    expect(log.sumFuelStat?.mpl, 4619.239121840687);
  });
}
