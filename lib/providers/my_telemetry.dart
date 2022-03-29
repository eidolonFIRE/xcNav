import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:location/location.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart' as geoLocator;

import '../models/eta.dart';
import '../models/geo.dart';

class MyTelemetry with ChangeNotifier {
  // Live Readings
  Geo geo = Geo();
  double fuel = 0; // Liters
  double fuelBurnRate = 4; // Liter/Hour

  // Calculated
  Geo? geoPrev;

  // Recorded
  List<Geo> recordGeo = [];
  List<LatLng> flightTrace = [];

  // in-flight hysterisis
  int triggerHyst = 0;
  bool inFlight = false;

  @override
  void dispose() {
    save();
    super.dispose();
  }

  MyTelemetry() {
    load();
  }

  void load() async {
    final prefs = await SharedPreferences.getInstance();
    fuel = prefs.getDouble("me.fuel") ?? 0;
    fuelBurnRate = prefs.getDouble("me.fuelBurnRate") ?? 4;
  }

  void save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setDouble("me.fuel", fuel);
    prefs.setDouble("me.fuelBurnRate", fuelBurnRate);
  }

  void updateGeo(Geo newGeo) {
    // debugPrint("${location.elapsedRealtimeNanos}) ${location.latitude}, ${location.longitude}, ${location.altitude}");
    geoPrev = geo;
    geo = newGeo;

    // --- In-Flight detector
    if ((geo.spd.abs() > 2.5 || geo.vario.abs() > 1.0) ^ inFlight) {
      triggerHyst += geo.time - geoPrev!.time;
    } else {
      triggerHyst = 0;
    }
    if (triggerHyst > 1000 * 20) {
      inFlight = !inFlight;
      triggerHyst = 0;
      if (inFlight) {
        debugPrint("In Flight!!!");
      } else {
        debugPrint("Flight Ended");
      }
    }

    if (inFlight) {
      // --- burn fuel
      fuel =
          max(0, fuel - fuelBurnRate * (geo.time - geoPrev!.time) / 3600000.0);

      // --- Record path
      recordGeo.add(geo);
      if (flightTrace.isEmpty ||
          (flightTrace.isNotEmpty &&
              latlngCalc.distance(flightTrace.last, geo.latLng) > 50)) {
        flightTrace.add(geo.latLng);
        // --- keep list from bloating
        if (flightTrace.length > 10000) {
          flightTrace.removeRange(0, 100);
        }
      }
    }

    notifyListeners();
  }

  void updateFuel(double delta) {
    fuel = max(0, fuel + delta);
    notifyListeners();
  }

  void updateFuelBurnRate(double delta) {
    fuelBurnRate = max(0.1, fuelBurnRate + delta);
    notifyListeners();
  }

  String fuelTimeRemaining() {
    return hhmmFormat
        .firstMatch(
            Duration(milliseconds: (fuel / fuelBurnRate * 3600000).toInt())
                .toString())!
        .group(0)!;
  }

  Color fuelIndicatorColor(ETA next, ETA trip) {
    double fuelTime = fuel / fuelBurnRate;
    if (fuelTime > 0.0001 && inFlight) {
      if (fuelTime < 0.25 || (fuelTime < next.time / 3600000)) {
        // Red at 15minutes of fuel left or can't make selected waypoint
        return Colors.red.shade900;
      } else if (fuelTime < trip.time / 3600000) {
        // Orange if not enough fuel to finish the plan
        return Colors.amber.shade900;
      }
    }
    return Colors.grey.shade900;
  }

  Polyline buildFlightTrace() {
    return Polyline(
        points: flightTrace,
        strokeWidth: 6,
        color: const Color.fromARGB(100, 255, 50, 50),
        isDotted: true);
  }
}
