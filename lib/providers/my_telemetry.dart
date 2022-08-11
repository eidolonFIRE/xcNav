import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_barometer/flutter_barometer.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

// --- Models
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';

class MyTelemetry with ChangeNotifier, WidgetsBindingObserver {
  Geo geo = Geo();

  /// Liters
  double fuel = 0;

  /// Liter/Hour
  double fuelBurnRate = 4;
  Geo geoPrev = Geo();

  List<Geo> recordGeo = [];
  List<LatLng> flightTrace = [];
  DateTime? takeOff;
  Geo? launchGeo;
  DateTime? lastSavedLog;

  // in-flight hysterisis
  int triggerHyst = 0;
  bool inFlight = false;

  // fuel save interval
  double? lastSavedFuelLevel;

  /// Latest Barometric Reading
  BarometerValue? baro;

  /// Ambient barometric reading fetched from web API
  BarometerValue? baroAmbient;
  bool baroAmbientRequested = false;
  bool stationFound = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && inFlight) saveFlight();
  }

  @override
  void dispose() {
    _save();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  MyTelemetry() {
    _load();
    WidgetsBinding.instance.addObserver(this);
  }

  void _load() async {
    final prefs = await SharedPreferences.getInstance();
    fuel = prefs.getDouble("me.fuel") ?? 0;
    lastSavedFuelLevel = fuel;
    fuelBurnRate = prefs.getDouble("me.fuelBurnRate") ?? 4;
  }

  void _save() async {
    debugPrint("Fuel Level Saved");
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble("me.fuel", fuel);
    prefs.setDouble("me.fuelBurnRate", fuelBurnRate);
    lastSavedFuelLevel = fuel;
  }

  Future saveFlight() async {
    lastSavedLog = DateTime.now();
    Directory tempDir = await getApplicationDocumentsDirectory();
    File logFile = File("${tempDir.path}/flight_logs/${recordGeo[0].time}.json");
    debugPrint("Writing ${logFile.uri} with ${recordGeo.length} samples");
    // TODO: save out the current flight plan as well!
    await logFile
        .create(recursive: true)
        .then((value) => logFile.writeAsString(jsonEncode({"samples": recordGeo.map((e) => e.toJson()).toList()})));
  }

  void fetchAmbPressure() {
    http
        .get(Uri.parse("https://api.weather.gov/points/${geo.lat.toStringAsFixed(2)},${geo.lng.toStringAsFixed(2)}"))
        .then((responseXY) {
      // nearest stations
      var msgXY = jsonDecode(responseXY.body);
      var x = msgXY["properties"]["gridX"];
      var y = msgXY["properties"]["gridY"];
      var gridId = msgXY["properties"]["gridId"];

      http.get(Uri.parse("https://api.weather.gov/gridpoints/$gridId/$x,$y/stations")).then((responsePoint) async {
        var msgPoint = jsonDecode(responsePoint.body);
        // check each for pressure
        stationFound = false;

        if (msgPoint["observationStations"] != null) {
          List<dynamic> stationList = msgPoint["observationStations"];
          for (String each in stationList) {
            if (stationFound) break;
            await http.get(Uri.parse("$each/observations/latest")).then((responseStation) {
              try {
                var msgStation = jsonDecode(responseStation.body);
                if (msgStation["properties"] != null && msgStation["properties"]["seaLevelPressure"]["value"] != null) {
                  double pressure = msgStation["properties"]["barometricPressure"]["value"] / 100;
                  debugPrint("Found Baro: $gridId, ${pressure.toStringAsFixed(2)}");
                  baroAmbient = BarometerValue(pressure);
                  baroAmbientRequested = false;
                  stationFound = true;
                }
              } catch (e) {
                debugPrint("Failed to get station info. $e");
                debugPrint(Uri.parse("$each/observations/latest").toString());
                debugPrint(responseStation.body);
              }
            });
          }
        } else {
          debugPrint("No stations found for point $gridId, $x, $y");
          // debugPrint(responsePoint.body);
        }
      });
    });
  }

  void updateGeo(Position position, {bool bypassRecording = false}) {
    // debugPrint("${location.elapsedRealtimeNanos}) ${location.latitude}, ${location.longitude}, ${location.altitude}");
    geoPrev = geo;
    geo = Geo.fromPosition(position, geoPrev, baro, baroAmbient);
    recordGeo.add(geo);

    // fetch ambient baro from weather service
    if (baroAmbient == null && !baroAmbientRequested) {
      baroAmbientRequested = true;
      try {
        fetchAmbPressure();
      } catch (e) {
        debugPrint("Failed to fetch ambient pressure... $e");
      }
    }

    // --- In-Flight detector
    const triggerDuration = Duration(seconds: 30);
    if ((geo.spd > 2.5 || geo.vario.abs() > 1.0) ^ inFlight) {
      triggerHyst += geo.time - geoPrev.time;
    } else {
      triggerHyst = 0;
    }
    if (triggerHyst > triggerDuration.inMilliseconds) {
      inFlight = !inFlight;
      triggerHyst = 0;
      if (inFlight) {
        // TODO: Use real timestamp search here (it's hardcoded to 5seconds)
        final launchIndex = max(0, recordGeo.length - (triggerDuration.inSeconds ~/ 5) - 5);
        launchGeo = recordGeo[launchIndex];

        takeOff = DateTime.fromMillisecondsSinceEpoch(launchGeo!.time);
        lastSavedLog = DateTime.fromMillisecondsSinceEpoch(launchGeo!.time);
        debugPrint("In Flight!!!  Launchindex: $launchIndex / ${recordGeo.length}");

        // clear the log
        recordGeo.removeRange(0, launchIndex);
      } else {
        debugPrint("Flight Ended");

        // Save current flight to log
        if (!(bypassRecording)) {
          saveFlight();
        }
      }
    }

    if (inFlight) {
      // --- burn fuel
      fuel = max(0, fuel - fuelBurnRate * (geo.time - geoPrev.time) / 3600000.0);

      // --- Record path
      if (flightTrace.isEmpty || (flightTrace.isNotEmpty && latlngCalc.distance(flightTrace.last, geo.latLng) > 50)) {
        flightTrace.add(geo.latLng);
        // --- keep list from bloating
        if (flightTrace.length > 10000) {
          flightTrace.removeRange(0, 100);
        }
      }

      // --- Periodically save log
      if (!bypassRecording &&
          lastSavedLog != null &&
          lastSavedLog!.add(const Duration(minutes: 5)).isBefore(DateTime.now())) {
        saveFlight();
      }
    }

    notifyListeners();
  }

  void updateFuel(double delta) {
    fuel = max(0, fuel + delta);
    // every so often, save the fuel level in case the app crashes
    if ((fuel - (lastSavedFuelLevel ?? fuel)).abs() > 0.2) _save();
    notifyListeners();
  }

  void updateFuelBurnRate(double delta) {
    fuelBurnRate = max(0.1, fuelBurnRate + delta);
    _save();
    notifyListeners();
  }

  Color fuelIndicatorColor(ETA next, ETA trip) {
    double fuelTime = fuel / fuelBurnRate;
    if (fuelTime > 0.0001 && inFlight && next.time != null) {
      if (fuelTime < 0.25 || (fuelTime < next.time!.inMilliseconds.toDouble() / 3600000)) {
        // Red at 15minutes of fuel left or can't make selected waypoint
        return Colors.red.shade900;
      } else if (fuelTime < trip.time!.inMilliseconds.toDouble() / 3600000) {
        // Orange if not enough fuel to finish the plan
        return Colors.amber.shade900;
      }
    }
    return Colors.grey.shade900;
  }

  Duration get fuelTimeRemaining => Duration(milliseconds: ((fuel / fuelBurnRate) * 3600000).ceil());

  Polyline buildFlightTrace() {
    return Polyline(points: flightTrace, strokeWidth: 4, color: const Color.fromARGB(150, 255, 50, 50), isDotted: true);
  }
}
