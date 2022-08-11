import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/main.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/profile.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/tts_service.dart';
import 'package:xcnav/units.dart';

class LastReport<T> {
  final T value;
  late final DateTime timestamp;
  LastReport(this.value, this.timestamp);

  LastReport.now(this.value) {
    timestamp = DateTime.now();
  }
}

class AudioCueService {
  late final Settings settings;
  late final ChatMessages chatMessages;
  late final Group group;
  late final ActivePlan activePlan;
  late final Profile profile;

  /// Current global multiplier
  int? _mode = 0;

  late final SharedPreferences _prefs;

  Map<String, bool> _config = {
    "My Telemetry": true,
    "Next Waypoint": true,
    "Chat Messages": true,
    "Group Awareness": true,
  };

  static const Map<String, IconData> icons = {
    "My Telemetry": Icons.speed,
    "Next Waypoint": Icons.pin_drop,
    "Chat Messages": Icons.chat,
    "Group Awareness": Icons.groups,
  };

  /// Multipier options for all cue trigger thresholds
  static const Map<String, int?> modeOptions = {
    "Off": null,
    "Less": 2,
    "Med": 1,
    "More": 0,
  };

  /// Values are in display value (not necessarily standard internal values)
  static const dynamic precisionLUT = {
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
      0: 0.08,
      1: 0.1,
      2: 0.16,
    }
  };

  /// Values are in minutes
  /// First value is minimum elapsed time since last... will skip trigger
  /// Second value is maximum since last... will force trigger a new one
  static const dynamic intervalLUT = {
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
    "Fuel": {
      0: [0.1, 3.0],
      1: [0.2, 5.0],
      2: [0.5, 15.0],
    },
  };

  static const groupProxmityH = 50;
  static const groupProxmityV = 50;
  static const groupRadialSize = pi / 6.0;

  // --- Hysterisis in reporting
  LastReport<double>? lastAlt;
  LastReport<double>? lastSpd;
  LastReport<int>? lastChat;
  LastReport<double>? lastHdg;
  Map<String, LastReport<Vector>> lastPilotVector = {};
  LastReport<double>? lastLowFuel;

  AudioCueService({
    required this.settings,
    required this.chatMessages,
    required this.group,
    required this.activePlan,
    required this.profile,
  }) {
    SharedPreferences.getInstance().then((instance) {
      _prefs = instance;
      final loadedConfig = _prefs.getString("audio_cues_config");
      if (loadedConfig != null) {
        final loaded = jsonDecode(loadedConfig);
        for (final String name in _config.keys) {
          _config[name] = loaded[name] as bool? ?? true;
        }
      }
      mode = _prefs.getInt("audio_cues_mode");
    });
  }

  Map<String, bool> get config => _config;
  set config(Map<String, bool> newConfig) {
    _config = newConfig;
    _prefs.setString("audio_cues_config", jsonEncode(config));
  }

  int? get mode => _mode;
  set mode(int? newmode) {
    _mode = newmode;
    if (newmode != null) {
      _prefs.setInt("audio_cues_mode", newmode);
    } else {
      _prefs.remove("audio_cues_mode");
    }
  }

  // void refreshTicker(int? interval) {
  //   // kill the previous one
  //   ticker?.cancel();

  //   if (interval != null && interval > 0) {
  //     debugPrint("Audio Cue interval set: $interval");
  //     // start a new periodic timer quantized to the clock
  //     Timer(Duration(minutes: interval - DateTime.now().minute % interval), () {
  //       ticker = Timer.periodic(Duration(minutes: interval), (timer) {
  //         // Do the thing!
  //         triggerAudioCue();
  //       });
  //     });
  //   }
  // }

  void cueMyTelemetry(Geo myGeo) {
    // --- My Telemetry
    if (mode != null && (config["My Telemetry"] ?? false)) {
      // --- Altitude
      final altPrecision = (precisionLUT["alt"][settings.displayUnitsDist][mode] as int).toDouble();
      // Value is transformed into display units before quantizing.
      // Triggers yes if:
      // 1: we don't have a previous value
      // 2: Or, maximum time is reach
      // 3: Or, minimum time satisfied and value past threshold
      final maxInterval = Duration(seconds: ((intervalLUT["My Telemetry"][mode][1]! as double) * 60).toInt());
      final minInterval = Duration(seconds: ((intervalLUT["My Telemetry"][mode][0]! as double) * 60).toInt());
      if (lastAlt == null ||
          DateTime.now().isAfter(lastAlt!.timestamp.add(maxInterval)) ||
          (DateTime.now().isAfter(lastAlt!.timestamp.add(minInterval)) &&
              (lastAlt!.value - convertDistValueFine(settings.displayUnitsDist, myGeo.alt)).abs() >=
                  altPrecision * 0.8)) {
        lastAlt = LastReport.now(
            ((convertDistValueFine(settings.displayUnitsDist, myGeo.alt) / altPrecision).round() * altPrecision)
                .toDouble());

        final text = "Altitude: ${lastAlt!.value.round()}";
        ttsService.speak(AudioMessage(text, volume: 0.75, expires: DateTime.now().add(const Duration(seconds: 4))));
      }

      // --- Speed
      final spdPrecision = (precisionLUT["spd"][settings.displayUnitsSpeed][mode] as int).toDouble();
      if (lastSpd == null ||
          DateTime.now().isAfter(lastSpd!.timestamp.add(maxInterval)) ||
          (DateTime.now().isAfter(lastSpd!.timestamp.add(minInterval)) &&
              ((lastSpd!.value - convertSpeedValue(settings.displayUnitsSpeed, myGeo.spd)).abs() >= spdPrecision))) {
        lastSpd = LastReport.now(convertSpeedValue(settings.displayUnitsSpeed, myGeo.spd));

        final text = "Speed: ${lastSpd!.value.round()}";
        ttsService.speak(AudioMessage(text, volume: 0.75, expires: DateTime.now().add(const Duration(seconds: 4))));
      }
    }
  }

  void cueNextWaypoint(Geo myGeo) {
    // --- Next Waypoint
    if (mode != null && activePlan.selectedWp != null && (config["Next Waypoint"] ?? false)) {
      final maxInterval = Duration(seconds: ((intervalLUT["Next Waypoint"][mode][1]! as double) * 60).toInt());
      final minInterval = Duration(seconds: ((intervalLUT["Next Waypoint"][mode][0]! as double) * 60).toInt());
      final hdgPrecision = precisionLUT["hdg"][mode];

      final target = activePlan.selectedWp!.latlng.length > 1
          ? myGeo.nearestPointOnPath(activePlan.selectedWp!.latlng, activePlan.isReversed).latlng
          : activePlan.selectedWp!.latlng[0];

      final wpHdg = latlngCalc.bearing(myGeo.latLng, target) * pi / 180;
      final relativeHdg = (myGeo.hdg - wpHdg + pi) % (2 * pi) - pi;

      debugPrint("Time Since last Hdg: ${(lastHdg?.timestamp ?? DateTime.now()).difference(DateTime.now()).inSeconds}");

      if (lastHdg == null ||
          DateTime.now().isAfter(lastHdg!.timestamp.add(maxInterval)) ||
          (DateTime.now().isAfter(lastHdg!.timestamp.add(minInterval)) && ((relativeHdg).abs() >= hdgPrecision))) {
        lastHdg = LastReport.now(myGeo.hdg);

        final eta = activePlan.etaToWaypoint(myGeo, myGeo.spd, activePlan.selectedIndex!);
        if (eta.time != null) {
          final etaTime = printHrMinLexical(eta.time!);
          final dist = printValueLexical(
            value: convertDistValueCoarse(settings.displayUnitsDist, eta.distance),
          );
          final deltaDegrees = ((relativeHdg * 180 / pi) / 5).round() * 5;
          final degreesVerbal = "at ${deltaDegrees.abs()} degrees ${relativeHdg > 0 ? "left" : "right"}";
          final int oclock = (((relativeHdg / (2 * pi) * 12.0).round() + 11) % 12) + 1;
          final oclockVerbal = "$oclock o'clock";

          final text =
              "Waypoint: $dist ${unitStrDistCoarseLexical[settings.displayUnitsDist]} out, ${deltaDegrees.abs() <= 45 ? degreesVerbal : oclockVerbal}. ETA $etaTime.";
          ttsService.speak(
              AudioMessage(text, volume: 0.75, priority: 4, expires: DateTime.now().add(const Duration(seconds: 4))));
        }
      }
    }
  }

  void cueFuel(Geo myGeo, double fuel, Duration fuelTimeRemaining) {
    if (mode != null && fuel > 0 && activePlan.selectedWp != null) {
      final etaNext = activePlan.etaToWaypoint(myGeo, myGeo.spd, activePlan.selectedIndex!);
      if (etaNext.time != null && fuelTimeRemaining < etaNext.time!) {
        final minInterval = Duration(seconds: ((intervalLUT["Fuel"][mode][0]! as double) * 60).toInt());

        if (lastLowFuel == null || DateTime.now().isAfter(lastLowFuel!.timestamp.add(minInterval))) {
          // Insufficient fuel!
          lastLowFuel = LastReport.now(fuel);

          const text = "Check fuel needed for next waypoint!";
          ttsService.speak(
              AudioMessage(text, volume: 1.0, priority: 2, expires: DateTime.now().add(const Duration(seconds: 10))));
        }
      }
    }
  }

  void cueChatMessage() {
    if (mode != null && ((config["Chat Messages"] ?? false) && chatMessages.messages.last.pilotId != profile.id)) {
      if (lastChat == null || lastChat!.value < chatMessages.messages.length - 1) {
        // --- Read chat messages

        final msg = chatMessages.messages.last;
        final pilotName = group.pilots[msg.pilotId]?.name;

        final text = "${pilotName != null ? "$pilotName says" : ""} ${msg.text}.";

        ttsService
            .speak(AudioMessage(text, volume: msg.text.toLowerCase().contains("emergency") ? 1.0 : 0.75, priority: 7));
      }
    }
    lastChat = LastReport.now(chatMessages.messages.length - 1);
  }

  void _cuePilots(List<Pilot> pilots, Vector vector) {
    // Borrow the intervals from "Next Waypoint"
    final maxInterval = Duration(seconds: ((intervalLUT["Next Waypoint"][mode][1]! as double) * 60).toInt());
    final minInterval = Duration(seconds: ((intervalLUT["Next Waypoint"][mode][0]! as double) * 60).toInt());

    final hdgPrecision = precisionLUT["hdg"][mode] * 3;
    final distPrecision = precisionLUT["dist"][settings.displayUnitsDist][mode];

    // Will trigger message if:
    // 1: we haven't done so yet
    // 2: max interval reached
    // 3: min interval satisfied and vector is changed
    if (!lastPilotVector.containsKey(pilots.first.id) ||
        DateTime.now().isAfter(lastPilotVector[pilots.first.id]!.timestamp.add(maxInterval)) ||
        (DateTime.now().isAfter(lastPilotVector[pilots.first.id]!.timestamp.add(minInterval)) &&
            ((vector.dist - lastPilotVector[pilots.first.id]!.value.dist).abs() >= distPrecision ||
                (vector.hdg - lastPilotVector[pilots.first.id]!.value.hdg).abs() >= hdgPrecision))) {
      // Record last values
      lastPilotVector[pilots.first.id] = LastReport.now(Vector(vector.hdg, vector.dist));

      // Build the message
      final distVerbal = printValueLexical(value: vector.dist);
      final int oclock = (((vector.hdg / (2 * pi) * 12.0).round() + 11) % 12) + 1;
      final verbalAlt = vector.alt.abs() > groupProxmityV ? (vector.alt > 0 ? " high" : " low") : "";

      final text =
          "${pilots.length == 1 ? "${pilots.first.name} is" : "${pilots.map((e) => e.name).join(" and ")} are"} $distVerbal ${unitStrDistCoarseLexical[settings.displayUnitsDist]} out at $oclock o'clock$verbalAlt.";

      ttsService.speak(
          AudioMessage(text, volume: 0.75, priority: 6, expires: DateTime.now().add(const Duration(seconds: 6))));
    }
  }

  void cueGroupAwareness(Geo myGeo) {
    if (mode != null && (config["Group Awareness"] ?? false)) {
      final activePilots = group.activePilots.toList();
      final Map<String, Vector> pilotVectors =
          Map.fromEntries(activePilots.map((e) => MapEntry(e.id, Vector.fromGeoToGeo(myGeo, e.geo))));

      final Map<String, Pilot> pilotsClose = {};
      final Map<String, Pilot> pilotsAbove = {};
      final Map<String, Pilot> pilotsBelow = {};

      // separate pilots "above" / "close" / "below"
      for (final pilot in activePilots) {
        if (pilotVectors[pilot.id]!.dist <= groupProxmityH) {
          if (pilotVectors[pilot.id]!.alt < -groupProxmityV) {
            // Pilot is above us
            pilotsAbove[pilot.id] = pilot;
          } else if (pilotVectors[pilot.id]!.alt > groupProxmityV) {
            // Pilot is below us
            pilotsBelow[pilot.id] = pilot;
          } else {
            // Pilot is in close proximity
            pilotsClose[pilot.id] = pilot;
          }
          activePilots.remove(pilot);
        }
      }

      // Sort remaining pilots radialy
      activePilots.sort((a, b) => pilotVectors[a.id]!.hdg < pilotVectors[b.id]!.hdg ? 0 : 1);

      /// Binary reduction to cluster into groups.
      /// Start with a list of lists, holding only 1 value.
      final List<List<String>> clusters = activePilots.map((e) => [e.id]).toList();
      int wrapsWithoutChange = 0;
      int i = 0;
      int maxIter = activePilots.length * activePilots.length;

      while (wrapsWithoutChange < (activePilots.length / 2 + 2) && maxIter > 0) {
        final int leftI = (i - 1) % clusters.length;
        final int rightI = (i + 1) % clusters.length;
        // check an entry for nearest valid neighbor
        final left = deltaHdg(pilotVectors[clusters[leftI].first]!.hdg, pilotVectors[clusters[i].last]!.hdg).abs();
        final right = deltaHdg(pilotVectors[clusters[rightI].last]!.hdg, pilotVectors[clusters[i].first]!.hdg).abs();

        if (left < right && left < groupRadialSize) {
          // left is closer and valid to include
          clusters[i].insertAll(0, clusters[leftI]);
          clusters.removeAt(leftI);
          wrapsWithoutChange = 0;
        } else if (right <= left && right < groupRadialSize) {
          // right is closer and valid to include
          clusters[i].insertAll(clusters[i].length, clusters[rightI]);
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

      // if (max num groups met)
      if (clusters.length < 5) {
        // Cue each cluster
        for (final clusterGroup in clusters) {
          if (clusterGroup.length < 3) {
            final vectors = clusterGroup.map((e) => pilotVectors[e]!);
            // Average the altitude and distance
            final double alt = vectors.map((e) => e.alt).reduce((a, b) => a + b) / clusterGroup.length;
            final double dist = vectors.map((e) => e.dist).reduce((a, b) => a + b) / clusterGroup.length;
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
        final text = "${activePilots.length} pilots are dispursed around you.";
        ttsService.speak(
            AudioMessage(text, volume: 0.75, priority: 8, expires: DateTime.now().add(const Duration(seconds: 4))));
      }
    }
  }
}
