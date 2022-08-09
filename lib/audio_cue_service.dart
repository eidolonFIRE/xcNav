import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/main.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/chat_messages.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/my_telemetry.dart';
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
  final BuildContext _context;
  late final Settings _settings;
  late final MyTelemetry _myTelemetry;
  late final ChatMessages _chatMessages;
  late final Group _group;
  late final ActivePlan _activePlan;
  late final Profile _profile;

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

  // --- Hysterisis in reporting
  LastReport<double>? lastAlt;
  LastReport<double>? lastSpd;
  LastReport<int>? lastChat;
  LastReport<double>? lastHdg;
  Map<String, LastReport<Vector>> lastPilotVector = {};
  LastReport<double>? lastLowFuel;

  AudioCueService(this._context) {
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

    _settings = Provider.of<Settings>(_context, listen: false);
    _myTelemetry = Provider.of<MyTelemetry>(_context, listen: false);
    _chatMessages = Provider.of<ChatMessages>(_context, listen: false);
    _group = Provider.of<Group>(_context, listen: false);
    _activePlan = Provider.of<ActivePlan>(_context, listen: false);
    _profile = Provider.of<Profile>(_context, listen: false);
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

  void cueMyTelemetry() {
    // --- My Telemetry
    if (_myTelemetry.inFlight && mode != null && (config["My Telemetry"] ?? false)) {
      // --- Altitude
      final altPrecision = (precisionLUT["alt"][_settings.displayUnitsDist][mode] as int).toDouble();
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
              (lastAlt!.value - convertDistValueFine(_settings.displayUnitsDist, _myTelemetry.geo.alt)).abs() >=
                  altPrecision * 0.8)) {
        lastAlt = LastReport.now(
            ((convertDistValueFine(_settings.displayUnitsDist, _myTelemetry.geo.alt) / altPrecision).round() *
                    altPrecision)
                .toDouble());

        final text = "Altitude: ${lastAlt!.value.round()}";
        ttsService.speak(AudioMessage(text, volume: 0.75, expires: DateTime.now().add(const Duration(seconds: 4))));
      }

      // --- Speed
      final spdPrecision = (precisionLUT["spd"][_settings.displayUnitsSpeed][mode] as int).toDouble();
      if (lastSpd == null ||
          DateTime.now().isAfter(lastSpd!.timestamp.add(maxInterval)) ||
          (DateTime.now().isAfter(lastSpd!.timestamp.add(minInterval)) &&
              ((lastSpd!.value - convertSpeedValue(_settings.displayUnitsSpeed, _myTelemetry.geo.spd)).abs() >=
                  spdPrecision))) {
        lastSpd = LastReport.now(convertSpeedValue(_settings.displayUnitsSpeed, _myTelemetry.geo.spd));

        final text = "Speed: ${lastSpd!.value.round()}";
        ttsService.speak(AudioMessage(text, volume: 0.75, expires: DateTime.now().add(const Duration(seconds: 4))));
      }
    }

    cueNextWaypoint();
    cueGroupAwareness();
    cueFuel();
  }

  void cueNextWaypoint() {
    // --- Next Waypoint
    if (_myTelemetry.inFlight && mode != null && _activePlan.selectedWp != null && (config["Next Waypoint"] ?? false)) {
      final maxInterval = Duration(seconds: ((intervalLUT["Next Waypoint"][mode][1]! as double) * 60).toInt());
      final minInterval = Duration(seconds: ((intervalLUT["Next Waypoint"][mode][0]! as double) * 60).toInt());
      final hdgPrecision = precisionLUT["hdg"][mode];

      final target = _activePlan.selectedWp!.latlng.length > 1
          ? _myTelemetry.geo.nearestPointOnPath(_activePlan.selectedWp!.latlng, _activePlan.isReversed).latlng
          : _activePlan.selectedWp!.latlng[0];

      final wpHdg = latlngCalc.bearing(_myTelemetry.geo.latLng, target) * pi / 180;
      final deltaHdg = (_myTelemetry.geo.hdg - wpHdg + pi) % (2 * pi) - pi;

      debugPrint("Time Since last Hdg: ${(lastHdg?.timestamp ?? DateTime.now()).difference(DateTime.now()).inSeconds}");

      if (lastHdg == null ||
          DateTime.now().isAfter(lastHdg!.timestamp.add(maxInterval)) ||
          (DateTime.now().isAfter(lastHdg!.timestamp.add(minInterval)) && ((deltaHdg).abs() >= hdgPrecision))) {
        lastHdg = LastReport.now(_myTelemetry.geo.hdg);

        final eta = _activePlan.etaToWaypoint(_myTelemetry.geo, _myTelemetry.geo.spd, _activePlan.selectedIndex!);
        final etaTime = printHrMinLexical(milliseconds: eta.time);
        final dist = printValueLexical(
          value: convertDistValueCoarse(_settings.displayUnitsDist, eta.distance),
        );
        final deltaDegrees = ((deltaHdg * 180 / pi) / 5).round() * 5;
        final text =
            "Waypoint: $dist ${unitStrDistCoarseLexical[_settings.displayUnitsDist]} out, at ${deltaDegrees.abs()} degrees ${deltaHdg > 0 ? "left" : "right"}. ETA $etaTime.";
        ttsService.speak(
            AudioMessage(text, volume: 0.75, priority: 4, expires: DateTime.now().add(const Duration(seconds: 4))));
      }
    }
  }

  void cueFuel() {
    if (_myTelemetry.inFlight &&
        mode != null &&
        _myTelemetry.fuel > 0 &&
        _activePlan.selectedWp != null &&
        _myTelemetry.fuelTimeRemaining <
            _activePlan.etaToWaypoint(_myTelemetry.geo, _myTelemetry.geo.spd, _activePlan.selectedIndex!).time) {
      final minInterval = Duration(seconds: ((intervalLUT["Fuel"][mode][0]! as double) * 60).toInt());

      if (lastLowFuel == null || DateTime.now().isAfter(lastLowFuel!.timestamp.add(minInterval))) {
        // Insufficient fuel!
        lastLowFuel = LastReport.now(_myTelemetry.fuel);

        const text = "Check fuel needed for next waypoint!";
        ttsService.speak(
            AudioMessage(text, volume: 1.0, priority: 2, expires: DateTime.now().add(const Duration(seconds: 10))));
      }
    }
  }

  void cueChatMessage() {
    if (mode != null && ((config["Chat Messages"] ?? false) && _chatMessages.messages.last.pilotId != _profile.id)) {
      if (lastChat == null || lastChat!.value < _chatMessages.messages.length - 1) {
        // --- Read chat messages

        final msg = _chatMessages.messages.last;
        final pilotName = _group.pilots[msg.pilotId]?.name;

        final text = "${pilotName != null ? "$pilotName says" : ""} ${msg.text}.";

        ttsService
            .speak(AudioMessage(text, volume: msg.text.toLowerCase().contains("emergency") ? 1.0 : 0.75, priority: 7));
      }
    }
    lastChat = LastReport.now(_chatMessages.messages.length - 1);
  }

  void cueGroupAwareness() {
    // --- Group Awareness
    if (_myTelemetry.inFlight && mode != null && (config["Group Awareness"] ?? false)) {
      // --- Small Group - Update on positions of each pilot
      if (_group.activePilots.length < 3) {
        // Borrow the intervals from "Next Waypoint"
        final maxInterval = Duration(seconds: ((intervalLUT["Next Waypoint"][mode][1]! as double) * 60).toInt());
        final minInterval = Duration(seconds: ((intervalLUT["Next Waypoint"][mode][0]! as double) * 60).toInt());

        final hdgPrecision = precisionLUT["hdg"][mode] * 3;
        final distPrecision = precisionLUT["dist"][_settings.displayUnitsDist][mode];

        // relative position of each pilot
        for (final pilot in _group.activePilots) {
          final relativeDist =
              convertDistValueCoarse(_settings.displayUnitsDist, _myTelemetry.geo.distanceTo(pilot.geo));
          final relativeHdg = _myTelemetry.geo.relativeHdg(pilot.geo);

          // Will trigger message if:
          // 1: we haven't done so yet
          // 2: max interval reached
          // 3: min interval satisfied and vector is changed
          if (!lastPilotVector.containsKey(pilot.id) ||
              DateTime.now().isAfter(lastPilotVector[pilot.id]!.timestamp.add(maxInterval)) ||
              (DateTime.now().isAfter(lastPilotVector[pilot.id]!.timestamp.add(minInterval)) &&
                  ((relativeDist - lastPilotVector[pilot.id]!.value.dist).abs() >= distPrecision ||
                      (relativeHdg - lastPilotVector[pilot.id]!.value.hdg).abs() >= hdgPrecision))) {
            // Record last values
            lastPilotVector[pilot.id] = LastReport.now(Vector(relativeHdg, relativeDist));

            // Build the message
            final distVerbal = printValueLexical(value: relativeDist);
            final int oclock = (((relativeHdg / (2 * pi) * 12.0).round() + 11) % 12) + 1;
            final relativeAlt = pilot.geo.alt - _myTelemetry.geo.alt;
            final verbalAlt = relativeAlt.abs() > 50 ? (relativeAlt > 0 ? " high" : " low") : "";

            final text =
                "${pilot.name} is $distVerbal ${unitStrDistCoarseLexical[_settings.displayUnitsDist]} out at $oclock o'clock$verbalAlt.";

            ttsService.speak(
                AudioMessage(text, volume: 0.75, priority: 6, expires: DateTime.now().add(const Duration(seconds: 6))));
          }
        }
      } else {
        // TODO: large group awareness
        // --- Large Group
        // (calculate group center of mass, group spread (standard deviation?) )
        // how most of the group is around you
        // disenters / lagging behind
        // nearby people
      }

      // TODO: other group awareness warnings
      // --- Any group size
      // Pilot is flying towards you
    }
  }
}
