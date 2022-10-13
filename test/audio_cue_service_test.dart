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
      "testPilot": Pilot("testPilot", "John", null,
          Geo.fromValues(-37, 122, 100, 0, 0, 4, 0), null),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AudioCueService cueService;
  late TtsService ttsService;
  late MockFlutterTts flutterTts;

  // Common Setup
  setUp(() {
    SharedPreferences.setMockInitialValues({"audio_cues_mode": 1});

    ttsService = TtsService();
    flutterTts = MockFlutterTts();
    ttsService.instance = flutterTts;
    // First "init" message is just to plug the queue so it waits for the tick to fire
    ttsService.speak(AudioMessage("init"));

    cueService = AudioCueService(
      ttsService: ttsService,
      settings: Settings(),
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
    expect(ttsService.msgQueue.map((element) => element.text).toList(),
        ["3", "6", "1", "2", "4", "5"]);
  });

  test("chatMessage", () {
    cueService.cueChatMessage(Message(0, "testPilot", "message", false));
    cueService.cueChatMessage(Message(0, "testPilot", "message", false));
    cueService.cueChatMessage(Message(0, "testPilot", "message2", false));

    expect(ttsService.msgQueue.map((element) => element.text).toList(),
        ["John says message.", "John says message2."]);
  });

  test("myTelemetry", () {
    cueService.cueMyTelemetry(Geo.fromValues(-37, 122.5, 100, 0, 0, 0, 0));
    cueService.cueMyTelemetry(Geo.fromValues(
        -37, 122.5, 100, const Duration(seconds: 1).inMilliseconds, 0, 0, 0));
    cueService.cueMyTelemetry(Geo.fromValues(
        -37, 122.5, 200, const Duration(seconds: 2).inMilliseconds, 0, 0, 0));
    cueService.cueMyTelemetry(Geo.fromValues(
        -37, 122.5, 300, const Duration(seconds: 3).inMilliseconds, 0, 0, 0));
    cueService.cueMyTelemetry(Geo.fromValues(
        -37, 122.5, 400, const Duration(seconds: 40).inMilliseconds, 0, 10, 0));

    expect(ttsService.msgQueue.map((element) => element.text).toList(),
        ["Altitude: 350", "Speed: 0", "Altitude: 1300", "Speed: 22"]);

    cueService.cueMyTelemetry(Geo.fromValues(
        -37, 122.5, 500, const Duration(minutes: 10).inMilliseconds, 0, 20, 0));

    expect(ttsService.msgQueue.map((element) => element.text).toList(), [
      "Altitude: 350",
      "Speed: 0",
      "Altitude: 1300",
      "Speed: 22",
      "Altitude: 1650",
      "Speed: 45"
    ]);
  });
}
