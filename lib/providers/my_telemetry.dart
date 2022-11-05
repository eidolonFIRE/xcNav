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
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/fake_path.dart';

// --- Models
import 'package:xcnav/models/eta.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/providers/wind.dart';

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
    _save();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  MyTelemetry() {
    _load();
    WidgetsBinding.instance.addObserver(this);

    _startBaroService();
  }

  void init(BuildContext context) {
    debugPrint("Build /MyTelemetry PROVIDER");

    // --- Location Spoofer for debugging

    final client = Provider.of<Client>(context, listen: false);
    final settings = Provider.of<Settings>(context, listen: false);
    final activePlan = Provider.of<ActivePlan>(context, listen: false);

    addListener((() {
      if (!settings.groundMode || settings.groundModeTelemetry) {
        if (Provider.of<Group>(context, listen: false).pilots.isNotEmpty || client.telemetrySkips > 20) {
          client.sendTelemetry(geo, fuel);
          client.telemetrySkips = 0;
        } else {
          client.telemetrySkips++;
        }
      }

      // Update ADSB
      Provider.of<ADSB>(context, listen: false).refresh(geo);

      audioCueService.cueMyTelemetry(geo);
      audioCueService.cueNextWaypoint(geo);
      audioCueService.cueGroupAwareness(geo);
      // audioCueService.cueFuel(geo, fuel, fuelTimeRemaining);
    }));

    _setupServiceStatusStream(context);
    settings.addListener(() {
      if (settings.spoofLocation) {
        if (timer == null) {
          // --- Spoof Location / Disable Baro
          listenBaro?.cancel();
          if (positionStreamStarted) {
            positionStreamStarted = !positionStreamStarted;
            _toggleListening(context);
          }
          debugPrint("--- Starting Location Spoofer ---");
          baro = null;

          // if a waypoint is selected, teleport to there first (useful for doing testing)
          if (activePlan.selectedWp != null) {
            updateGeo(
                Position(
                  latitude: activePlan.selectedWp!.latlng[0].latitude,
                  longitude: activePlan.selectedWp!.latlng[0].longitude,
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
            final target = activePlan.selectedWp == null
                ? null
                : activePlan.selectedWp!.latlng.length > 1
                    ? geo.nearestPointOnPath(activePlan.selectedWp!.latlng, false).latlng
                    : activePlan.selectedWp!.latlng[0];
            handleGeomUpdate(context, fakeFlight.genFakeLocationFlight(target, geoPrev));
          });
        }
      } else {
        if (timer != null) {
          // --- Real Location / Baro

          _startBaroService();

          if (!positionStreamStarted) {
            positionStreamStarted = !positionStreamStarted;
            _toggleListening(context);
          }
          _serviceStatusStreamSubscription!.resume();
          debugPrint("--- Stopping Location Spoofer ---");
          timer?.cancel();
          timer = null;
        }
      }
    });

    addListener(() {
      if (inFlight && geo.spd > 1) {
        Provider.of<Wind>(context, listen: false).handleVector(Vector(geo.hdg, geo.spd));
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
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        );
      }

      positionStream = _geolocatorPlatform.getPositionStream(locationSettings: locationSettings);
    }

    if (_positionStreamSubscription == null) {
      _positionStreamSubscription = positionStream!.handleError((error) {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
      }).listen((position) => {handleGeomUpdate(context, position)});

      debugPrint('Listening for position updates RESUMED');
    } else {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      debugPrint('Listening for position updates PAUSED');
    }
  }

  /// Do all the things with a GPS update
  void handleGeomUpdate(BuildContext context, Position position) {
    final settings = Provider.of<Settings>(context, listen: false);

    if (position.latitude != 0.0 || position.longitude != 0.0) {
      updateGeo(position, bypassRecording: settings.groundMode);
    }
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

  void updateGeo(Position position, {bool bypassRecording = false}) async {
    // debugPrint("${location.elapsedRealtimeNanos}) ${location.latitude}, ${location.longitude}, ${location.altitude}");
    geoPrev = geo;
    geo = Geo.fromPosition(position, geoPrev, baro, baroAmbient);
    geo.prevGnd = geoPrev.ground;
    await sampleDem(geo.latLng, true).then((value) {
      if (value != null) {
        geo.ground = value;
      }
    }).timeout(const Duration(milliseconds: 500), onTimeout: () {
      debugPrint("DEM SERVICE TIMEOUT!");
    });

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
        // TODO: Use real timestamp search here (it's hardcoded to 3seconds)
        final launchIndex = max(0, recordGeo.length - (triggerDuration.inSeconds ~/ 3) - 3);
        launchGeo = recordGeo[launchIndex];

        takeOff = DateTime.fromMillisecondsSinceEpoch(launchGeo!.time);
        debugPrint("In Flight!!!  Launchindex: $launchIndex / ${recordGeo.length}");

        // clear the log
        recordGeo.removeRange(0, launchIndex);
      } else {
        debugPrint("Flight Ended");

        // Save current flight to log
        if (!bypassRecording) {
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
      if (!bypassRecording && lastSavedLog == null ||
          lastSavedLog!.add(const Duration(minutes: 2)).isBefore(DateTime.now())) {
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

  List<Geo> getHistory(DateTime oldest, {Duration? interval}) {
    final bisectIndex = bisect_left<Geo>(
      recordGeo,
      Geo.fromValues(0, 0, 0, oldest.millisecondsSinceEpoch, 0, 0, 0),
      compare: (a, b) => a.time - b.time,
    );

    if (interval == null) {
      return recordGeo.sublist(bisectIndex);
    } else {
      final int desiredCardinality =
          ((recordGeo.last.time - max(recordGeo.first.time, oldest.millisecondsSinceEpoch)) / interval.inMilliseconds)
              .ceil();
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
