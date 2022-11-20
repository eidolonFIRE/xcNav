import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/providers/settings.dart';
import 'package:xcnav/tts_service.dart';

class MockFlutterTts extends Mock implements FlutterTts {
  MockFlutterTts();
  Completer<void>? completer = Completer();

  @override
  Future<dynamic> speak(String text) async {
    // print("TTS: Speak: $text");
    return completer!.future;
  }

  @override
  Future<dynamic> setVolume(double value) async {
    // print("TTS: Set Volume: $value");
    return Future.value(null);
  }

  @override
  Future<dynamic> stop() async {
    // print("TTS: Stop");
    return Future.value(null);
  }
}

class MockGroup extends Group {
  MockGroup() {
    pilots = {
      "testPilot": Pilot("testPilot", "John", null, Geo(lat: -37, lng: 122, alt: 100, spd: 4), null),
    };
  }
}

void main() {
  late AudioCueService cueService;
  late TtsService ttsService;
  late MockFlutterTts flutterTts;
  late Settings settings;

  // Common Setup
  setUp(() {
    SharedPreferences.setMockInitialValues({"audio_cues_mode": 1});

    ttsService = TtsService();
    flutterTts = MockFlutterTts();
    settings = Settings();
    settings.chatTts = true;
    ttsService.instance = flutterTts;
    // First "init" message is just to plug the queue so it waits for the tick to fire
    ttsService.speak(AudioMessage("init"));

    cueService = AudioCueService(
      ttsService: ttsService,
      settings: settings,
      group: MockGroup(),
      activePlan: ActivePlan(),
    );
  });

  test("queue priority", () {
    ttsService.speak(AudioMessage("1", priority: 5));
    ttsService.speak(AudioMessage("2", priority: 5));
    ttsService.speak(AudioMessage("3", priority: 2));
    ttsService.speak(AudioMessage("4", priority: 5));
    ttsService.speak(AudioMessage("5", priority: 6));
    ttsService.speak(AudioMessage("6", priority: 2));
    expect(ttsService.msgQueue.map((element) => element.text).toList(), ["3", "6", "1", "2", "4", "5"]);
  });

  test("chatMessage", () {
    cueService.cueChatMessage(Message(0, "testPilot", "message", false));
    cueService.cueChatMessage(Message(0, "testPilot", "message", false));
    cueService.cueChatMessage(Message(0, "testPilot", "message2", false));

    expect(ttsService.msgQueue.map((element) => element.text).toList(), ["John says message.", "John says message2."]);
  });

  test("myTelemetry", () {
    cueService.mode = 2;
    cueService.cueMyTelemetry(Geo(lat: -37, lng: 122.5, alt: 100, timestamp: 0));
    cueService
        .cueMyTelemetry(Geo(lat: -37, lng: 122.5, alt: 100, timestamp: const Duration(seconds: 1).inMilliseconds));
    cueService
        .cueMyTelemetry(Geo(lat: -37, lng: 122.5, alt: 200, timestamp: const Duration(seconds: 2).inMilliseconds));
    cueService
        .cueMyTelemetry(Geo(lat: -37, lng: 122.5, alt: 300, timestamp: const Duration(seconds: 3).inMilliseconds));
    cueService.cueMyTelemetry(
        Geo(lat: -37, lng: 122.5, alt: 400, timestamp: const Duration(seconds: 40).inMilliseconds, spd: 10));

    expect(ttsService.msgQueue.map((element) => element.text).toList(),
        ["Altitude: 400", "Speed: 0", "Altitude: 1400", "Speed: 22"]);

    cueService.cueMyTelemetry(
        Geo(lat: -37, lng: 122.5, alt: 500, timestamp: const Duration(minutes: 10).inMilliseconds, spd: 20));

    expect(ttsService.msgQueue.map((element) => element.text).toList(),
        ["Altitude: 400", "Speed: 0", "Altitude: 1400", "Speed: 22", "Altitude: 1600", "Speed: 45"]);
  });
}
