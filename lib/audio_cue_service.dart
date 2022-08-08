import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/providers/my_telemetry.dart';

const List<int?> audioCueIntervals = [
  null,
  15,
  5,
  2,
  1,
];

class AudioCueService {
  final BuildContext context;
  Timer? ticker;
  int? _interval;

  late final SharedPreferences prefs;

  Map<String, int> _config = {
    "myTelemetry": 1,
    "etaNext": 1,
    "etaTrip": 4,
    "groupChat": 1,
    "groupAwareness": 2,
  };

  static const Map<String, List<int>> configOptions = {
    "myTelemetry": [0, 1],
    "etaNext": [0, 1],
    "etaTrip": [0, 4, 2, 1],
    "groupChat": [0, 1],
    "groupAwareness": [0, 1, 2],
  };

  AudioCueService(this.context) {
    SharedPreferences.getInstance().then((instance) {
      prefs = instance;
      final loadedConfig = prefs.getString("audio_cues_config");
      if (loadedConfig != null) {
        _config = jsonDecode(loadedConfig);
      }
      interval = prefs.getInt("audio_cues_interval");
    });
  }

  Map<String, int> get config => _config;
  set config(Map<String, int> newConfig) {
    _config = newConfig;
    prefs.setString("audio_cues_config", jsonEncode(config));
  }

  int? get interval => _interval;
  set interval(int? newInterval) {
    _interval = newInterval;
    prefs.setInt("audio_cues_interval", newInterval ?? 0);
    refreshTicker(newInterval);
  }

  void refreshTicker(int? interval) {
    // kill the previous one
    ticker?.cancel();

    if (interval != null && interval > 0) {
      debugPrint("Audio Cue interval set: $interval");
      // start a new periodic timer quantized to the clock
      Timer(Duration(minutes: interval - DateTime.now().minute % interval), () {
        ticker = Timer.periodic(Duration(minutes: interval), (timer) {
          // Do the thing!
          triggerAudioCue();
        });
      });
    }
  }

  void triggerAudioCue() {
    final myTelemetry = Provider.of<MyTelemetry>(context, listen: false);

    if (myTelemetry.inFlight) {}
  }
}
