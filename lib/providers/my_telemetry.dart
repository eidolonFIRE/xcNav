import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bisection/bisect.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/datadog.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/douglas_peucker.dart';
import 'package:xcnav/fake_path.dart';
import 'package:xcnav/gaussian_filter.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/datadog.dart' as dd;

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/vector.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/services/ble_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/secrets.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

enum FlightEventType { init, takeoff, land }

enum BarometerSrc {
  weatherkit,
  snapToGround,
  gpsAlt,
}

final Map<BarometerSrc, String> barometerSrcString = {
  BarometerSrc.weatherkit: "WeatherKit",
  BarometerSrc.snapToGround: "Snap To Ground",
  BarometerSrc.gpsAlt: "GPS Altitude",
};

/// Meters
double densityAlt(BarometerEvent ambientPressure, double ambientTemp) {
  return 145442.16 *
      (1 - pow(17.326 * (ambientPressure.pressure * 0.02953) / (459.67 + ambientTemp), 0.235)) /
      meters2Feet;
}

Geo defaultGeo = Geo(lat: 37, lng: -122);

class FlightEvent {
  final FlightEventType type;
  final DateTime time;
  final LatLng? latlng;
  FlightEvent({required this.type, required this.time, this.latlng});
}

class MyTelemetry with ChangeNotifier, WidgetsBindingObserver {
  BuildContext? globalContext;
  bool isInitialized = false;

  Geo? geo;
  Geo? geoPrev;

  final List<TimestampDouble> gForceRecord = [];
  List<Geo> recordGeo = [];
  List<LatLng> flightTrace = [];
  DateTime? takeOff;
  DateTime? landing;
  Geo? launchGeo;
  DateTime? lastSavedLog;
  List<FuelReport> fuelReports = [];

  // in-flight hysterisis
  int triggerHyst = 0;
  bool _inFlight = false;
  StreamController<FlightEvent> flightEvent = StreamController<FlightEvent>();
  StreamSubscription? _flightEventListener;

  /// Latest Barometric Reading
  BarometerEvent? baro;

  /// Live vario (smoothed)
  ValueNotifier<double> varioSmooth = ValueNotifier(0);

  /// Live speed (smoothed)
  ValueNotifier<double> speedSmooth = ValueNotifier(0);

  /// Microseconds since last sensor reading
  int gForcePrevTimestamp = 0;
  double gForceX = 0;
  double gForceY = 0;
  double gForceZ = 0;

  /// Microseconds since last sample of `gForce`
  int gForceCounter = 0;

  /// Ambient barometric reading fetched from web API
  BarometerEvent? baroAmbient;
  bool baroAmbientRequested = false;
  int baroAmbientRequestCount = 0;
  bool baroFromWeatherkit = false;

  /// Ambient Temp in F, according to weatherkit
  double? ambientTemperature;

  StreamSubscription<BarometerEvent>? listenBaro;
  StreamSubscription<AccelerometerEvent>? listenIMU;

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  Stream<Position>? positionStream;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  bool positionStreamStarted = false;

  FakeFlight fakeFlight = FakeFlight();
  Timer? timer;

  FuelStat? _sumFuelStat;
  FuelStat? get sumFuelStat {
    if (_sumFuelStat == null && fuelStats.isNotEmpty) {
      debugPrint("Building sumFuelStats");
      // Only use valid stats.
      final temp = fuelStats.where((e) => e.isValid).toList();
      if (temp.isNotEmpty) {
        _sumFuelStat = temp.reduce((a, b) => a + b);
      } else {
        // No valid stats...
        _sumFuelStat = null;
        // FuelStat(0, Duration.zero, 0, 0, 0, 0, 0, 0);
      }
    }
    return _sumFuelStat;
  }

  List<FuelStat>? _fuelStats = [];
  List<FuelStat> get fuelStats {
    if (_fuelStats == null) {
      _fuelStats = [];

      debugPrint("Building fuelStats");

      // Rebuild the stats
      for (int index = 0; index < fuelReports.length - 1; index++) {
        final a = fuelReports[index];
        final b = fuelReports[index + 1];
        final newStat =
            FuelStat.fromSamples(a, b, recordGeo.sublist(timeToSampleIndex(a.time), timeToSampleIndex(b.time) + 1));
        // this will even include stats that are invalid.
        _fuelStats!.add(newStat);
      }
    }

    return _fuelStats!;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && inFlight) saveFlight();
  }

  @override
  void dispose() {
    timer?.cancel();
    _flightEventListener?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  MyTelemetry() {
    WidgetsBinding.instance.addObserver(this);
    _startBaroService();
    _startIMUService();
  }

  void init() {
    debugPrint("Init /MyTelemetry");

    gForcePrevTimestamp = clock.now().millisecondsSinceEpoch;

    assert(globalContext != null, "globalContext in MyTelemetry instance hasn't been set yet!");

    if (flightEvent.hasListener) {
      flightEvent.close();
      flightEvent = StreamController<FlightEvent>();
    }
    // Initial value of the event stream
    flightEvent.add(FlightEvent(type: FlightEventType.init, time: DateTime.now()));
    _flightEventListener = flightEvent.stream.listen(
      (event) {
        if (event.type == FlightEventType.takeoff) {
          // Add launch waypoints
          Provider.of<ActivePlan>(globalContext!, listen: false).updateWaypoint(Waypoint(
              name: "Launch ${DateFormat("h:mm a").format(event.time)}",
              latlngs: [event.latlng!],
              color: 0xff00df00,
              icon: "takeoff",
              ephemeral: true));
        }
      },
    );

    final activePlan = Provider.of<ActivePlan>(globalContext!, listen: false);
    _setupServiceStatusStream(globalContext!);
    settingsMgr.spoofLocation.listenable.addListener(() {
      if (settingsMgr.spoofLocation.value) {
        if (timer == null) {
          // --- Spoof Location / Disable Baro
          listenBaro?.cancel();
          listenIMU?.cancel();
          if (positionStreamStarted) {
            positionStreamStarted = !positionStreamStarted;
            _toggleListening(globalContext!);
          }
          debugPrint("--- Starting Location Spoofer ---");
          baro = null;

          // if a waypoint is selected, teleport to there first (useful for doing testing)
          final selectedWp = activePlan.getSelectedWp();
          if (selectedWp != null) {
            updateGeo(
                Position(
                  latitude: selectedWp.latlng[0].latitude,
                  longitude: selectedWp.latlng[0].longitude,
                  altitude: geo?.alt ?? 0,
                  speed: 0,
                  timestamp: DateTime.now(),
                  heading: 0,
                  accuracy: 0,
                  speedAccuracy: 0,
                  altitudeAccuracy: 0.0,
                  headingAccuracy: 0.0,
                ),
                bypassRecording: true);
          }

          fakeFlight.initFakeFlight(geo ?? defaultGeo);
          timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
            final targetWp = activePlan.getSelectedWp();
            final target = (targetWp == null || geo == null)
                ? null
                : targetWp.isPath
                    ? geo!
                        .getIntercept(
                          targetWp.latlngOriented,
                        )
                        .latlng
                    : targetWp.latlng[0];
            handleGeoUpdate(globalContext!, fakeFlight.genFakeLocationFlight(target, geoPrev ?? geo ?? defaultGeo),
                bypassRecording: true);
          });
        }
      } else {
        if (timer != null) {
          // --- Real Location / Baro
          _startBaroService();

          if (!positionStreamStarted) {
            positionStreamStarted = !positionStreamStarted;
            _toggleListening(globalContext!);
          }
          _serviceStatusStreamSubscription!.resume();
          debugPrint("--- Stopping Location Spoofer ---");
          timer?.cancel();
          timer = null;
        }
      }
    });

    isInitialized = true;
  }

  void _startBaroService() {
    if (listenBaro != null) {
      listenBaro?.cancel();
      listenBaro = null;
    }
    debugPrint("Starting Barometer Service Stream");
    listenBaro = barometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen((event) {
      // Handle barometer changes (run the vario)
      final baroPrev = baro;
      baro = BarometerEvent(event.pressure + settingsMgr.barometerOffset.value, event.timestamp);
      double vario = 0;
      if (baroPrev != null && baroPrev.timestamp.isBefore(baro!.timestamp)) {
        vario = (altFromBaro(baro!.pressure, baroAmbient?.pressure) -
                altFromBaro(baroPrev.pressure, baroAmbient?.pressure)) /
            (baro!.timestamp.difference(baroPrev.timestamp)).inMilliseconds *
            1000;
        if (vario.isFinite) {
          varioSmooth.value = varioSmooth.value * 0.8 + vario * 0.2;
        } else {
          varioSmooth.value = 0;
        }
      }
    }, onError: (error) {
      // Handle barometer errors
      listenBaro?.cancel();
      listenBaro = null;
      dd.error("Barometer Service Stream Error", errorMessage: error.toString());
    });
  }

  void _startIMUService() {
    if (listenIMU != null) {
      listenIMU?.cancel();
      listenIMU = null;
    }
    listenIMU = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 10)).listen((event) {
      // Microsecond interval since last sample
      // On android (Samsung S21) this was measured at 9602us. Configuring API to slow it down had no effect.
      // final interval = event.timestamp.microsecondsSinceEpoch - gForcePrevTimestamp;

      // Accumulate IMU readings.
      gForceX += event.x;
      gForceY += event.y;
      gForceZ += event.z;
      gForceCounter += 1;

      // To save battery, we will only run heavy calculations every so often.
      if (event.timestamp.millisecondsSinceEpoch > gForcePrevTimestamp + 100) {
        // Average the accumulated readings and take normal vector.s
        double magnitude =
            sqrt(pow(gForceX / gForceCounter, 2) + pow(gForceY / gForceCounter, 2) + pow(gForceZ / gForceCounter, 2)) /
                9.8066;
        gForceRecord.add(TimestampDouble(event.timestamp.millisecondsSinceEpoch, magnitude));

        // mark timer and reset for next couple samples
        gForcePrevTimestamp = event.timestamp.millisecondsSinceEpoch;
        gForceCounter = 0;
        gForceX = 0;
        gForceY = 0;
        gForceZ = 0;
      }
    });
  }

  void _setupServiceStatusStream(BuildContext context) {
    debugPrint("Toggle Location Service Stream");
    if (_serviceStatusStreamSubscription == null) {
      final serviceStatusStream = _geolocatorPlatform.getServiceStatusStream();
      _serviceStatusStreamSubscription = serviceStatusStream.handleError((error) {
        _serviceStatusStreamSubscription?.cancel();
        _serviceStatusStreamSubscription = null;
      }).listen((serviceStatus) {
        if (serviceStatus == ServiceStatus.enabled) {
          if (positionStreamStarted) {
            if (context.mounted) {
              _toggleListening(context);
            }
          }
          if (defaultTargetPlatform == TargetPlatform.iOS && !positionStreamStarted) {
            positionStreamStarted = true;
            if (context.mounted) {
              _toggleListening(context);
            }
          }
          debugPrint("Location Service Enabled");
        } else {
          if (_positionStreamSubscription != null) {
            _positionStreamSubscription?.cancel();
            _positionStreamSubscription = null;
            debugPrint('Position Stream has been canceled');
          }
          debugPrint("Location Service Disabled");
        }
      });

      // Initial start of the position stream
      if (!positionStreamStarted && defaultTargetPlatform == TargetPlatform.android) {
        positionStreamStarted = true;
        _toggleListening(context);
      }
    }
  }

  void _toggleListening(BuildContext context) {
    debugPrint("Toggle Location Listening");
    if (_positionStreamSubscription == null) {
      late LocationSettings locationSettings;

      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            forceLocationManager: false,
            intervalDuration: Duration(milliseconds: settingsMgr.gpsUpdateInterval.value),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationText: "Still sending your position to the group.",
                notificationTitle: "xcNav",
                setOngoing: true,
                enableWakeLock: true));
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.best,
          // activityType: ActivityType.fitness,
          distanceFilter: 0,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        );
      }

      positionStream = _geolocatorPlatform.getPositionStream(locationSettings: locationSettings);
    }

    if (_positionStreamSubscription == null) {
      _positionStreamSubscription = positionStream!.handleError((error) {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
      }).listen((position) {
        if (context.mounted) {
          handleGeoUpdate(context, position);
        }
      });

      debugPrint('Listening for position updates RESUMED');
    } else {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      debugPrint('Listening for position updates PAUSED');
    }
  }

  /// Do all the things with a GPS update
  void handleGeoUpdate(BuildContext context, Position position, {bool bypassRecording = false}) {
    final client = Provider.of<Client>(context, listen: false);
    final group = Provider.of<Group>(context, listen: false);
    final adsb = Provider.of<ADSB>(context, listen: false);

    // debugPrint("geoUpdate (${position.timestamp}): ${position.altitude}, ${position.latitude} x ${position.longitude}");

    if (position.latitude != 0.0 || position.longitude != 0.0) {
      updateGeo(position, bypassRecording: settingsMgr.groundMode.value || bypassRecording);

      if (geo != null) {
        if (!settingsMgr.groundMode.value || settingsMgr.groundModeTelem.value) {
          // Telemetry enabled
          if ((group.activePilots.isEmpty && client.telemetrySkips < 10) ||
              (group.activePilots.length > 20 && client.telemetrySkips < (group.activePilots.length - 20) * 2)) {
            // This message skipped
            client.telemetrySkips++;
          } else {
            // Sending telemetry
            client.sendTelemetry(geo!);
            client.telemetrySkips = 0;
          }
        }

        if (inFlight && geo!.spd > 1) {
          Provider.of<Wind>(context, listen: false)
              .handleVector(Vector(geo!.hdg, geo!.spd, timestamp: position.timestamp));
        }

        // Update ADSB
        adsb.refresh(geo!, inFlight);

        if (inFlight) {
          audioCueService.cueMyTelemetry(geo!);
          audioCueService.cueNextWaypoint(geo!, speedSmooth.value);
          audioCueService.cueGroupAwareness(geo!);
          audioCueService.cueFuel(sumFuelStat, fuelReports.lastOrNull);
        }
      }
    }
  }

  bool get inFlight => _inFlight;
  void startFlight() {
    if (!_inFlight && geo != null) {
      debugPrint("Flight started");
      _inFlight = true;

      // scan backwards to find sample 30 seconds back
      int launchIndex = recordGeo.length - 1;
      while (launchIndex > 0 &&
          recordGeo[launchIndex].time >
              DateTime.now().millisecondsSinceEpoch - const Duration(seconds: 30).inMilliseconds) {
        launchIndex--;
      }

      launchGeo = recordGeo[launchIndex];

      takeOff = DateTime.fromMillisecondsSinceEpoch(launchGeo!.time);
      landing = null;
      debugPrint("In Flight!!!  Launchindex: $launchIndex / ${recordGeo.length}");

      flightEvent.add(FlightEvent(
          type: FlightEventType.takeoff, time: DateTime.fromMillisecondsSinceEpoch(geo!.time), latlng: geo!.latlng));

      if (fuelReports.isNotEmpty) {
        // Duplicate the latest fuel report so it's part of this log, and drop everything else.
        // We assume we weren't just in flight, so we don't account for burn since last report.
        final latest = fuelReports.last;
        fuelReports.clear();
        insertFuelReport(takeOff!, latest.amount, tolerance: Duration.zero);
      }

      // trim the log
      recordGeo.removeRange(0, launchIndex);

      // trim g-force log
      gForceRecord.removeWhere((a) => a.time < launchGeo!.time);

      notifyListeners();
    }
  }

  void stopFlight({bypassRecording = false}) {
    if (_inFlight && geo != null) {
      _inFlight = false;
      debugPrint("Flight Ended");
      landing = DateTime.fromMillisecondsSinceEpoch(recordGeo.last.time);

      // Insert new fuel report extrapolated down (if stats were available)
      if (sumFuelStat != null && fuelReports.isNotEmpty) {
        insertFuelReport(landing!, sumFuelStat!.extrapolateToTime(fuelReports.last, landing!));
      }

      flightEvent.add(FlightEvent(
          type: FlightEventType.land, time: DateTime.fromMillisecondsSinceEpoch(geo!.time), latlng: geo!.latlng));
      // Save current flight to log
      if (!bypassRecording) {
        saveFlight();
      }

      notifyListeners();
    }
  }

  Future saveFlight() async {
    if (recordGeo.length > 10) {
      final log = FlightLog(
          timezone: DateTime.now().timeZoneOffset.inHours,
          samples: recordGeo.toList(),
          // Note: gForce samples smoothed and simplified during time of save
          gForceSamples: douglasPeuckerTimestamped(gaussianFilterTimestamped(gForceRecord, 1, 3).toList(), 0.02),
          waypoints: globalContext != null
              ? Provider.of<ActivePlan>(globalContext!, listen: false)
                  .waypoints
                  .values
                  .where((element) => (!element.ephemeral && element.validate()))
                  .toList()
              : [],
          fuelReports: fuelReports,
          gear: Provider.of<Profile>(globalContext!, listen: false).gear);
      Map<String, dynamic> deviceLogs = {
        "ble_devices": {"xc170": bleDeviceXc170.toJson()}
      };
      log.save(additionalJson: deviceLogs);
      lastSavedLog = clock.now();
    }
  }

  /// Find the nearest sample index
  int timeToSampleIndex(DateTime time) {
    return nearestIndex(recordGeo.map((e) => e.time).toList(), time.millisecondsSinceEpoch);
  }

  /// Find overlapping fuel report.
  /// If the time is close to two reports, the earlier index will be returned.
  /// Null is returned if no matches within tolerance are found.
  int? findFuelReportIndex(DateTime time, {Duration tolerance = const Duration(minutes: 5)}) {
    final index =
        bisect_left<int>(fuelReports.map((e) => e.time.millisecondsSinceEpoch).toList(), time.millisecondsSinceEpoch);
    if (index > 0 && fuelReports[index - 1].time.difference(time).abs().compareTo(tolerance) < 1) {
      return index - 1;
    } else if (index < fuelReports.length && fuelReports[index].time.difference(time).abs().compareTo(tolerance) < 1) {
      return index;
    } else {
      return null;
    }
  }

  /// Insert a fuel report into the sorted list.
  /// If the new report is within tolerance of another report, it will be replaced.
  void insertFuelReport(DateTime time, double? amount, {Duration tolerance = const Duration(minutes: 5)}) {
    final overwriteIndex = findFuelReportIndex(time, tolerance: tolerance);

    if (overwriteIndex != null) {
      if (amount != null) {
        // edit existing
        fuelReports[overwriteIndex] = FuelReport(fuelReports[overwriteIndex].time, amount);
      } else {
        // remove existing
        fuelReports.removeAt(overwriteIndex);
      }
    } else {
      if (amount != null) {
        // Insert new
        final insertIndex = bisect_left<int>(
            fuelReports.map((e) => e.time.millisecondsSinceEpoch).toList(), time.millisecondsSinceEpoch);
        fuelReports.insert(insertIndex, FuelReport(time, amount));
      }
    }

    // reset internal calculations
    _fuelStats = null;
    _sumFuelStat = null;
  }

  void snapBarometerTo(BarometerSrc src, {LatLng? latlng}) {
    switch (src) {
      case BarometerSrc.weatherkit:
        if (latlng != null) {
          fetchAmbPressure(latlng);
        }

      case BarometerSrc.snapToGround:
        debugPrint("Snapping ambient pressure to ground.");
        baroAmbient =
            BarometerEvent(ambientFromAlt(geo!.ground ?? geo?.altGps ?? 0, baro?.pressure ?? 1013.25), clock.now());
        break;
      case BarometerSrc.gpsAlt:
        debugPrint("Snapping ambient pressure to gps altitude. ${geo?.altGps}");
        baroAmbient = BarometerEvent(ambientFromAlt(geo?.altGps ?? 0, baro?.pressure ?? 1013.25), clock.now());
    }
  }

  void fetchAmbPressure(LatLng latlng, {force = false}) async {
    // First check if we've recently
    if (!force) {
      final prefs = await SharedPreferences.getInstance();
      final lastTime = prefs.getInt("weatherKit.last.time");
      if (lastTime != null &&
          clock.now().difference(DateTime.fromMillisecondsSinceEpoch(lastTime)) < const Duration(minutes: 10)) {
        final lastLat = prefs.getDouble("weatherKit.last.lat");
        final lastLng = prefs.getDouble("weatherKit.last.lng");
        if (lastLng != null && lastLat != null) {
          if (latlngCalc.distance(LatLng(lastLat, lastLng), latlng) < 1000) {
            // Recent query available!
            final lastValue = prefs.getDouble("weatherKit.last.value");
            if (lastValue != null) {
              baroAmbient = BarometerEvent(lastValue, clock.now());
              debugPrint("Baro pulled from memory. Skipped weatherKit call.");
              return;
            }
          }
        }
      }
    }

    try {
      if (!baroAmbientRequested) {
        baroAmbientRequested = true;
        http.get(
            Uri.parse(
                "https://weatherkit.apple.com/api/v1/weather/en_US/${latlng.latitude.toStringAsFixed(5)}/${latlng.longitude.toStringAsFixed(5)}?dataSets=currentWeather"),
            headers: {"Authorization": "Bearer $weatherkitToken"}).then((response) {
          if (response.statusCode != 200) {
            baroAmbientRequestCount++;
            // throw "Failed to reach weatherkit resource! (attempt $baroAmbientRequestCount) ${response.statusCode} : ${response.body}";
          } else {
            final payload = jsonDecode(response.body);
            baroAmbient = BarometerEvent(payload["currentWeather"]["pressure"], clock.now());
            ambientTemperature = payload["currentWeather"]["temperature"] * 9 / 5 + 32;
            debugPrint("Ambient pressure found: ${baroAmbient?.pressure} ( ${ambientTemperature}F )");
            baroFromWeatherkit = true;
            baroAmbientRequestCount = 0;

            // Save for later
            SharedPreferences.getInstance().then((prefs) {
              prefs.setInt("weatherKit.last.time", clock.now().millisecondsSinceEpoch);
              prefs.setDouble("weatherKit.last.lat", latlng.latitude);
              prefs.setDouble("weatherKit.last.lng", latlng.longitude);
              prefs.setDouble("weatherKit.last.value", baroAmbient!.pressure);
            });
          }
          baroAmbientRequested = false;
        });
      }
    } catch (err, trace) {
      error("WeatherKit",
          errorMessage: err.toString(),
          errorStackTrace: trace,
          attributes: {"lat": latlng.latitude.toStringAsFixed(5), "lng": latlng.longitude.toStringAsFixed(5)});
    }
  }

  void updateGeo(Position position, {bool bypassRecording = false}) async {
    geoPrev = geo;
    geo = Geo.fromPosition(position, geoPrev, baro, baroAmbient, useGpsAltitude: settingsMgr.useGpsAltitude.value);

    // Preserve previous ground elevation to avoid AGL spinner while new DEM data loads
    if (geoPrev?.ground != null) {
      geo!.ground = geoPrev!.ground;
    }

    if (baro == null || settingsMgr.useGpsAltitude.value) {
      // Use GPS-based vario when barometer unavailable or GPS-only mode enabled
      if (geoPrev != null) {
        final vario = (geo!.alt - geoPrev!.alt) / (geo!.time - geoPrev!.time) * 1000;
        if (vario.isFinite) {
          varioSmooth.value = varioSmooth.value * 0.8 + vario * 0.2;
        } else {
          varioSmooth.value = 0;
        }
      }
    }

    speedSmooth.value = speedSmooth.value * 0.8 + geo!.spd * 0.2;

    await sampleDem(geo!.latlng, true).then((value) {
      if (value != null) {
        geo!.ground = value;
      }
    }).timeout(const Duration(milliseconds: 1000), onTimeout: () {
      warn("DEM service timeout", attributes: {"lat": geo!.lat, "lng": geo!.lng});
    });

    recordGeo.add(geo!);

    // fetch ambient baro from weather service
    if (baroAmbient == null && baroAmbientRequestCount < 10) {
      snapBarometerTo(settingsMgr.ambientPressureSource.value, latlng: geo?.latlng);
    }

    // --- In-Flight detector
    if (globalContext != null && settingsMgr.autoRecordFlight.value) {
      if (inFlight) {
        // Is moving slowly near the ground?
        if (speedSmooth.value < 2.5 && varioSmooth.value.abs() < 0.2 && (geo!.alt - (geo!.ground ?? geo!.alt)) < 30) {
          if (geoPrev != null) {
            triggerHyst += geo!.time - geoPrev!.time;
          } else {
            triggerHyst += const Duration(seconds: 1).inMilliseconds;
          }
        } else {
          triggerHyst = 0;
        }
        if (triggerHyst > 60000) {
          // Landed!
          stopFlight(bypassRecording: bypassRecording);
        }
      } else {
        // Is moving a normal speed and above the ground?
        if (4.0 < geo!.spd && geo!.spd < 25 && geo!.alt - (geo!.ground ?? 0) > 30) {
          if (geoPrev != null) {
            triggerHyst += geo!.time - geoPrev!.time;
          } else {
            triggerHyst += const Duration(seconds: 1).inMilliseconds;
          }
        } else {
          triggerHyst = 0;
        }
        if (triggerHyst > 30000) {
          // Launched!
          startFlight();
        }
      }
    }

    if (inFlight) {
      // --- Record path
      if (flightTrace.isEmpty || (flightTrace.isNotEmpty && latlngCalc.distance(flightTrace.last, geo!.latlng) > 50)) {
        flightTrace.add(geo!.latlng);
        // --- keep list from bloating
        if (flightTrace.length > 10000) {
          flightTrace.removeRange(0, 100);
        }
      }

      // --- Periodically save log
      if (!bypassRecording &&
          (lastSavedLog == null || lastSavedLog!.add(const Duration(minutes: 2)).isBefore(DateTime.now()))) {
        saveFlight();
      }
    }

    notifyListeners();
  }

  Polyline buildFlightTrace() {
    return Polyline(
        points: flightTrace,
        strokeWidth: 4,
        color: const Color.fromARGB(150, 255, 50, 50),
        pattern: const StrokePattern.dotted());
  }

  List<Geo> getHistory(DateTime oldest, {Duration? interval}) {
    final bisectIndex = bisect_left<Geo>(
      recordGeo,
      Geo(timestamp: oldest.millisecondsSinceEpoch),
      compare: (a, b) => a.time - b.time,
    );

    if (interval == null) {
      return recordGeo.sublist(bisectIndex);
    } else {
      final int desiredCardinality = max(
          1,
          ((recordGeo.last.time - max(recordGeo.first.time, oldest.millisecondsSinceEpoch)) / interval.inMilliseconds)
              .ceil());
      final startingCard = recordGeo.length - bisectIndex;
      // debugPrint("recordGeo sample ratio: 1:${(startingCard / desiredCardinality).round()} (desired $desiredCardinality)");
      List<Geo> retval = [];
      for (int index = bisectIndex; index < recordGeo.length; index += (startingCard / desiredCardinality).round()) {
        retval.add(recordGeo[index]);
      }
      // Add end-cap if missing
      if (retval.last.time != recordGeo.last.time) retval.add(recordGeo.last);
      return retval;
    }
  }
}
