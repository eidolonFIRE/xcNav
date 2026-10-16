import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:bisection/bisect.dart';
import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/dem_service.dart';
import 'package:xcnav/douglas_peucker.dart';
import 'package:xcnav/fake_path.dart';
import 'package:xcnav/gaussian_filter.dart';
import 'package:xcnav/log_store.dart';
import 'package:xcnav/models/flight_log.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/datadog.dart' as dd;

// --- Models
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/geoid.dart';
import 'package:xcnav/models/gps_jump_filter.dart';
import 'package:xcnav/models/vector.dart';
import 'package:xcnav/models/waypoint.dart';
import 'package:xcnav/notifications.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/adsb.dart';
import 'package:xcnav/providers/client.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/services/ble_service.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/providers/wind.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/util.dart';

enum FlightEventType { init, takeoff, land }

/// Meters
double densityAlt(BarometerEvent ambientPressure, double ambientTemp) {
  return 145442.16 *
      (1 - pow(17.326 * (ambientPressure.pressure * 0.02953) / (459.67 + ambientTemp), 0.235)) /
      meters2Feet;
}

Geo defaultGeo = Geo(lat: 37, lng: -122);

enum GpsStrength { none, poor, fair, good }

class GpsFixQuality {
  /// Horizontal accuracy (meters)
  final double accuracy;

  /// Local time the fix was received
  final DateTime time;

  GpsFixQuality({required this.accuracy, required this.time});

  /// No fix for this long counts as lost
  static const staleAfter = Duration(seconds: 10);

  GpsStrength get strength {
    if (clock.now().difference(time) > staleAfter) return GpsStrength.none;
    if (accuracy <= 10) return GpsStrength.good;
    if (accuracy <= 30) return GpsStrength.fair;
    return GpsStrength.poor;
  }
}

class FlightEvent {
  final FlightEventType type;
  final DateTime time;
  final LatLng? latlng;
  FlightEvent({required this.type, required this.time, this.latlng});
}

class MyTelemetry with ChangeNotifier, WidgetsBindingObserver {
  BuildContext? globalContext;
  bool isInitialized = false;

  Duration _standbyTimer = Duration.zero;
  bool _inStandby = false;

  Geo? geo;
  Geo? geoPrev;
  final GpsJumpFilter gpsJumpFilter = GpsJumpFilter();

  /// Latest raw GPS fix quality (includes fixes rejected by the jump filter)
  final ValueNotifier<GpsFixQuality?> gpsFix = ValueNotifier(null);

  final List<TimestampValue<double>> gForceRecord = [];
  List<Geo> recordGeo = [];
  List<LatLng> flightTrace = [];
  DateTime? takeOff;
  DateTime? landing;
  Geo? launchGeo;
  DateTime? lastSavedLog;

  /// Most recent log on disk when the app started. A flight launching shortly after it ended continues it.
  FlightLog? resumeCandidate;

  /// Log being continued by the current flight. (Recording was interrupted, likely by an app restart.)
  FlightLog? resumedLog;

  /// Start of the whole flight, including any resumed log.
  DateTime? get flightStart => resumedLog?.startTime ?? takeOff;

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

  /// Ambient barometric pressure
  BarometerEvent? baroAmbient;

  StreamSubscription<BarometerEvent>? listenBaro;
  StreamSubscription<AccelerometerEvent>? listenIMU;

  /// Phone sensors are ignored while an external (BLE) sensor has reported within this window.
  static const externalSensorTimeout = Duration(seconds: 5);
  DateTime? _externalBaroTime;
  DateTime? _externalGpsTime;

  bool get externalBaroActive =>
      _externalBaroTime != null && clock.now().difference(_externalBaroTime!) < externalSensorTimeout;
  bool get externalGpsActive =>
      _externalGpsTime != null && clock.now().difference(_externalGpsTime!) < externalSensorTimeout;

  final GeolocatorPlatform _geolocatorPlatform = GeolocatorPlatform.instance;
  Stream<Position>? positionStream;
  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<ServiceStatus>? _serviceStatusStreamSubscription;
  bool positionStreamStarted = false;

  FakeFlight fakeFlight = FakeFlight();
  Timer? timer;

  FuelReportController fuelReportController = FuelReportController();

  double? get glideSlope {
    if (geo != null) {
      final slope = speedSmooth.value / varioSmooth.value.abs();
      if (slope.isFinite && slope < 50 && slope > 1) {
        return slope;
      }
    }
    return null;
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
  }

  void setStandby(bool inStandby) {
    if (inStandby != _inStandby) {
      debugPrint("/!\\ Set Standby: $inStandby");
      _standbyTimer = Duration.zero;
      _inStandby = inStandby;
      if (_inStandby) {
        listenBaro?.cancel();
        _stopIMUService();
        if (positionStreamStarted) {
          positionStreamStarted = !positionStreamStarted;
          _stopGpsService();
        }
      } else {
        _startBaroService();
        if (_inFlight) _startIMUService();
        if (!positionStreamStarted) {
          positionStreamStarted = !positionStreamStarted;
          _startGpsService(globalContext!);
        }
        _serviceStatusStreamSubscription?.resume();
      }
    }
  }

  void init() {
    debugPrint("Init /MyTelemetry");

    gForcePrevTimestamp = clock.now().millisecondsSinceEpoch;

    assert(globalContext != null, "globalContext in MyTelemetry instance hasn't been set yet!");

    if (flightEvent.hasListener) {
      flightEvent.close();
      flightEvent = StreamController<FlightEvent>();
    }
    // In case we are restarting mid-flight
    logStore.loadMostRecentLog().then((log) => resumeCandidate ??= log);

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

    bleDeviceStodeus.onBaro = (pressure, vario) => handleExternalBaro(pressure, vario: vario);
    bleDeviceStodeus.onPosition = handleExternalPosition;

    // Listen for GPS-only altitude setting changes
    settingsMgr.forceGpsAltitude.listenable.addListener(() {
      _startBaroService(); // This will stop or start the service based on the setting
    });

    settingsMgr.spoofLocation.listenable.addListener(() {
      if (settingsMgr.spoofLocation.value) {
        if (timer == null) {
          // --- Spoof Location / Disable Baro
          setStandby(true);
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
          setStandby(false);
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

    // Don't start barometer service if GPS-only altitude mode is enabled
    if (settingsMgr.forceGpsAltitude.value) {
      debugPrint("Barometer Service disabled (GPS-only mode)");
      return;
    }

    debugPrint("Starting Barometer Service Stream");
    listenBaro = barometerEventStream(samplingPeriod: SensorInterval.normalInterval).listen((event) {
      if (externalBaroActive) return;
      _handleBaro(BarometerEvent(event.pressure, event.timestamp));
    }, onError: (error) {
      // Handle barometer errors
      listenBaro?.cancel();
      listenBaro = null;
      dd.error("Barometer Service Stream Error", errorMessage: error.toString());
    });
  }

  /// Handle barometer changes (run the vario).
  /// [vario] (m/s) is used as-is, without our smoothing, when the sensor provides its own (already smoothed).
  void _handleBaro(BarometerEvent event, {double? vario}) {
    final baroPrev = baro;
    baro = event;
    if (vario != null) {
      varioSmooth.value = vario.isFinite ? vario : 0;
      return;
    }
    if (baroPrev != null && baroPrev.timestamp.isBefore(baro!.timestamp)) {
      final rawVario =
          (altFromBaro(baro!.pressure, baroAmbient?.pressure) - altFromBaro(baroPrev.pressure, baroAmbient?.pressure)) /
              (baro!.timestamp.difference(baroPrev.timestamp)).inMilliseconds *
              1000;
      if (rawVario.isFinite) {
        varioSmooth.value = varioSmooth.value * 0.8 + rawVario * 0.2;
      } else {
        varioSmooth.value = 0;
      }
    }
  }

  /// Pressure (hPa) from an external sensor. Takes priority over the phone barometer.
  void handleExternalBaro(double pressure, {double? vario}) {
    if (_inStandby || settingsMgr.forceGpsAltitude.value) {
      _logExternalIgnored("barometer");
      return;
    }
    if (!externalBaroActive) debugPrint("Using external barometer ($pressure hPa)");
    _externalBaroTime = clock.now();
    _handleBaro(BarometerEvent(pressure, clock.now()), vario: vario);
  }

  DateTime _externalIgnoredLogged = DateTime(0);

  /// Rate limited, since external sensors report up to 10hz.
  void _logExternalIgnored(String sensor) {
    if (clock.now().difference(_externalIgnoredLogged) < externalSensorTimeout) return;
    _externalIgnoredLogged = clock.now();
    debugPrint(
        "Ignoring external $sensor (standby: $_inStandby, forceGpsAltitude: ${settingsMgr.forceGpsAltitude.value}, "
        "has context: ${globalContext?.mounted ?? false})");
  }

  /// Fix from an external GPS. Takes priority over the phone GPS.
  void handleExternalPosition(Position position) {
    if (_inStandby || globalContext == null || !globalContext!.mounted) {
      _logExternalIgnored("GPS");
      return;
    }
    if (!externalGpsActive) debugPrint("Using external GPS (${position.latitude}, ${position.longitude})");
    _externalGpsTime = clock.now();
    handleGeoUpdate(globalContext!, position);
  }

  /// G-force is only recorded in flight, so the IMU only runs in flight to save battery.
  void _startIMUService() {
    _stopIMUService();
    gForcePrevTimestamp = clock.now().millisecondsSinceEpoch;
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
        gForceRecord.add(TimestampValue<double>(event.timestamp.millisecondsSinceEpoch, magnitude));

        // mark timer and reset for next couple samples
        gForcePrevTimestamp = event.timestamp.millisecondsSinceEpoch;
        gForceCounter = 0;
        gForceX = 0;
        gForceY = 0;
        gForceZ = 0;
      }
    });
  }

  void _stopIMUService() {
    listenIMU?.cancel();
    listenIMU = null;
    gForceCounter = 0;
    gForceX = 0;
    gForceY = 0;
    gForceZ = 0;
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
            _stopGpsService();
          }
          if (defaultTargetPlatform == TargetPlatform.iOS && !positionStreamStarted) {
            positionStreamStarted = true;
            if (context.mounted) {
              _startGpsService(context);
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
        _startGpsService(context);
      }
    }
  }

  void _startGpsService(BuildContext context) {
    if (_positionStreamSubscription == null) {
      debugPrint("Start GPS listening");
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
      _positionStreamSubscription = positionStream!.handleError((error) {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
      }).listen((position) {
        if (context.mounted && !externalGpsActive) {
          handleGeoUpdate(
              context, defaultTargetPlatform == TargetPlatform.android ? ellipsoidToMsl(position) : position);
        }
      });

      debugPrint('Listening for position updates RESUMED');
    }
  }

  void _stopGpsService() {
    if (_positionStreamSubscription != null) {
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      debugPrint('Stop GPS listening');
    }
  }

  /// Do all the things with a GPS update
  void handleGeoUpdate(BuildContext context, Position position, {bool bypassRecording = false}) {
    final client = Provider.of<Client>(context, listen: false);
    final group = Provider.of<Group>(context, listen: false);
    final adsb = Provider.of<ADSB>(context, listen: false);

    // debugPrint("geoUpdate (${position.timestamp}): ${position.altitude}, ${position.latitude} x ${position.longitude}");

    // Update standby check
    if (!inFlight && !appInFocus()) {
      if (geo != null) {
        final elapsed = clock.now().difference(DateTime.fromMillisecondsSinceEpoch(geo!.time));
        _standbyTimer += elapsed;
        if (_standbyTimer > Duration(hours: 2)) {
          setStandby(true);
        }
      }
    }

    if (position.latitude != 0.0 || position.longitude != 0.0) {
      final accepted = updateGeo(position, bypassRecording: settingsMgr.groundMode.value || bypassRecording);

      if (accepted && geo != null) {
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
        client.sendAirplanesObserved(adsb, geo!);

        if (inFlight) {
          audioCueService.cueElevationTriggers(geo!);
          audioCueService.cueMyTelemetry(geo!, speedSmoothed: speedSmooth.value);
          audioCueService.cueNextWaypoint(geo!, speedSmooth.value);
          audioCueService.cueGroupAwareness(geo!);
          audioCueService.cueFuel(
              fuelReportController.getSumFuelStat(recordGeo), fuelReportController.fuelReports.lastOrNull);
        }
      }
    }
  }

  bool get inFlight => _inFlight;

  /// Latest fuel level from a connected BLE fuel sensor, if it reported recently.
  double? liveFuelReading({Duration maxAge = const Duration(minutes: 1)}) {
    final cutoff = clock.now().subtract(maxAge).millisecondsSinceEpoch;
    final soc = bleDeviceSp140.telemetry.charge.log.lastOrNull;
    if (soc != null && soc.time >= cutoff) return soc.value.toDouble();
    final fuel = bleDeviceXc170.telemetry.fuel.log.lastOrNull;
    if (fuel != null && fuel.time >= cutoff) return fuel.value;
    return null;
  }

  void startFlight() {
    if (!_inFlight && geo != null) {
      debugPrint("Flight started");
      _inFlight = true;

      // scan backwards to find sample 30 seconds back
      int launchIndex = recordGeo.length - 1;
      while (launchIndex > 0 &&
          recordGeo[launchIndex].time >
              clock.now().millisecondsSinceEpoch - const Duration(seconds: 30).inMilliseconds) {
        launchIndex--;
      }

      launchGeo = recordGeo[launchIndex];

      // Only the first flight since app start can resume. Later ones follow a landing or manual stop.
      resumedLog = takeOff == null && (resumeCandidate?.canResumeAt(launchGeo!) ?? false) ? resumeCandidate : null;
      resumeCandidate = null;
      if (resumedLog != null) {
        debugPrint("Resuming flight log ${resumedLog!.filename}");
      }

      takeOff = DateTime.fromMillisecondsSinceEpoch(launchGeo!.time);
      landing = null;
      debugPrint("In Flight!!!  Launchindex: $launchIndex / ${recordGeo.length}");

      flightEvent.add(FlightEvent(
          type: FlightEventType.takeoff, time: DateTime.fromMillisecondsSinceEpoch(geo!.time), latlng: geo!.latlng));

      final liveFuel = liveFuelReading();
      if (liveFuel != null) {
        // A connected fuel sensor knows better than the last report (tank may have been refilled since landing).
        fuelReportController.clear();
        fuelReportController.insertFuelReport(takeOff!, liveFuel, tolerance: Duration.zero);
      } else if (fuelReportController.fuelReports.isNotEmpty) {
        // Duplicate the latest fuel report so it's part of this log, and drop everything else.
        // We assume we weren't just in flight, so we don't account for burn since last report.
        final latest = fuelReportController.fuelReports.last;
        fuelReportController.clear();
        fuelReportController.insertFuelReport(takeOff!, latest.amount, tolerance: Duration.zero);
      }

      // trim the log
      recordGeo.removeRange(0, launchIndex);

      // trim g-force log
      gForceRecord.removeWhere((a) => a.time < launchGeo!.time);
      _startIMUService();

      notifyListeners();
    }
  }

  void stopFlight({bool bypassRecording = false}) {
    if (_inFlight && geo != null) {
      _inFlight = false;
      debugPrint("Flight Ended");
      _stopIMUService();
      landing = DateTime.fromMillisecondsSinceEpoch(recordGeo.last.time);
      final sumFuelStat = fuelReportController.getSumFuelStat(recordGeo);

      // Insert new fuel report extrapolated down (if stats were available)
      if (bleDeviceSp140.device != null) {
        debugPrint("SP140 is armed, Logging real fuel report.");
        final soc = bleDeviceSp140.telemetry.charge.log.lastOrNull?.value.toDouble();
        if (soc != null) {
          fuelReportController.insertFuelReport(landing!, soc);
        }
      } else if (sumFuelStat != null && fuelReportController.fuelReports.isNotEmpty) {
        fuelReportController.insertFuelReport(
            landing!, sumFuelStat.extrapolateToTime(fuelReportController.fuelReports.last, landing!));
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
          // Offset in effect at launch (handles daylight savings and fractional-hour zones)
          utcOffset: DateTime.fromMillisecondsSinceEpoch(recordGeo.first.time).timeZoneOffset,
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
          fuelReports: fuelReportController.fuelReports,
          gear: Provider.of<Profile>(globalContext!, listen: false).gear);

      if (log.timeRange != null) {
        bleDeviceXc170.trimToRange(log.timeRange!);
        bleDeviceRunleader.trimToRange(log.timeRange!);
        bleDeviceSp140.trimToRange(log.timeRange!);
      }

      Map<String, dynamic> bleDevices = {
        if (bleDeviceXc170.device != null) "xc170": bleDeviceXc170.toJson(),
        if (bleDeviceRunleader.device != null) "runleader": bleDeviceRunleader.toJson(),
        if (bleDeviceSp140.device != null) "sp140": bleDeviceSp140.toJson(),
      };

      if (resumedLog != null) {
        // Write this flight onto the end of the interrupted log
        final merged = FlightLog.merge(resumedLog!, log);
        bleDevices = FlightLog.mergeBleDevicesJson(resumedLog!.bleDevicesJson, jsonDecode(jsonEncode(bleDevices)),
            cutoff: resumedLog!.samples.last.time)!;
        merged.save(additionalJson: {"ble_devices": bleDevices});
      } else {
        log.save(additionalJson: {"ble_devices": bleDevices});
      }
      lastSavedLog = clock.now();
    }
  }

  /// Find the nearest sample index
  int timeToSampleIndex(DateTime time) {
    return nearestIndex(recordGeo.map((e) => e.time).toList(), time.millisecondsSinceEpoch);
  }

  BarometerEvent snapBarometerToGpsAlt(double altitude) {
    return BarometerEvent(ambientFromAlt(altitude, baro?.pressure ?? 1013.25), clock.now());
  }

  /// Returns false if the fix was rejected as a physically impossible jump.
  bool updateGeo(Position position, {bool bypassRecording = false}) {
    gpsFix.value = GpsFixQuality(accuracy: position.accuracy, time: clock.now());
    final verdict = gpsJumpFilter.check(geo, position);
    if (verdict == GpsFixVerdict.reject) {
      debugPrint("Rejected GPS jump: ${position.latitude}, ${position.longitude} @ ${position.timestamp}");
      return false;
    }
    final reanchor = verdict == GpsFixVerdict.reanchor;
    if (reanchor) {
      debugPrint("Re-anchoring GPS after repeated rejected fixes.");
    }

    geoPrev = geo;
    // When re-anchoring, don't derive speed/heading from the jump.
    geo = Geo.fromPosition(position, reanchor ? null : geoPrev, baro, baroAmbient,
        forceGpsAltitude: settingsMgr.forceGpsAltitude.value);

    if (baro == null || settingsMgr.forceGpsAltitude.value) {
      // Use GPS-based vario when barometer unavailable or GPS-only mode enabled
      if (geoPrev != null && !reanchor) {
        final vario = (geo!.alt - geoPrev!.alt) / (geo!.time - geoPrev!.time) * 1000;
        if (vario.isFinite) {
          varioSmooth.value = varioSmooth.value * 0.8 + vario * 0.2;
        } else {
          varioSmooth.value = 0;
        }
      }
    }

    if (geo!.spd.isFinite) {
      speedSmooth.value = speedSmooth.value * 0.8 + geo!.spd * 0.2;
    }
    geo!.ground = sampleDem(geo!.latlng, true);

    if (!appInFocus() && !inFlight) {
      if (geo!.ground != null && (geo!.alt - geo!.ground! < 10) && geo!.spd > 25) {
        debugPrint("Driving detected!");
        setStandby(true);
      }
    }

    recordGeo.add(geo!);

    // Drift barometric ambient toward GPS altitude
    if (inFlight) {
      // adjust slowly
      final target = snapBarometerToGpsAlt(geo!.altGps);
      final current = baroAmbient?.pressure ?? target.pressure;
      final mixed = (current) + (target.pressure - current) * 0.1;
      baroAmbient = BarometerEvent(mixed, target.timestamp);
    } else {
      // snap to GPS altitude
      //debugPrint("Snapping ambient pressure to gps altitude. ${unitConverters[UnitType.distFine]!(geo!.altGps)}");
      baroAmbient = snapBarometerToGpsAlt(geo!.altGps);
    }

    // --- In-Flight detector
    if (globalContext != null && settingsMgr.autoRecordFlight.value) {
      if (inFlight) {
        // Is moving slowly near the ground?
        // Only acount for AGL if ground data available.
        final landingConfig = settingsMgr.landingDetectorConfig;
        if (landingConfig.isLandingCandidate(
            speed: speedSmooth.value,
            agl: geo!.ground != null ? geo!.alt - geo!.ground! : null,
            vario: varioSmooth.value)) {
          if (geoPrev != null) {
            triggerHyst += geo!.time - geoPrev!.time;
          } else {
            triggerHyst += const Duration(seconds: 1).inMilliseconds;
          }
        } else {
          triggerHyst = 0;
        }
        if (landingConfig.shouldLand(triggerHystMs: triggerHyst, sp140Armed: bleDeviceSp140.isArmed())) {
          // Landed!
          stopFlight(bypassRecording: bypassRecording);
        }
      } else {
        // Is moving a normal speed and above the ground?
        // Only acount for AGL if ground data available.
        final launchConfig = settingsMgr.launchDetectorConfig;
        if (launchConfig.isLaunchCandidate(
            speed: geo!.spd, agl: geo!.ground != null ? geo!.alt - geo!.ground! : null, vario: varioSmooth.value)) {
          if (geoPrev != null) {
            triggerHyst += geo!.time - geoPrev!.time;
          } else {
            triggerHyst += const Duration(seconds: 1).inMilliseconds;
          }
        } else {
          triggerHyst = 0;
        }
        if (launchConfig.shouldLaunch(triggerHystMs: triggerHyst, sp140Armed: bleDeviceSp140.isArmed())) {
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
    return true;
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

/// Global single instance
final myTelemetry = MyTelemetry();
