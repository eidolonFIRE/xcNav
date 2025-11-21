// ignore_for_file: avoid_print
// This is a unit test to pump a flight log (*.json file) through
// the wind estimator and print out the results onscreen

// Just set the environment varable XCNAV_LOG to the location of the file and then run
// > flutter test test/wind_from_json_test.dart

// On Windows, you can call a batch script that makes this easy:
// > run_wind_test.bat <path\to\log.json>

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/vector.dart';
import 'package:xcnav/providers/wind.dart';

void main() {
  test('Wind solve from flight log', () async {
    final path = Platform.environment['XCNAV_LOG'];
    expect(path, isNotNull, reason: 'Set env var XCNAV_LOG to a .json flight log');
    final file = File(path!);
    expect(await file.exists(), isTrue, reason: 'File not found: $path');

    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    final log = FlightLog.fromJson(path, data, rawJson: content);


    final int logStartTimeSec = log.samples.first.time ~/ 1000;

    final wind = Wind(isRunningReplayFromLog: true);

    int successfulWindReports = 0;
    // Print every time a new wind result is solved.
    wind.addListener(() {
      final r = wind.result;
      if (r != null) {
        final windSpeed = r.windSpd;
        final hdgDeg = (r.windHdg * 180 / pi) % 360;
        final airSpeed = r.airspeed;

        // Speeds are in m/s
        // For knots, multiply by 1.943844
        // For kph, multiply by 3.6
        // For mph, multiply by 2.23694
        final windSpeedMph = windSpeed * 2.23694;
        final airSpeedMph = airSpeed * 2.23694;

        // Elapsed minutes from first to latest log entry
        final int latestTimeSec = r.timestamp.millisecondsSinceEpoch ~/ 1000.0;
        final double elapsedMin = (latestTimeSec - logStartTimeSec) / 60.0;

        successfulWindReports++;

        print('${elapsedMin.toStringAsFixed(1)}m: windSpeed=${windSpeedMph.toStringAsFixed(2)}mph '
              'hdg=${hdgDeg.toStringAsFixed(1)}° airSpeed=${airSpeedMph.toStringAsFixed(2)}mph');
      }
    });

    // Feed samples including altitude and timestamp from the log.
    for (final geo in log.samples) {
      if (geo.spd > 1) {
        wind.handleVector(Vector(
          geo.hdg,
          geo.spd,
          alt: geo.alt,
          timestamp: DateTime.fromMillisecondsSinceEpoch(geo.time),
        ));
      }
    }

    final double reportPct = 100.0 * successfulWindReports / log.samples.length;
    print('Got a wind report for ${reportPct.toStringAsFixed(1)}% of the samples');

    // Pass criteria: require wind reports for > 50%% of samples
    expect(reportPct, greaterThan(50.0),
        reason: 'Insufficient wind reports; require > 50% coverage.');
  });
}
