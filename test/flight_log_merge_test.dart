import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/util.dart';

const minute = 60 * 1000;

/// Samples every 10 seconds from [start] to [end] (minutes), moving north at about 15m/s.
List<Geo> track(int start, int end) {
  return [
    for (int t = start * minute; t <= end * minute; t += 10000)
      Geo(lat: 34 + t / 1000 * 15 / 111111, lng: -120, alt: 500, timestamp: t)
  ];
}

DateTime at(int minutes) => DateTime.fromMillisecondsSinceEpoch(minutes * minute);

void main() {
  version = PackageInfo(appName: "xcNav", packageName: "xcNav", version: "test", buildNumber: "100");

  group("merge", () {
    final wpShared = Waypoint(name: "shared", latlngs: [const LatLng(35, -120)]);
    final logA = FlightLog(
        samples: track(0, 20),
        gForceSamples: [TimestampValue(5 * minute, 1.5), TimestampValue(19 * minute, 2.0)],
        waypoints: [wpShared],
        fuelReports: [FuelReport(at(0), 10)],
        filename: "a.json",
        utcOffset: const Duration(hours: -7),
        bleDevicesJson: {
          "xc170": {
            "id": "xc170",
            "datas": {
              "telemetry": {
                "rpm": {
                  "start_time": 0,
                  "data": [
                    [0, 1000],
                    [20 * minute, 1100]
                  ]
                }
              }
            }
          }
        });
    logA.customTitle = "Big XC";

    final logB = FlightLog(
        samples: track(21, 40),
        gForceSamples: [TimestampValue(30 * minute, 1.8)],
        waypoints: [
          wpShared,
          Waypoint(name: "new", latlngs: [const LatLng(36, -120)])
        ],
        fuelReports: [FuelReport(at(21), 8), FuelReport(at(40), 4)],
        filename: "b.json",
        bleDevicesJson: {
          "xc170": {
            "id": "xc170",
            "datas": {
              "telemetry": {
                "rpm": {
                  "start_time": 21 * minute,
                  "data": [
                    [0, 1200],
                    [19 * minute, 1300]
                  ]
                }
              }
            }
          },
          "sp140": {"id": "sp140"}
        });

    test("joins everything in time order, regardless of argument order", () {
      for (final merged in [FlightLog.merge(logA, logB), FlightLog.merge(logB, logA)]) {
        expect(merged.filename, "a.json");
        expect(merged.startTime, logA.startTime);
        expect(merged.endTime, logB.endTime);
        expect(merged.samples.length, logA.samples.length + logB.samples.length);
        expect(merged.gForceSamples.map((e) => e.time), [5 * minute, 19 * minute, 30 * minute]);
        expect(merged.waypoints.map((e) => e.name), ["shared", "new"]);
        expect(merged.fuelReportController.fuelReports.map((e) => e.amount), [10, 8, 4]);
        expect(merged.customTitle, "Big XC");
        expect(merged.utcOffset, const Duration(hours: -7));
        expect(merged.unsaved, isTrue);

        final rpm = merged.bleDevicesJson!["xc170"]["datas"]["telemetry"]["rpm"];
        expect(rpm["start_time"], 0);
        expect(rpm["data"], [
          [0, 1000],
          [20 * minute, 1100],
          [21 * minute, 1200],
          [40 * minute, 1300],
        ]);
        expect(merged.bleDevicesJson!["sp140"], {"id": "sp140"});
        expect(merged.getBleDeviceSeries("xc170", "rpm").length, 4);
      }
    });

    test("refuses logs that overlap", () {
      expect(() => FlightLog.merge(logA, FlightLog(samples: track(15, 30))), throwsA(anything));
      expect(() => FlightLog.merge(FlightLog(samples: track(15, 30)), logA), throwsA(anything));
      // Sharing a timestamp counts as overlapping
      expect(() => FlightLog.merge(logA, FlightLog(samples: track(20, 30))), throwsA(anything));
    });

    test("survives a save / load round trip", () {
      final merged = FlightLog.merge(logA, logB);
      final loaded = FlightLog.fromJson("a.json", jsonDecode(jsonEncode(merged.toJson())));
      expect(loaded.goodFile, isTrue);
      expect(loaded.samples.length, merged.samples.length);
      expect(loaded.customTitle, "Big XC");
      expect(loaded.getBleDeviceSeries("xc170", "rpm").length, 4);
    });
  });

  test("custom title is saved", () {
    final log = FlightLog(samples: track(0, 5));
    log.customTitle = "Beach run";
    expect(FlightLog.fromJson(null, jsonDecode(jsonEncode(log.toJson()))).customTitle, "Beach run");
    expect(log.cropLog(Range(0, 3)).customTitle, "Beach run");
  });

  group("canResumeAt", () {
    final log = FlightLog(samples: track(0, 20));
    final last = log.samples.last;

    test("shortly after, nearby", () {
      expect(log.canResumeAt(Geo(lat: last.lat + 0.005, lng: last.lng, timestamp: 21 * minute)), isTrue);
    });
    test("too long after", () {
      expect(log.canResumeAt(Geo(lat: last.lat, lng: last.lng, timestamp: 30 * minute)), isFalse);
    });
    test("too far away to have flown there", () {
      expect(log.canResumeAt(Geo(lat: last.lat + 1, lng: last.lng, timestamp: 21 * minute)), isFalse);
    });
    test("same time as the last sample", () {
      expect(log.canResumeAt(Geo(lat: last.lat, lng: last.lng, timestamp: last.time)), isFalse);
    });
    test("before the log ended", () {
      expect(log.canResumeAt(Geo(lat: last.lat, lng: last.lng, timestamp: 10 * minute)), isFalse);
    });
  });

  group("LogStore", () {
    setUp(() => logStore.logs.clear());

    test("findAdjacentLog", () {
      logStore.updateLog("a", FlightLog(samples: track(0, 20)));
      logStore.updateLog("b", FlightLog(samples: track(22, 40)));
      logStore.updateLog("c", FlightLog(samples: track(200, 220)));
      // 15 min after "b" - too long to be the same flight
      logStore.updateLog("d", FlightLog(samples: track(55, 60)));
      // Overlaps "c"
      logStore.updateLog("e", FlightLog(samples: track(210, 230)));

      expect(logStore.findAdjacentLog("a", next: true), "b");
      expect(logStore.findAdjacentLog("a", next: false), isNull);
      expect(logStore.findAdjacentLog("b", next: false), "a");
      expect(logStore.findAdjacentLog("b", next: true), isNull);
      expect(logStore.findAdjacentLog("c", next: false), isNull);
      expect(logStore.findAdjacentLog("c", next: true), isNull);
      expect(logStore.findAdjacentLog("e", next: false), isNull);
    });
  });
}
