import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/tts_service.dart';
import 'package:xcnav/units.dart';
import 'package:xcnav/widgets/altimeter.dart';

class LastReport<T> {
  final T value;
  late final DateTime timestamp;
  LastReport(this.value, this.timestamp);

  LastReport.now(this.value) {
    timestamp = clock.now();
  }
}

late AudioCueService audioCueService;

class AudioCueService {
  late final TtsService ttsService;
  late final Group group;
  late final ActivePlan activePlan;

  SharedPreferences? _prefs;

  Map<String, bool> _config = {
    "My Telemetry": true,
    "Next Waypoint": true,
    "Group Awareness": true,
    "Report Fuel": true,
    "Fuel Level": true,
  };

  static const Map<String, IconData> icons = {
    "My Telemetry": Icons.speed,
    "Next Waypoint": Icons.pin_drop,
    "Group Awareness": Icons.groups,
    "Report Fuel": Icons.local_gas_station,
    "Fuel Level": Icons.local_gas_station,
  };

  /// Multipier options for all cue trigger thresholds
  static const Map<String, int?> modeOptions = {
    "Off": null,
    "Less": 2,
    "Med": 1,
    "More": 0,
  };

  /// Values are in display value (not necessarily standard internal values)
  static const Map<String, Map<dynamic, List<double>>> precisionLUT = {
    "alt": {
      DisplayUnitsDist.imperial: [50, 100, 200], // ft
      DisplayUnitsDist.metric: [10, 20, 50], // meters
    },
    "dist": {
      DisplayUnitsDist.imperial: [0.25, 0.5, 1.0], // mi
      DisplayUnitsDist.metric: [0.5, 1.0, 2.0], // km
    },
    "spd": {
      DisplayUnitsSpeed.mph: [2, 4, 8],
      DisplayUnitsSpeed.kts: [2, 5, 10],
      DisplayUnitsSpeed.kph: [5, 10, 20],
      DisplayUnitsSpeed.mps: [1, 2, 5],
    },
    "hdg": {
      // heading threshold (radians)
      0: [0.08],
      1: [0.1],
      2: [0.16],
    }
  };

  /// Values are in minutes
  /// First value is minimum elapsed time since last... will skip trigger
  /// Second value is maximum since last... will force trigger a new one
  static const Map<String, Map<int, List<double>>> intervalLUT = {
    "My Telemetry": {
      0: [0.1, 3.0],
      1: [0.2, 5.0],
      2: [0.3, 15.0],
    },
    "Next Waypoint": {
      0: [0.2, 3.0],
      1: [0.5, 5.0],
      2: [1.0, 15.0],
    },

    /// [When fuel low, Read approx fuel level]
    "Fuel Level": {
      0: [1, 15.0],
      1: [2, 20.0],
      2: [5, 25.0],
    },

    /// [Prompt first report, Remind following reports]
    "Report Fuel": {
      0: [2, 20.0],
      1: [5, 30.0],
      2: [10, 45.0],
    },
  };

  static const groupProxmityH = 100;
  static const groupProxmityV = 100;
  static const groupRadialSize = pi / 6.0;

  // --- Hysterisis in reporting
  LastReport<double>? lastAlt;
  LastReport<double>? lastSpd;
  LastReport<String>? lastChat;
  LastReport<double>? lastHdg;
  Map<String, LastReport<Vector>> lastPilotVector = {};
  LastReport<double>? lastFuelReport;
  LastReport<double>? lastFuelLevel;

  AudioCueService({
    required this.ttsService,
    required this.group,
    required this.activePlan,
  }) {
    SharedPreferences.getInstance().then((instance) {
      _prefs = instance;
      final loadedConfig = _prefs?.getString("audio_cues_config");
      if (loadedConfig != null) {
        final loaded = jsonDecode(loadedConfig);
        for (final String name in _config.keys) {
          _config[name] = loaded[name] as bool? ?? true;
        }
      }
      mode = _prefs?.getInt("audio_cues_mode");
    });
  }

  Map<String, bool> get config => _config;
  set config(Map<String, bool> newConfig) {
    _config = newConfig;
    _prefs?.setString("audio_cues_config", jsonEncode(config));
  }

  int? _mode;
  int? get mode => _mode;
  set mode(int? newmode) {
    _mode = newmode;
    if (newmode != null) {
      _prefs?.setInt("audio_cues_mode", newmode);
    } else {
      _prefs?.remove("audio_cues_mode");
    }
  }

  void cueMyTelemetry(Geo myGeo) {
    // --- My Telemetry
    if (mode != null && (config["My Telemetry"] ?? false)) {
      // --- Altitude
      final altPrecision = precisionLUT["alt"]![settingsMgr.displayUnitDist.value]![mode!];
      // Value is transformed into display units before quantizing.
      // Triggers yes if:
      // 1: we don't have a previous value
      // 2: Or, maximum time is reached
      // 3: Or, minimum time satisfied and value past threshold
      final maxInterval = Duration(seconds: (intervalLUT["My Telemetry"]![mode]![1] * 60).toInt());
      final minInterval = Duration(seconds: (intervalLUT["My Telemetry"]![mode]![0] * 60).toInt());
      if (lastAlt == null ||
          DateTime.fromMillisecondsSinceEpoch(myGeo.time).isAfter(lastAlt!.timestamp.add(maxInterval)) ||
          (DateTime.fromMillisecondsSinceEpoch(myGeo.time).isAfter(lastAlt!.timestamp.add(minInterval)) &&
              (lastAlt!.value - unitConverters[UnitType.distFine]!(myGeo.alt)).abs() >= altPrecision * 0.8)) {
        final lastAltSrc =
            settingsMgr.audioCueAltimeter.value == AltimeterMode.msl ? myGeo.alt : (myGeo.alt - (myGeo.ground ?? 0));
        lastAlt = LastReport(
            ((unitConverters[UnitType.distFine]!(lastAltSrc) / altPrecision).round() * altPrecision).toDouble(),
            DateTime.fromMillisecondsSinceEpoch(myGeo.time));

        final text = "Altitude: ${lastAlt!.value.round()}";
        ttsService.speak(AudioMessage(text,
            volume: 0.75, expires: DateTime.fromMillisecondsSinceEpoch(myGeo.time).add(const Duration(seconds: 4))));
      }

      // --- Speed
      final spdPrecision = precisionLUT["spd"]![settingsMgr.displayUnitSpeed.value]![mode!];
      if (lastSpd == null ||
          DateTime.fromMillisecondsSinceEpoch(myGeo.time).isAfter(lastSpd!.timestamp.add(maxInterval)) ||
          (DateTime.fromMillisecondsSinceEpoch(myGeo.time).isAfter(lastSpd!.timestamp.add(minInterval)) &&
              ((lastSpd!.value - unitConverters[UnitType.speed]!(myGeo.spd)).abs() >= spdPrecision))) {
        lastSpd =
            LastReport(unitConverters[UnitType.speed]!(myGeo.spd), DateTime.fromMillisecondsSinceEpoch(myGeo.time));

        final text = "Speed: ${lastSpd!.value.round()}";
        ttsService.speak(AudioMessage(text,
            volume: 0.75, expires: DateTime.fromMillisecondsSinceEpoch(myGeo.time).add(const Duration(seconds: 4))));
      }
    }
  }

  void cueNextWaypoint(Geo myGeo) {
    // --- Next Waypoint
    final selectedWp = activePlan.getSelectedWp();
    if (mode != null && selectedWp != null && (config["Next Waypoint"] ?? false)) {
      final maxInterval = Duration(seconds: (intervalLUT["Next Waypoint"]![mode]![1] * 60).toInt());
      final minInterval = Duration(seconds: (intervalLUT["Next Waypoint"]![mode]![0] * 60).toInt());
      final hdgPrecision = precisionLUT["hdg"]![mode]![0];

      final target = selectedWp.latlng.length > 1 ? myGeo.getIntercept(selectedWp.latlng).latlng : selectedWp.latlng[0];

      final relativeHdg = myGeo.relativeHdgLatlng(target);

      // debugPrint("Time Since last Hdg: ${(lastHdg?.timestamp ?? clock.now()).difference(clock.now()).inSeconds}");

      if (lastHdg == null ||
          clock.now().isAfter(lastHdg!.timestamp.add(maxInterval)) ||
          (clock.now().isAfter(lastHdg!.timestamp.add(minInterval)) && ((relativeHdg).abs() >= hdgPrecision))) {
        lastHdg = LastReport.now(myGeo.hdg);

        final eta = selectedWp.eta(myGeo, myGeo.spd);
        if (eta.time != null) {
          final etaTime = printHrMinLexical(eta.time!);
          final dist = printDoubleLexical(
            value: unitConverters[UnitType.distCoarse]!(eta.distance),
          );
          final deltaDegrees = ((relativeHdg * 180 / pi) / 5).round() * 5;
          final degreesVerbal = "at ${deltaDegrees.abs()} degrees ${relativeHdg > 0 ? "left" : "right"}";
          final int oclock = (((relativeHdg / (2 * pi) * 12.0).round() + 11) % 12) + 1;
          final oclockVerbal = "$oclock o'clock";

          final text =
              "Waypoint: $dist ${getUnitStr(UnitType.distCoarse, lexical: true)} out, ${deltaDegrees.abs() <= 45 ? degreesVerbal : oclockVerbal}. ETA $etaTime.";
          ttsService.speak(
              AudioMessage(text, volume: 0.75, priority: 4, expires: clock.now().add(const Duration(seconds: 4))));
        }
      }
    }
  }

  ///
  void cueFuel(FuelStat? sumFuelStat, FuelReport? fuelReport) {
    if (mode != null) {
      // Prompt to report fuel
      if (
          // Switched on
          (config["Report Fuel"] ?? false) &&
              // havent reported yet OR it's been a while*
              (lastFuelReport == null ||
                  clock.now().isAfter(lastFuelReport!.timestamp.add(Duration(
                      seconds: (intervalLUT["Report Fuel"]![mode]![fuelReport == null ? 0 : 1] * 60).round())))) &&
              // no fuel report yet OR it's been a while
              (fuelReport == null ||
                  clock.now().isAfter(
                      fuelReport.time.add(Duration(seconds: (intervalLUT["Report Fuel"]![mode]![1] * 60).round()))))) {
        lastFuelReport = LastReport.now(0);
        const text = "Report fuel level.";
        ttsService
            .speak(AudioMessage(text, volume: 0.8, priority: 3, expires: clock.now().add(const Duration(seconds: 10))));
      }

      // Advise fuel level
      if ((config["Fuel Level"] ?? false) && sumFuelStat != null && fuelReport != null) {
        final etaEmpty = fuelReport.time.add(sumFuelStat.extrapolateEndurance(fuelReport));
        final estLevel = sumFuelStat.extrapolateToTime(fuelReport, clock.now());

        final minInterval = Duration(seconds: (intervalLUT["Fuel Level"]![mode]![0] * 60).toInt());
        final maxInterval = Duration(seconds: (intervalLUT["Fuel Level"]![mode]![1] * 60).toInt());

        if (lastFuelLevel == null || clock.now().isAfter(lastFuelLevel!.timestamp.add(minInterval))) {
          if (etaEmpty.isBefore(clock.now().add(minInterval)) || estLevel < 0) {
            // Critical fuel
            const text = "Fuel level critical!";
            ttsService.speak(
                AudioMessage(text, volume: 1.0, priority: 0, expires: clock.now().add(const Duration(seconds: 10))));
            lastFuelLevel = LastReport.now(estLevel);
          } else if (lastFuelLevel == null || clock.now().isAfter(lastFuelLevel!.timestamp.add(maxInterval))) {
            // Fuel remaining
            final text =
                "${printDoubleLexical(value: unitConverters[UnitType.fuel]!(estLevel), halfThreshold: 20)} ${getUnitStr(UnitType.fuel, lexical: true)} fuel remaining.";
            ttsService.speak(
                AudioMessage(text, volume: 1.0, priority: 3, expires: clock.now().add(const Duration(seconds: 10))));
            lastFuelLevel = LastReport.now(estLevel);
          }
        }
      }
    }
  }

  void cueChatMessage(Message msg) {
    if (settingsMgr.chatTTS.value) {
      if (lastChat == null || lastChat!.value != msg.pilotId + msg.text) {
        // --- Read chat messages
        final pilotName = group.pilots[msg.pilotId]?.name;

        final text = "${pilotName != null ? "$pilotName says" : ""} ${msg.text}.";

        ttsService
            .speak(AudioMessage(text, volume: msg.text.toLowerCase().contains("emergency") ? 1.0 : 0.75, priority: 7));
      }
    }
    lastChat = LastReport.now(msg.pilotId + msg.text);
  }

  String _assembleNames(List<Pilot> pilots) {
    if (pilots.length > 2) {
      return "${pilots.length} pilots are";
    } else if (pilots.length > 1) {
      return "${pilots.map((e) => e.name).join(" and ")} are";
    } else {
      return "${pilots.first.name} is";
    }
  }

  bool _checkLastPilotVector(String id, Vector vector) {
    // Borrow the intervals from "Next Waypoint"
    final maxInterval = Duration(seconds: (intervalLUT["Next Waypoint"]![mode!]![1] * 60).toInt());
    final minInterval = Duration(seconds: (intervalLUT["Next Waypoint"]![mode!]![0] * 60).toInt());

    final hdgPrecision = precisionLUT["hdg"]![mode!]![0] * 3;
    final distPrecision = precisionLUT["dist"]![settingsMgr.displayUnitDist.value]![mode!];

    // 1: we haven't done so yet
    // 2: max interval reached
    // 3: min interval satisfied and vector is changed

    // if (lastPilotVector.containsKey(id)) {
    //   debugPrint("CheckLastPilotVector: interval = ${lastPilotVector[id]!.timestamp.difference(clock.now())}");
    //   debugPrint("CheckLastPilotVector: dist = ${(vector.dist - lastPilotVector[id]!.value.dist).abs()}");
    //   debugPrint("CheckLastPilotVector: hdg = ${(vector.hdg - lastPilotVector[id]!.value.hdg).abs()}");
    // }

    if (!lastPilotVector.containsKey(id) ||
        clock.now().isAfter(lastPilotVector[id]!.timestamp.add(maxInterval)) ||
        (clock.now().isAfter(lastPilotVector[id]!.timestamp.add(minInterval)) &&
            (unitConverters[UnitType.distCoarse]!((vector.value - lastPilotVector[id]!.value.value).abs()) >=
                    distPrecision ||
                (vector.hdg - lastPilotVector[id]!.value.hdg).abs() >= hdgPrecision))) {
      // Record last values
      lastPilotVector[id] = LastReport.now(Vector(vector.hdg, vector.value));
      return true;
    } else {
      return false;
    }
  }

  void _cuePilots(List<Pilot> pilots, Vector vector) {
    // Make a stable key for that group of pilots so it doesn't re-trigger when they change order in the list.
    var sorted = pilots.map((e) => e.id).toList();
    sorted.sort((a, b) => a.compareTo(b));
    final key = sorted.join(",");
    debugPrint(key);
    if (_checkLastPilotVector(key, vector)) {
      // Build the message
      final distVerbal = printDoubleLexical(value: unitConverters[UnitType.distCoarse]!(vector.value));
      final int oclock = (((vector.hdg / (2 * pi) * 12.0).round() + 11) % 12) + 1;
      final verbalAlt = vector.alt.abs() > groupProxmityV ? (vector.alt < 0 ? " high" : " low") : "";

      final nameVerbal = _assembleNames(pilots);

      final text =
          "$nameVerbal $distVerbal ${getUnitStr(UnitType.distCoarse, lexical: true)} out at $oclock o'clock$verbalAlt.";

      ttsService
          .speak(AudioMessage(text, volume: 0.75, priority: 6, expires: clock.now().add(const Duration(seconds: 6))));
    }
  }

  void _cuePilotsCustom(List<Pilot> pilots, String customMsg) {
    if (_checkLastPilotVector(pilots.first.id, Vector(0, 0))) {
      final text = "${_assembleNames(pilots.toList())} $customMsg";
      ttsService
          .speak(AudioMessage(text, volume: 0.8, priority: 4, expires: clock.now().add(const Duration(seconds: 6))));
    }
  }

  void cueGroupAwareness(Geo myGeo) {
    if (mode != null && (config["Group Awareness"] ?? false)) {
      final activePilots = group.activePilots.toList();
      final List<Pilot> sortedPilots = [];
      final Map<String, Vector> pilotVectors =
          Map.fromEntries(activePilots.map((e) => MapEntry(e.id, Vector.distFromGeoToGeo(myGeo, e.geo!))));

      final List<Pilot> pilotsClose = [];
      final List<Pilot> pilotsAbove = [];
      final List<Pilot> pilotsBelow = [];

      // separate pilots "above" / "close" / "below"
      for (final pilot in activePilots) {
        if (pilotVectors[pilot.id]!.value <= groupProxmityH) {
          if (pilotVectors[pilot.id]!.alt < -groupProxmityV) {
            // Pilot is above us
            pilotsAbove.add(pilot);
          } else if (pilotVectors[pilot.id]!.alt > groupProxmityV) {
            // Pilot is below us
            pilotsBelow.add(pilot);
          } else {
            // Pilot is in close proximity
            pilotsClose.add(pilot);
          }
        } else {
          sortedPilots.add(pilot);
        }
      }

      // debugPrint("PilotsClose: ${pilotsClose.map((e) => e.name).join(", ")}");
      // debugPrint("PilotsAbove: ${pilotsAbove.map((e) => e.name).join(", ")}");
      // debugPrint("PilotsBelow: ${pilotsBelow.map((e) => e.name).join(", ")}");
      // debugPrint("PilotsActive: ${activePilots.map((e) => e.name).join(", ")}");

      /// --- Cue Pilots: proximity close
      if (pilotsClose.isNotEmpty) {
        _cuePilotsCustom(pilotsClose, " close proximity!");
      }

      /// --- Cue Pilots: above
      if (pilotsAbove.isNotEmpty) {
        _cuePilotsCustom(pilotsAbove, " above you.");
      }

      /// --- Cue Pilots: below
      if (pilotsBelow.isNotEmpty) {
        _cuePilotsCustom(pilotsBelow, " belove you");
      }

      // Sort remaining pilots radialy
      sortedPilots.sort((a, b) => pilotVectors[a.id]!.hdg < pilotVectors[b.id]!.hdg ? 0 : 1);

      /// Binary reduction to cluster into groups.
      /// Start with a list of lists, holding only 1 value.
      final List<List<String>> clusters = sortedPilots.map((e) => [e.id]).toList();
      int wrapsWithoutChange = 0;
      int i = 0;
      int maxIter = sortedPilots.length * sortedPilots.length;

      while (wrapsWithoutChange < (sortedPilots.length / 2 + 2) && maxIter > 0 && clusters.length > 1) {
        debugPrint("--- Cluster Iteration $maxIter");
        final int leftI = (i - 1) % clusters.length;
        final int rightI = (i + 1) % clusters.length;
        // check an entry for nearest valid neighbor
        final left = deltaHdg(pilotVectors[clusters[leftI].first]!.hdg, pilotVectors[clusters[i].last]!.hdg).abs();
        final right = deltaHdg(pilotVectors[clusters[rightI].last]!.hdg, pilotVectors[clusters[i].first]!.hdg).abs();

        if (left < right && left < groupRadialSize) {
          // left is closer and valid to include
          clusters[i].insertAll(0, clusters[leftI].toList());
          clusters.removeAt(leftI);
          wrapsWithoutChange = 0;
        } else if (right <= left && right < groupRadialSize) {
          // right is closer and valid to include
          clusters[i].addAll(clusters[rightI].toList());
          clusters.removeAt(rightI);
          wrapsWithoutChange = 0;
        } else {
          // neither left nor right are to be merged
        }

        // iter to next index to attempt merge
        i += 2;
        if (i >= clusters.length) {
          // smart wrap
          i = (clusters.length - i + 1) % 2;
          wrapsWithoutChange++;
        }

        // Don't let us do this too long;
        maxIter--;
      }

      // debugPrint("Clusters: ${clusters.toString()}");

      // if (max num groups met)
      if (clusters.length < 5) {
        // Cue each cluster
        for (final clusterGroup in clusters) {
          if (clusterGroup.length < 3) {
            final vectors = clusterGroup.map((e) => pilotVectors[e]!);
            // Average the altitude and distance
            final double alt = vectors.map((e) => e.alt).reduce((a, b) => a + b) / clusterGroup.length;
            final double dist = vectors.map((e) => e.value).reduce((a, b) => a + b) / clusterGroup.length;
            // Find center of the cluster
            double? hdgSum;
            double hdgPrev = 0;
            for (final each in clusterGroup) {
              if (hdgSum == null) {
                hdgSum = pilotVectors[each]!.hdg;
                hdgPrev = hdgSum;
              } else {
                hdgPrev += deltaHdg(hdgPrev, pilotVectors[each]!.hdg);
                hdgSum += hdgPrev;
              }
            }

            _cuePilots(clusterGroup.map((e) => group.pilots[e]!).toList(),
                Vector(deltaHdg(hdgSum! / clusterGroup.length, 0), dist, alt: alt));
          }
        }
      } else {
        // pilots are too dispursed to group sufficiently
        if (_checkLastPilotVector("scattered", Vector(0, 0))) {
          final text = "${activePilots.length} pilots are scattered around you.";
          ttsService.speak(
              AudioMessage(text, volume: 0.75, priority: 8, expires: clock.now().add(const Duration(seconds: 4))));
        }
      }
    }
  }
}
