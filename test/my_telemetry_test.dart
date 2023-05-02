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

    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(myTelemetry.sumFuelStat, null);

    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);

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

    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 0).inMilliseconds), 12);
    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(myTelemetry.sumFuelStat, null);

    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);

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

    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 2).inMilliseconds), 12);

    expect(myTelemetry.sumFuelStat, null);

    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 12).inMilliseconds), 10);
    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 30).inMilliseconds), 10);
    myTelemetry.addFuelReport(DateTime.fromMillisecondsSinceEpoch(const Duration(minutes: 35).inMilliseconds), 12);

    expect(myTelemetry.sumFuelStat?.amount, 2);
    expect(myTelemetry.sumFuelStat?.mpl, 4619.239121840687);
  });
}
