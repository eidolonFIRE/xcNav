import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/util.dart';

/// These tests must pass regardless of the timezone of the machine running them.
/// Every expectation is phrased either in absolute (UTC) time or in the log's recorded timezone.

FlightLog makeLog(DateTime startUtc, {Duration? utcOffset, Duration length = const Duration(minutes: 30)}) {
  final t0 = startUtc.millisecondsSinceEpoch;
  return FlightLog(
      utcOffset: utcOffset,
      samples: [
        Geo(lat: 38, lng: -122, alt: 100, timestamp: t0),
        Geo(lat: 38.01, lng: -122, alt: 200, timestamp: t0 + length.inMilliseconds ~/ 2),
        Geo(lat: 38.02, lng: -122, alt: 100, timestamp: t0 + length.inMilliseconds),
      ],
      fuelReports: [
        FuelReport(DateTime.fromMillisecondsSinceEpoch(t0), 10),
        FuelReport(DateTime.fromMillisecondsSinceEpoch(t0 + length.inMilliseconds), 5),
      ]);
}

String hm(DateTime t) => DateFormat("H:mm").format(t);

void main() {
  version = PackageInfo(appName: "xcNav", packageName: "xcNav", version: "test", buildNumber: "100");

  group("original timezone display", () {
    test("summer log (PDT -7)", () {
      final log = makeLog(DateTime.utc(2024, 6, 27, 14, 29), utcOffset: const Duration(hours: -7));
      expect(hm(log.startTimeOriginal!), "7:29");
      expect(hm(log.endTimeOriginal!), "7:59");
      expect(log.title, "Jun 27 - 2024");
    });

    test("winter log (PST -8) is not shifted by the viewer's current DST", () {
      // Previously used DateTime.now().timeZoneOffset, which is wrong whenever DST state differs from recording.
      final log = makeLog(DateTime.utc(2024, 1, 15, 18, 0), utcOffset: const Duration(hours: -8));
      expect(hm(log.startTimeOriginal!), "10:00");
    });

    test("fractional hour offset (IST +5:30)", () {
      final log = makeLog(DateTime.utc(2024, 3, 1, 3, 15), utcOffset: const Duration(hours: 5, minutes: 30));
      expect(hm(log.startTimeOriginal!), "8:45");
    });

    test("fractional negative offset (NST -3:30)", () {
      final log = makeLog(DateTime.utc(2024, 1, 10, 13, 0), utcOffset: const Duration(hours: -3, minutes: -30));
      expect(hm(log.startTimeOriginal!), "9:30");
    });

    test("date uses recorded timezone, not viewer's", () {
      // 2024-07-01 02:00 UTC is still June 30 in Denver
      final log = makeLog(DateTime.utc(2024, 7, 1, 2, 0), utcOffset: const Duration(hours: -6));
      expect(log.startTimeOriginal!.day, 30);
      expect(log.startTimeOriginal!.month, 6);
      expect(log.title, "Jun 30 - 2024");
    });

    test("original time does not change the underlying instant", () {
      final start = DateTime.utc(2024, 6, 27, 14, 29);
      final log = makeLog(start, utcOffset: const Duration(hours: -7));
      expect(log.startTime!.millisecondsSinceEpoch, start.millisecondsSinceEpoch);
    });

    test("unknown timezone falls back to viewer's local time", () {
      final start = DateTime.utc(2024, 6, 27, 14, 29);
      final log = makeLog(start);
      expect(log.utcOffset, null);
      expect(log.startTimeOriginal, start.toLocal());
      expect(log.startTimeOriginal!.isUtc, false);
    });

    test("fromOriginalTime is the inverse of toOriginalTime", () {
      for (final offset in [
        const Duration(hours: -7),
        const Duration(hours: 5, minutes: 30),
        const Duration(hours: 13),
        null
      ]) {
        final log = makeLog(DateTime.utc(2024, 11, 3, 9, 0), utcOffset: offset);
        final t = DateTime.utc(2024, 11, 3, 9, 17, 42);
        expect(log.fromOriginalTime(log.toOriginalTime(t)).millisecondsSinceEpoch, t.millisecondsSinceEpoch,
            reason: "offset $offset");
      }
    });

    test("fromOriginalTime reads wall clock fields in recorded timezone", () {
      final log = makeLog(DateTime.utc(2024, 6, 27, 14, 29), utcOffset: const Duration(hours: -7));
      // Time picker hands back a wall-clock time of 7:45 (in the recorded zone)
      final picked = DateTime.utc(2024, 6, 27, 7, 45);
      expect(log.fromOriginalTime(picked).millisecondsSinceEpoch,
          DateTime.utc(2024, 6, 27, 14, 45).millisecondsSinceEpoch);
    });
  });

  group("persistence", () {
    test("json round trip keeps fractional offset", () {
      final log = makeLog(DateTime.utc(2024, 3, 1, 3, 15), utcOffset: const Duration(hours: 5, minutes: 30));
      final json = jsonDecode(jsonEncode(log.toJson()));
      expect(json["utcOffsetMinutes"], 330);
      expect(json["timezone"], 5);

      final loaded = FlightLog.fromJson("", json);
      expect(loaded.utcOffset, const Duration(hours: 5, minutes: 30));
      expect(hm(loaded.startTimeOriginal!), "8:45");
    });

    test("legacy logs with only whole-hour timezone", () {
      final json = jsonDecode(jsonEncode(makeLog(DateTime.utc(2024, 6, 27, 14, 29)).toJson()));
      expect(json.containsKey("timezone"), false);
      json["timezone"] = -7;

      final loaded = FlightLog.fromJson("", json);
      expect(loaded.goodFile, true);
      expect(loaded.utcOffset, const Duration(hours: -7));
      expect(hm(loaded.startTimeOriginal!), "7:29");
    });

    test("no timezone stays unknown", () {
      final loaded = FlightLog.fromJson("", jsonDecode(jsonEncode(makeLog(DateTime.utc(2024, 6, 27)).toJson())));
      expect(loaded.utcOffset, null);
    });

    test("crop keeps offset", () {
      final log = makeLog(DateTime.utc(2024, 6, 27, 14, 29), utcOffset: const Duration(hours: -7));
      expect(log.cropLog(Range(1, 2)).utcOffset, const Duration(hours: -7));
    });

    test("gpx timestamps are UTC", () {
      final log = makeLog(DateTime.utc(2024, 6, 27, 14, 29), utcOffset: const Duration(hours: -7));
      expect(log.toGPX(), contains("<time>2024-06-27T14:29:00.000Z</time>"));
    });
  });

  group("IGC import", () {
    String igc({String date = "HFDTE270624", String tz = "HFTZNTIMEZONE:-7", List<String>? bRecords}) => [
          "AXFH000",
          date,
          tz,
          ...(bRecords ??
              [
                "B1429323826810N12236459WA0050000500005003043295347",
                "B1430273826905N12236802WA0054300544004003047238237",
              ]),
        ].join("\n");

    test("B record times are UTC", () {
      final log = FlightLog.fromIGC(igc());
      expect(log.goodFile, true);
      expect(log.startTime!.millisecondsSinceEpoch, DateTime.utc(2024, 6, 27, 14, 29, 32).millisecondsSinceEpoch);
      expect(log.endTime!.millisecondsSinceEpoch, DateTime.utc(2024, 6, 27, 14, 30, 27).millisecondsSinceEpoch);
      expect(log.utcOffset, const Duration(hours: -7));
      expect(hm(log.startTimeOriginal!), "7:29");
    });

    test("HFDTEDATE: date format", () {
      final log = FlightLog.fromIGC(igc(date: "HFDTEDATE:270624,01"));
      expect(log.goodFile, true);
      expect(log.startTime!.millisecondsSinceEpoch, DateTime.utc(2024, 6, 27, 14, 29, 32).millisecondsSinceEpoch);
    });

    test("fractional timezone", () {
      final log = FlightLog.fromIGC(igc(tz: "HFTZNTIMEZONE:+5.5"));
      expect(log.goodFile, true);
      expect(log.utcOffset, const Duration(hours: 5, minutes: 30));
      expect(hm(log.startTimeOriginal!), "19:59");
    });

    test("decimal formatted timezone", () {
      final log = FlightLog.fromIGC(igc(tz: "HFTZNTIMEZONE:-6.00"));
      expect(log.goodFile, true);
      expect(log.utcOffset, const Duration(hours: -6));
    });

    test("missing timezone", () {
      final log = FlightLog.fromIGC(igc(tz: "HFPLTPILOT:John Smith"));
      expect(log.goodFile, true);
      expect(log.utcOffset, null);
      expect(log.startTime!.millisecondsSinceEpoch, DateTime.utc(2024, 6, 27, 14, 29, 32).millisecondsSinceEpoch);
    });

    test("flight crossing UTC midnight", () {
      // Evening flight in California: 23:59 UTC -> 00:01 UTC next day
      final log = FlightLog.fromIGC(igc(bRecords: [
        "B2359003826810N12236459WA0050000500005003043295347",
        "B2359593826820N12236486WA0049800501004003042297331",
        "B0000303826823N12236493WA0049900501004003043294335",
        "B0001003826826N12236501WA0050000501004003043297179",
      ]));
      expect(log.goodFile, true);
      expect(log.samples.length, 4);
      expect(log.endTime!.millisecondsSinceEpoch, DateTime.utc(2024, 6, 28, 0, 1, 0).millisecondsSinceEpoch);
      expect(log.durationTime, const Duration(minutes: 2));
      expect(hm(log.endTimeOriginal!), "17:01");
    });
  });
}
