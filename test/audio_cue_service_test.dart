import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:easy_localization/src/localization.dart';

import 'package:xcnav/audio_cue_service.dart';
import 'package:xcnav/models/fuel_report.dart';
import 'package:xcnav/models/geo.dart';
import 'package:xcnav/models/message.dart';
import 'package:xcnav/models/pilot.dart';
import 'package:xcnav/providers/active_plan.dart';
import 'package:xcnav/providers/group.dart';
import 'package:xcnav/settings_service.dart';
import 'package:xcnav/tts_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

class ImmutableJsonAssetLoader extends AssetLoader {
  const ImmutableJsonAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String fullPath, Locale locale) async {
    return jsonDecode(await rootBundle.loadString('assets/translations/en.json'));
  }
}

class MockFlutterTts extends Mock implements FlutterTts {
  MockFlutterTts();
  Completer<void>? completer = Completer();

  @override
  Future<dynamic> speak(String text, {bool? focus}) async {
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
      "testPilot": Pilot("testPilot", "John", null, Geo(lat: -37, lng: 122, alt: 100, spd: 4)),
    };
  }
}

void main() {
  late AudioCueService cueService;
  late TtsService ttsService;
  late MockFlutterTts flutterTts;

  SharedPreferences.setMockInitialValues({});
  SharedPreferences.getInstance().then((prefs) {
    settingsMgr = SettingsMgr(prefs);
  });

  // Fuel stuff
  late FuelReport a;
  late FuelReport b;
  late FuelStat stat;

  TestWidgetsFlutterBinding.ensureInitialized();
  var r1 = EasyLocalizationController(
      forceLocale: const Locale('en'),
      path: 'assets/translations/en.json',
      supportedLocales: const [Locale('en')],
      useOnlyLangCode: true,
      useFallbackTranslations: false,
      saveLocale: false,
      onLoadError: (e) {},
      assetLoader: ImmutableJsonAssetLoader());
  // Common Setup
  setUpAll(() async {
    await r1.loadTranslations();
    Localization.load(const Locale('en'), translations: r1.translations);
  });

  // Common Setup
  setUp(() async {
    SharedPreferences.setMockInitialValues({"audio_cues_mode": 1});

    ttsService = TtsService();
    flutterTts = MockFlutterTts();
    settingsMgr.chatTTS.value = true;
    ttsService.instance = flutterTts;
    // First "init" message is just to plug the queue so it waits for the tick to fire
    ttsService.speak(AudioMessage("init"));

    cueService = AudioCueService(
      ttsService: ttsService,
      group: MockGroup(),
      activePlan: ActivePlan(),
    );

    cueService.mode = 2;

    a = FuelReport(DateTime.fromMillisecondsSinceEpoch(0), 10);
    b = FuelReport(DateTime.fromMillisecondsSinceEpoch(0).add(const Duration(minutes: 20)), 8.0);

    stat = FuelStat.fromSamples(a, b, [
      Geo(lat: -37, lng: 122.5, alt: 100, timestamp: a.time.millisecondsSinceEpoch),
      Geo(lat: -37, lng: 122.0, alt: 100, timestamp: b.time.millisecondsSinceEpoch)
    ]);
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

  test("fuel - not reported yet - start", () {
    // no fuel reported yet
    withClock(Clock.fixed(a.time), () => cueService.cueFuel(null, null));

    // first prompt
    expect(ttsService.msgQueue.map((element) => element.text).toList(), ["Report fuel level."]);

    // short time later
    withClock(
        Clock.fixed(a.time.add(
            Duration(seconds: (AudioCueService.intervalLUT["Report Fuel"]![cueService.mode]![0] * 60 - 1).round()))),
        () => cueService.cueFuel(null, null));

    // still only one prompt
    expect(ttsService.msgQueue.map((element) => element.text).toList(), ["Report fuel level."]);

    // short time later + threshold for quick prompt again
    withClock(
        Clock.fixed(a.time.add(
            Duration(seconds: (AudioCueService.intervalLUT["Report Fuel"]![cueService.mode]![0] * 60 + 1).round()))),
        () => cueService.cueFuel(null, null));

    // long enough to have 2 prompts now
    expect(ttsService.msgQueue.map((element) => element.text).toList(), ["Report fuel level.", "Report fuel level."]);

    // short time later + threshold for quick prompt again, but has been reported
    withClock(
        Clock.fixed(a.time.add(
            Duration(seconds: (AudioCueService.intervalLUT["Report Fuel"]![cueService.mode]![0] * 60 + 2).round()))),
        () => cueService.cueFuel(stat, b));

    // still only two prompt
    expect(ttsService.msgQueue.map((element) => element.text).toList(),
        ["Report fuel level.", "Report fuel level.", "9 liters fuel remaining."]);
  });

  test("fuel - reported", () {
    // fuel has been reported
    withClock(Clock.fixed(a.time), () => cueService.cueFuel(stat, b));
    expect(ttsService.msgQueue.map((element) => element.text).toList(), ["10 liters fuel remaining."]);

    // fuel reported and it's been a while
    withClock(
        Clock.fixed(b.time.add(
            Duration(seconds: (AudioCueService.intervalLUT["Report Fuel"]![cueService.mode]![1] * 60 + 1).round()))),
        () => cueService.cueFuel(stat, b));
    expect(ttsService.msgQueue.map((element) => element.text).toList(),
        ['10 liters fuel remaining.', 'Report fuel level.', '3 and a half liters fuel remaining.']);
  });

  test("fuel - critical", () {
    // almost critical
    withClock(Clock.fixed(b.time.add(const Duration(hours: 1))), () => cueService.cueFuel(stat, b));
    expect(ttsService.msgQueue.map((element) => element.text).toList(),
        ["Report fuel level.", "2 liters fuel remaining."]);

    ttsService.msgQueue.clear();

    // critical
    withClock(Clock.fixed(b.time.add(const Duration(hours: 1, minutes: 30))), () => cueService.cueFuel(stat, b));
    expect(ttsService.msgQueue.map((element) => element.text).toList(), ["Fuel level critical!"]);
  });
}
