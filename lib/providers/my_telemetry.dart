import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bisection/bisect.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_barometer/flutter_barometer.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/fake_path.dart';

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/secrets.dart';
import 'package:xcnav/units.dart';

enum FlightEventType { init, takeoff, land }

/// Meters
double densityAlt(BarometerValue ambientPressure, double ambientTemp) {
  return 145442.16 * (1 - pow(17.326 * ambientPressure.inchOfMercury / (459.67 + ambientTemp), 0.235)) / meters2Feet;
}

class FlightEvent {
  final FlightEventType type;
  final DateTime time;
  final LatLng? latlng;
  FlightEvent({required this.type, required this.time, this.latlng});
}

class MyTelemetry with ChangeNotifier, WidgetsBindingObserver {
  Geo geo = Geo();

  BuildContext? globalContext;

  // NOTE: fuel feature disabled for now

  /// Liters
  // double fuel = 0;

  /// Liter/Hour
  // double fuelBurnRate = 4;

  /// fuel save interval
  // double? lastSavedFuelLevel;

  Geo geoPrev = Geo();

  List<Geo> recordGeo = [];
  List<LatLng> flightTrace = [];
  DateTime? takeOff;
  Geo? launchGeo;
  DateTime? lastSavedLog;

  // in-flight hysterisis
  int triggerHyst = 0;
  bool _inFlight = false;
  StreamController<FlightEvent> flightEvent = StreamController<FlightEvent>();
  StreamSubscription? _flightEventListener;

  /// Latest Barometric Reading
  BarometerValue? baro;

  /// Ambient barometric reading fetched from web API
  BarometerValue? baroAmbient;
  bool baroAmbientRequested = false;
  int baroAmbientRequestCount = 0;
  bool baroFromWeatherkit = false;

  /// Ambient Temp in F, according to weatherkit
  double? ambientTemperature;

  StreamSubscription<BarometerValue>? listenBaro;

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  Stream<Position>? positionStream;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  bool positionStreamStarted = false;

  FakeFlight fakeFlight = FakeFlight();
  Timer? timer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached && inFlight) saveFlight();
  }

  @override
  void dispose() {
    //  NOTE: fuel feature disabled for now
    // _save();
    timer?.cancel();
    _flightEventListener?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  MyTelemetry() {
    // NOTE: fuel feature disabled for now
    // _load();
    WidgetsBinding.instance.addObserver(this);

    _startBaroService();
  }

  void init() {
    debugPrint("Build /MyTelemetry");

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

    final settings = Provider.of<Settings>(globalContext!, listen: false);
    final activePlan = Provider.of<ActivePlan>(globalContext!, listen: false);
    _setupServiceStatusStream(globalContext!);
    settings.addListener(() {
      if (settings.spoofLocation) {
        if (timer == null) {
          // --- Spoof Location / Disable Baro
          listenBaro?.cancel();
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
                  altitude: geo.alt,
                  speed: 0,
                  timestamp: DateTime.now(),
                  heading: 0,
                  accuracy: 0,
                  speedAccuracy: 0,
                ),
                bypassRecording: true);
          }

          fakeFlight.initFakeFlight(geo);
          timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
            final targetWp = activePlan.getSelectedWp();
            final target = targetWp == null
                ? null
                : targetWp.latlng.length > 1
                    ? geo
                        .getIntercept(
                          targetWp.latlngOriented,
                        )
                        .latlng
                    : targetWp.latlng[0];
            handleGeoUpdate(globalContext!, fakeFlight.genFakeLocationFlight(target, geoPrev), bypassRecording: true);
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
  }

  void _startBaroService() {
    listenBaro = FlutterBarometer.currentPressureEvent.listen((event) {
      baro = event;
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
            _toggleListening(context);
          }
          if (defaultTargetPlatform == TargetPlatform.iOS && !positionStreamStarted) {
            positionStreamStarted = true;
            _toggleListening(context);
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
            intervalDuration: const Duration(seconds: 3),
            //(Optional) Set foreground notification config to keep the app alive
            //when going to the background
            foregroundNotificationConfig: const ForegroundNotificationConfig(
                notificationText: "Still sending your position to the group.",
                notificationTitle: "xcNav",
                enableWakeLock: true));
      } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.best,
          // activityType: ActivityType.fitness,
          distanceFilter: 0,
          pauseLocationUpdatesAutomatically: false,
          // Only set to true if our app will be started up in the background.
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
      }).listen((position) => {handleGeoUpdate(context, position)});

      debugPrint('Listening for position updates RESUMED');
    } else {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      debugPrint('Listening for position updates PAUSED');
    }
  }

  /// Do all the things with a GPS update
  void handleGeoUpdate(BuildContext context, Position position, {bool bypassRecording = false}) {
    final settings = Provider.of<Settings>(context, listen: false);
    final client = Provider.of<Client>(context, listen: false);
    final group = Provider.of<Group>(context, listen: false);
    final adsb = Provider.of<ADSB>(context, listen: false);

    // debugPrint("geoUpdate (${position.timestamp}): ${position.altitude}, ${position.latitude} x ${position.longitude}");

    if (position.latitude != 0.0 || position.longitude != 0.0) {
      updateGeo(position, bypassRecording: settings.groundMode || bypassRecording);
    }

    if (!settings.groundMode || settings.groundModeTelemetry) {
      if (group.activePilots.isNotEmpty || client.telemetrySkips > 20) {
        client.sendTelemetry(geo);
        client.telemetrySkips = 0;
      } else {
        client.telemetrySkips++;
      }
    }

    if (inFlight && geo.spd > 1) {
      Provider.of<Wind>(context, listen: false).handleVector(Vector(geo.hdg, geo.spd, timestamp: position.timestamp));
    }

    // Update ADSB
    adsb.refresh(geo, inFlight);

    if (inFlight) {
      audioCueService.cueMyTelemetry(geo);
      audioCueService.cueNextWaypoint(geo);
      audioCueService.cueGroupAwareness(geo);
    }
  }

  // void _load() async {
  //   final prefs = await SharedPreferences.getInstance();
  //   fuel = prefs.getDouble("me.fuel") ?? 0;
  //   lastSavedFuelLevel = fuel;
  //   fuelBurnRate = prefs.getDouble("me.fuelBurnRate") ?? 4;
  // }

  // void _save() async {
  //   debugPrint("Fuel Level Saved");
  //   final prefs = await SharedPreferences.getInstance();
  //   prefs.setDouble("me.fuel", fuel);
  //   prefs.setDouble("me.fuelBurnRate", fuelBurnRate);
  //   lastSavedFuelLevel = fuel;
  // }

  bool get inFlight => _inFlight;

  void startFlight() {
    if (!_inFlight) {
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
      debugPrint("In Flight!!!  Launchindex: $launchIndex / ${recordGeo.length}");

      flightEvent.add(FlightEvent(
          type: FlightEventType.takeoff, time: DateTime.fromMillisecondsSinceEpoch(geo.time), latlng: geo.latlng));

      // clear the log
      recordGeo.removeRange(0, launchIndex);

      notifyListeners();
    }
  }

  void stopFlight({bypassRecording = false}) {
    if (_inFlight) {
      _inFlight = false;
      debugPrint("Flight Ended");
      flightEvent.add(FlightEvent(
          type: FlightEventType.land, time: DateTime.fromMillisecondsSinceEpoch(geo.time), latlng: geo.latlng));
      // Save current flight to log
      if (!bypassRecording) {
        saveFlight();
      }

      notifyListeners();
    }
  }

  Future saveFlight() async {
    if (recordGeo.length > 10) {
      lastSavedLog = DateTime.now();
      Directory tempDir = await getApplicationDocumentsDirectory();
      File logFile = File("${tempDir.path}/flight_logs/${recordGeo[0].time}.json");
      debugPrint("Writing ${logFile.uri} with ${recordGeo.length} samples");
      await logFile.create(recursive: true).then((value) => logFile.writeAsString(jsonEncode({
            "samples": recordGeo.map((e) => e.toJson()).toList(),
            "waypoints": globalContext != null
                ? Provider.of<ActivePlan>(globalContext!, listen: false)
                    .waypoints
                    .values
                    .where((element) => (!element.ephemeral && element.validate()))
                    .map((e) => e.toJson())
                    .toList()
                : []
          })));
    }
  }

  void fetchAmbPressure() {
    if (!baroAmbientRequested) {
      baroAmbientRequested = true;
      http.get(
          Uri.parse(
              "https://weatherkit.apple.com/api/v1/weather/en_US/${geo.lat.toStringAsFixed(5)}/${geo.lng.toStringAsFixed(5)}?dataSets=currentWeather"),
          headers: {"Authorization": "Bearer $weatherkitToken"}).then((response) {
        if (response.statusCode != 200) {
          baroAmbientRequestCount++;
          debugPrint(
              "Failed to reach weatherkit resource! (attempt $baroAmbientRequestCount) ${response.statusCode} : ${response.body}");
        } else {
          final payload = jsonDecode(response.body);
          baroAmbient = BarometerValue(payload["currentWeather"]["pressure"]);
          ambientTemperature = payload["currentWeather"]["temperature"] * 9 / 5 + 32;
          debugPrint("Ambient pressure found: ${baroAmbient?.hectpascal} ( ${ambientTemperature}F )");
          baroFromWeatherkit = true;
        }
        baroAmbientRequested = false;
      });
    }
  }

  void updateGeo(Position position, {bool bypassRecording = false}) async {
    // debugPrint("${location.elapsedRealtimeNanos}) ${location.latitude}, ${location.longitude}, ${location.altitude}");
    geoPrev = geo;
    geo = Geo.fromPosition(position, geoPrev, baro, baroAmbient);
    geo.prevGnd = geoPrev.ground;
    await sampleDem(geo.latlng, true).then((value) {
      if (value != null) {
        geo.ground = value;
      }
    }).timeout(const Duration(milliseconds: 500), onTimeout: () {
      debugPrint("DEM SERVICE TIMEOUT! ${geo.latlng}");
    });

    recordGeo.add(geo);

    // fetch ambient baro from weather service
    if (baroAmbient == null && baroAmbientRequestCount < 10) {
      try {
        fetchAmbPressure();
      } catch (e) {
        debugPrint("Failed to fetch ambient pressure... $e");
      }
    }

    // --- In-Flight detector
    if (globalContext != null && Provider.of<Settings>(globalContext!, listen: false).autoStartStopFlight) {
      if (inFlight) {
        // Is moving slowly near the ground?
        if (geo.spdSmooth < 3.0 && geo.varioSmooth.abs() < 1.0 && geo.alt - (geo.ground ?? geo.alt) < 30) {
          triggerHyst += geo.time - geoPrev.time;
        } else {
          triggerHyst = 0;
        }
        if (triggerHyst > 60000) {
          // Landed!
          stopFlight(bypassRecording: bypassRecording);
        }
      } else {
        // Is moving a normal speed and above the ground?
        if (4.0 < geo.spd && geo.spd < 25 && geo.alt - (geo.ground ?? 0) > 30) {
          triggerHyst += geo.time - geoPrev.time;
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
      // --- burn fuel
      // NOTE: fuel feature disabled for now
      // fuel = max(0, fuel - fuelBurnRate * (geo.time - geoPrev.time) / 3600000.0);

      // --- Record path
      if (flightTrace.isEmpty || (flightTrace.isNotEmpty && latlngCalc.distance(flightTrace.last, geo.latlng) > 50)) {
        flightTrace.add(geo.latlng);
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

  // void updateFuel(double delta) {
  //   fuel = max(0, fuel + delta);
  //   // every so often, save the fuel level in case the app crashes
  //   if ((fuel - (lastSavedFuelLevel ?? fuel)).abs() > 0.2) _save();
  //   notifyListeners();
  // }

  // void updateFuelBurnRate(double delta) {
  //   fuelBurnRate = max(0.1, fuelBurnRate + delta);
  //   _save();
  //   notifyListeners();
  // }

  // Color fuelIndicatorColor(ETA next, ETA trip) {
  //   double fuelTime = fuel / fuelBurnRate;
  //   if (fuelTime > 0.0001 && inFlight && next.time != null) {
  //     if (fuelTime < 0.25 || (fuelTime < next.time!.inMilliseconds.toDouble() / 3600000)) {
  //       // Red at 15minutes of fuel left or can't make selected waypoint
  //       return Colors.red.shade900;
  //     } else if (fuelTime < trip.time!.inMilliseconds.toDouble() / 3600000) {
  //       // Orange if not enough fuel to finish the plan
  //       return Colors.amber.shade900;
  //     }
  //   }
  //   return Colors.grey.shade900;
  // }

  // NOTE: fuel feature disabled for now
  // Duration get fuelTimeRemaining => Duration(milliseconds: ((fuel / fuelBurnRate) * 3600000).ceil());

  Polyline buildFlightTrace() {
    return Polyline(points: flightTrace, strokeWidth: 4, color: const Color.fromARGB(150, 255, 50, 50), isDotted: true);
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
