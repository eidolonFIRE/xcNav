import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/my_telemetry.dart';
import 'package:xcnav/services/ble_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/util.dart';

/// Drives a MyTelemetry instance through simulated time.
class FlightSim {
  final MyTelemetry telemetry = MyTelemetry();
  DateTime now;
  double lat = 37;
  double lng = -122;

  FlightSim(this.now);

  /// Feed GPS fixes every `step` for `duration`.
  void run(Duration duration, {double speed = 0, double alt = 100, Duration step = const Duration(seconds: 5)}) {
    final end = now.add(duration);
    while (now.isBefore(end)) {
      now = now.add(step);
      // Move north at `speed` m/s
      lat += speed * step.inSeconds / 111111;
      withClock(Clock.fixed(now), () {
        telemetry.updateGeo(
            Position(
              longitude: lng,
              latitude: lat,
              timestamp: now,
              accuracy: 1,
              altitude: alt,
              altitudeAccuracy: 1,
              headingAccuracy: 1,
              heading: 0,
              speed: speed,
              speedAccuracy: 0,
            ),
            bypassRecording: true);
      });
    }
  }

  void startFlight() => withClock(Clock.fixed(now), telemetry.startFlight);
  void stopFlight() => withClock(Clock.fixed(now), () => telemetry.stopFlight(bypassRecording: true));

  /// Same as the "now" / pre-flight entry in the live fuel dialog.
  void reportFuel(double amount) => telemetry.fuelReportController.insertFuelReport(now, amount);

  /// Same as the "launch" entry in the live fuel dialog while in flight.
  void reportLaunchFuel(double amount) => telemetry.fuelReportController.insertFuelReport(telemetry.takeOff!, amount);

  List<FuelReport> get reports => telemetry.fuelReportController.fuelReports;

  DateTime get firstSampleTime => DateTime.fromMillisecondsSinceEpoch(telemetry.recordGeo.first.time);
  DateTime get lastSampleTime => DateTime.fromMillisecondsSinceEpoch(telemetry.recordGeo.last.time);

  /// Every fuel report must fall within the recorded samples of the current flight.
  void expectReportsWithinLog() {
    for (final each in reports) {
      expect(each.time.isBefore(firstSampleTime), isFalse,
          reason: "Report ${each.time} (${each.amount}) is before log start $firstSampleTime");
      expect(each.time.isAfter(lastSampleTime), isFalse,
          reason: "Report ${each.time} (${each.amount}) is after log end $lastSampleTime");
    }
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // MyTelemetry starts the IMU on construction; stub the sensors plugin.
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      "dev.fluttercommunity.plus/sensors/method",
      "dev.fluttercommunity.plus/sensors/accelerometer",
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    SharedPreferences.setMockInitialValues({
      "profile.name": "Mr Test",
      "profile.id": "1234",
      "profile.secretID": "1234abcd",
    });
    settingsMgr = SettingsMgr(await SharedPreferences.getInstance());
    settingsMgr.forceGpsAltitude.value = true;
  });

  group("Fuel reports across sequential flights in one session", () {
    test("refuel between flights", () {
      final sim = FlightSim(DateTime(2026, 6, 1, 9));

      // --- Flight 1
      sim.run(const Duration(minutes: 5));
      sim.reportFuel(10);
      sim.run(const Duration(minutes: 2));
      sim.startFlight();
      final takeOff1 = sim.telemetry.takeOff!;
      sim.run(const Duration(minutes: 30), speed: 15);
      sim.reportFuel(7);
      sim.run(const Duration(minutes: 30), speed: 15);
      sim.stopFlight();
      final landing1 = sim.telemetry.landing!;

      expect(sim.reports.length, 3);
      expect(sim.reports.first.time, takeOff1);
      expect(sim.reports.first.amount, 10);
      expect(sim.reports.last.time, landing1);
      expect(sim.reports.last.amount, closeTo(4, 0.1));
      sim.expectReportsWithinLog();

      // --- Ground, refuel
      sim.run(const Duration(minutes: 20));
      sim.reportFuel(12);
      sim.run(const Duration(minutes: 10));

      // --- Flight 2
      sim.startFlight();
      final takeOff2 = sim.telemetry.takeOff!;
      expect(sim.reports.length, 1);
      expect(sim.reports.first.time, takeOff2);
      expect(sim.reports.first.amount, 12);
      sim.expectReportsWithinLog();

      sim.run(const Duration(minutes: 30), speed: 15);
      sim.reportFuel(9);
      sim.run(const Duration(minutes: 30), speed: 15);
      sim.stopFlight();
      final landing2 = sim.telemetry.landing!;

      expect(sim.reports.map((e) => e.time).toList(), [takeOff2, sim.reports[1].time, landing2]);
      expect(sim.reports.map((e) => e.amount).toList(), [12, 9, closeTo(6, 0.1)]);
      sim.expectReportsWithinLog();
      final stats = sim.telemetry.fuelReportController.getFuelStats(sim.telemetry.recordGeo);
      expect(stats.every((e) => e.isValid), isTrue);
    });

    test("no refuel between flights carries landing amount", () {
      final sim = FlightSim(DateTime(2026, 6, 1, 9));

      sim.run(const Duration(minutes: 5));
      sim.reportFuel(10);
      sim.run(const Duration(minutes: 2));
      sim.startFlight();
      sim.run(const Duration(minutes: 30), speed: 15);
      sim.reportFuel(8);
      sim.run(const Duration(minutes: 10), speed: 15);
      sim.stopFlight();
      final landingAmount = sim.reports.last.amount;

      sim.run(const Duration(minutes: 15));
      sim.startFlight();
      expect(sim.reports.length, 1);
      expect(sim.reports.first.time, sim.telemetry.takeOff);
      expect(sim.reports.first.amount, landingAmount);
      sim.expectReportsWithinLog();
    });

    test("quick relaunch shortly after landing", () {
      final sim = FlightSim(DateTime(2026, 6, 1, 9));

      sim.run(const Duration(minutes: 5));
      sim.reportFuel(10);
      sim.run(const Duration(minutes: 2));
      sim.startFlight();
      sim.run(const Duration(minutes: 30), speed: 15);
      sim.reportFuel(8);
      sim.run(const Duration(minutes: 10), speed: 15);
      sim.stopFlight();

      sim.run(const Duration(seconds: 40));
      sim.startFlight();
      sim.expectReportsWithinLog();
      expect(sim.reports.length, 1);

      sim.run(const Duration(minutes: 20), speed: 15);
      sim.reportFuel(6);
      sim.run(const Duration(minutes: 5), speed: 15);
      sim.stopFlight();
      expect(sim.reports.length, 3);
      sim.expectReportsWithinLog();
    });

    test("launch fuel entered in flight 2 after landing report of flight 1", () {
      final sim = FlightSim(DateTime(2026, 6, 1, 9));

      sim.run(const Duration(minutes: 5));
      sim.reportFuel(10);
      sim.run(const Duration(minutes: 2));
      sim.startFlight();
      sim.run(const Duration(minutes: 30), speed: 15);
      sim.reportFuel(8);
      sim.run(const Duration(minutes: 10), speed: 15);
      sim.stopFlight();

      sim.run(const Duration(minutes: 15));
      sim.startFlight();
      sim.run(const Duration(minutes: 5), speed: 15);
      sim.reportLaunchFuel(12);
      expect(sim.reports.length, 1);
      expect(sim.reports.first.amount, 12);
      expect(sim.reports.first.time, sim.telemetry.takeOff);
      sim.expectReportsWithinLog();
    });

    test("refuel between flights with xc170 fuel sensor connected", () {
      final sensor = bleDeviceXc170.telemetry.fuel.log;
      addTearDown(sensor.clear);
      final sim = FlightSim(DateTime(2026, 6, 1, 9));
      void sensorReads(double amount) => sensor.add(TimestampValue(sim.now.millisecondsSinceEpoch, amount));

      // --- Flight 1
      sim.run(const Duration(minutes: 5));
      sensorReads(10);
      sim.startFlight();
      expect(sim.reports.single.amount, 10);
      sim.run(const Duration(minutes: 30), speed: 15);
      sensorReads(7);
      sim.reportFuel(7);
      sim.run(const Duration(minutes: 30), speed: 15);
      sim.stopFlight();
      expect(sim.reports.last.amount, closeTo(4, 0.1));

      // --- Ground, refuel. Sensor sees it, but no fuel report is made on the ground.
      sim.run(const Duration(minutes: 20));
      sensorReads(12);
      sim.run(const Duration(seconds: 30));
      sensorReads(12);

      // --- Flight 2 should start from the sensor reading, not flight 1's landing.
      sim.startFlight();
      expect(sim.reports.length, 1);
      expect(sim.reports.first.time, sim.telemetry.takeOff);
      expect(sim.reports.first.amount, 12);
    });

    test("stale sensor reading is ignored", () {
      final sensor = bleDeviceXc170.telemetry.fuel.log;
      addTearDown(sensor.clear);
      final sim = FlightSim(DateTime(2026, 6, 1, 9));

      sensor.add(TimestampValue(sim.now.millisecondsSinceEpoch, 3));
      sim.run(const Duration(minutes: 10));
      sim.reportFuel(10);
      sim.run(const Duration(minutes: 1));
      sim.startFlight();
      expect(sim.reports.single.amount, 10);
    });
  });

  group("Resume interrupted flight", () {
    /// Log that was being recorded before the app restarted.
    FlightLog previousLog(FlightSim sim, {required Duration endedAgo, double latOffset = 0}) {
      final end = sim.now.subtract(endedAgo);
      return FlightLog(filename: "prev.json", samples: [
        for (int i = 30; i >= 0; i--)
          Geo(
              lat: sim.lat + latOffset - i * 0.001,
              lng: sim.lng,
              alt: 100,
              timestamp: end.subtract(Duration(minutes: i)).millisecondsSinceEpoch)
      ]);
    }

    test("app restarted mid-flight continues the previous log", () {
      final sim = FlightSim(DateTime(2026, 6, 1, 9));
      sim.run(const Duration(seconds: 30));
      final prev = previousLog(sim, endedAgo: const Duration(minutes: 1));
      sim.telemetry.resumeCandidate = prev;

      sim.startFlight();
      expect(sim.telemetry.resumedLog, same(prev));
      expect(sim.telemetry.flightStart, prev.startTime);
      expect(sim.telemetry.resumeCandidate, isNull);
    });

    test("previous log ended too long ago", () {
      final sim = FlightSim(DateTime(2026, 6, 1, 9));
      sim.run(const Duration(seconds: 30));
      sim.telemetry.resumeCandidate = previousLog(sim, endedAgo: const Duration(minutes: 30));

      sim.startFlight();
      expect(sim.telemetry.resumedLog, isNull);
      expect(sim.telemetry.flightStart, sim.telemetry.takeOff);
    });

    test("previous log ended somewhere else", () {
      final sim = FlightSim(DateTime(2026, 6, 1, 9));
      sim.run(const Duration(seconds: 30));
      sim.telemetry.resumeCandidate = previousLog(sim, endedAgo: const Duration(minutes: 1), latOffset: 1);

      sim.startFlight();
      expect(sim.telemetry.resumedLog, isNull);
    });

    test("second flight of the session never resumes", () {
      final sim = FlightSim(DateTime(2026, 6, 1, 9));
      sim.run(const Duration(seconds: 30));
      sim.startFlight();
      sim.run(const Duration(minutes: 10), speed: 15);
      sim.stopFlight();
      sim.run(const Duration(minutes: 1));

      sim.telemetry.resumeCandidate = previousLog(sim, endedAgo: const Duration(minutes: 1));
      sim.startFlight();
      expect(sim.telemetry.resumedLog, isNull);
    });
  });
}
